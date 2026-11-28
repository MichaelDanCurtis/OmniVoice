use std::sync::{Arc, LazyLock, Mutex, OnceLock};

use harper_core::linting::{LintGroup, LintKind, Linter};
use harper_core::spell::FstDictionary;
use harper_core::{Dialect, Document};
use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GrammarCheckRequest {
    pub text: String,
    #[serde(default)]
    pub protected_terms: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GrammarEditInfo {
    pub start: usize,
    pub end: usize,
    pub original: String,
    pub message: String,
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GrammarCheckResponse {
    pub text: String,
    pub applied_count: usize,
    pub engine: String,
    #[serde(default)]
    pub edits: Vec<GrammarEditInfo>,
}

struct HarperRuntime {
    dictionary: Arc<FstDictionary>,
    linter: Mutex<LintGroup>,
}

static HARPER_RUNTIME: OnceLock<HarperRuntime> = OnceLock::new();

static PROTECTED_TOKEN_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"https?://\S+|\b\S+@\S+\.\S+\b|(?:/|~/)[^\s]+|\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b[A-Za-z]+_[A-Za-z0-9_]+\b|\b[A-Z]{2,}[0-9]*\b",
    )
    .expect("valid protected token regex")
});

fn harper() -> &'static HarperRuntime {
    HARPER_RUNTIME.get_or_init(|| {
        let dictionary = FstDictionary::curated();
        let linter = LintGroup::new_curated(dictionary.clone(), Dialect::American);
        HarperRuntime {
            dictionary,
            linter: Mutex::new(linter),
        }
    })
}

/// Runs Harper (`harper-core`) grammar & punctuation checking on dictated text in <1-3 ms.
///
/// Protects Personal Dictionary terms, URLs, emails, paths, code identifiers, ALL-CAPS acronyms,
/// and capitalized proper nouns from unintended spelling rewrites.
pub fn check_and_correct_grammar(
    text: &str,
    protected_terms: &[String],
) -> GrammarCheckResponse {
    if text.trim().is_empty() || text.chars().count() > 8_000 {
        return GrammarCheckResponse {
            text: text.to_string(),
            applied_count: 0,
            engine: "harper-core".to_string(),
            edits: Vec::new(),
        };
    }

    let runtime = harper();
    let document = Document::new_plain_english(text, &*runtime.dictionary);
    let mut lints = {
        let mut linter = runtime.linter.lock().expect("harper linter lock poisoned");
        linter.lint(&document)
    };

    if lints.is_empty() {
        return GrammarCheckResponse {
            text: text.to_string(),
            applied_count: 0,
            engine: "harper-core".to_string(),
            edits: Vec::new(),
        };
    }

    let protected_char_spans = collect_protected_char_spans(text, protected_terms);
    let mut chars: Vec<char> = text.chars().collect();

    // Sort descending by span start so right-to-left edits keep earlier char indices intact.
    lints.sort_by(|a, b| {
        b.span
            .start
            .cmp(&a.span.start)
            .then_with(|| b.span.end.cmp(&a.span.end))
    });

    let mut applied_edits: Vec<GrammarEditInfo> = Vec::new();
    let mut last_applied_start = usize::MAX;

    for lint in lints {
        let start = lint.span.start;
        let end = lint.span.end;
        if start > end || end > chars.len() || end > last_applied_start {
            continue;
        }
        if overlaps_any(start, end, &protected_char_spans) {
            continue;
        }
        let Some(suggestion) = lint.suggestions.first() else {
            continue;
        };

        let original: String = chars[start..end].iter().collect();

        // Guardrail: never let spelling rules rewrite capitalized words (likely proper nouns / product names).
        if matches!(lint.lint_kind, LintKind::Spelling) {
            if original.chars().next().is_some_and(|c| c.is_uppercase()) && start > 0 {
                continue;
            }
        }
        // Only auto-apply safe, high-signal dictation lint categories (skip stylistic preferences).
        if !is_safe_dictation_lint_kind(lint.lint_kind) {
            continue;
        }

        suggestion.apply(lint.span, &mut chars);
        last_applied_start = start;
        applied_edits.push(GrammarEditInfo {
            start,
            end,
            original,
            message: lint.message.clone(),
            kind: format!("{:?}", lint.lint_kind),
        });
    }

    applied_edits.reverse();
    let updated: String = chars.into_iter().collect();
    let applied_count = applied_edits.len();

    GrammarCheckResponse {
        text: updated,
        applied_count,
        engine: "harper-core".to_string(),
        edits: applied_edits,
    }
}

fn is_safe_dictation_lint_kind(kind: LintKind) -> bool {
    matches!(
        kind,
        LintKind::Grammar
            | LintKind::Punctuation
            | LintKind::Spelling
            | LintKind::Capitalization
            | LintKind::Repetition
            | LintKind::Typo
            | LintKind::Agreement
            | LintKind::BoundaryError
            | LintKind::Formatting
            | LintKind::Miscellaneous
            | LintKind::WordChoice
            | LintKind::Usage
    )
}

fn collect_protected_char_spans(text: &str, protected_terms: &[String]) -> Vec<(usize, usize)> {
    let mut byte_to_char: Vec<usize> = vec![0; text.len() + 1];
    let mut char_idx = 0usize;
    for (byte_idx, ch) in text.char_indices() {
        byte_to_char[byte_idx] = char_idx;
        let next_byte = byte_idx + ch.len_utf8();
        for b in (byte_idx + 1)..next_byte {
            byte_to_char[b] = char_idx;
        }
        char_idx += 1;
    }
    byte_to_char[text.len()] = char_idx;

    let mut spans: Vec<(usize, usize)> = Vec::new();

    for m in PROTECTED_TOKEN_REGEX.find_iter(text) {
        spans.push((byte_to_char[m.start()], byte_to_char[m.end()]));
    }

    let lower = text.to_lowercase();
    // Map lowercase search matches only when byte lengths align cleanly (ASCII-safe fast path),
    // otherwise fall back to char-slice case-insensitive scan.
    let lower_chars: Vec<char> = text.chars().map(|c| c.to_ascii_lowercase()).collect();
    for term in protected_terms {
        let cleaned = term.trim();
        if cleaned.chars().count() < 2 {
            continue;
        }
        let needle: Vec<char> = cleaned.chars().map(|c| c.to_ascii_lowercase()).collect();
        if needle.len() > lower_chars.len() {
            continue;
        }
        if lower.is_ascii() && cleaned.is_ascii() {
            let needle_str = cleaned.to_ascii_lowercase();
            let mut offset = 0usize;
            while let Some(pos) = lower[offset..].find(&needle_str) {
                let start = offset + pos;
                let end = start + needle_str.len();
                spans.push((byte_to_char[start], byte_to_char[end]));
                offset = end;
            }
        } else {
            let mut i = 0usize;
            while i + needle.len() <= lower_chars.len() {
                if lower_chars[i..i + needle.len()] == needle[..] {
                    spans.push((i, i + needle.len()));
                    i += needle.len();
                } else {
                    i += 1;
                }
            }
        }
    }

    spans
}

fn overlaps_any(start: usize, end: usize, protected: &[(usize, usize)]) -> bool {
    protected.iter().any(|&(p_start, p_end)| start < p_end && p_start < end)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn harper_fixes_basic_grammar_and_articles() {
        let res = check_and_correct_grammar("This is a apple.", &[]);
        assert_eq!(res.text, "This is an apple.");
        assert!(res.applied_count >= 1);
    }

    #[test]
    fn harper_fixes_repeated_words_and_preserves_protected_terms() {
        let res = check_and_correct_grammar(
            "I opened the the OmniSpeak app to test NeroNook.",
            &["OmniSpeak".to_string(), "NeroNook".to_string()],
        );
        assert_eq!(res.text, "I opened the OmniSpeak app to test NeroNook.");
    }

    #[test]
    fn harper_leaves_clean_sentences_untouched() {
        let clean = "Let's check the page to the left, and then deploy the build.";
        let res = check_and_correct_grammar(clean, &[]);
        assert_eq!(res.text, clean);
        assert_eq!(res.applied_count, 0);
    }
}

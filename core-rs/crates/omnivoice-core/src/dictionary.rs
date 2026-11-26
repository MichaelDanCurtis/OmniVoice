use std::collections::HashSet;
use std::ops::Range;
use std::sync::LazyLock;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearnedCorrection {
    pub from: String,
    pub to: String,
}

static COMMON_WORDS: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    [
        "the", "a", "an", "and", "or", "but", "if", "then", "than", "so", "because", "as",
        "to", "too", "two", "of", "in", "on", "at", "by", "for", "with", "about", "from",
        "into", "over", "under", "again", "further", "here", "there", "their", "theyre",
        "they're", "your", "youre", "you're", "its", "it's", "whos", "who's", "whose",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
        "my", "mine", "our", "ours", "his", "hers", "this", "that", "these", "those",
        "is", "am", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "should", "could", "can", "may", "might",
        "must", "shall", "not", "no", "yes", "all", "any", "some", "few", "more", "most",
        "other", "such", "only", "own", "same", "very", "just", "now", "well", "also",
        "up", "down", "out", "off", "above", "below", "between", "through", "during",
        "before", "after", "while", "where", "when", "why", "how", "what", "which",
        "fast", "slow", "quick", "good", "bad", "new", "old", "great", "high", "low",
        "right", "left", "first", "last", "next", "many", "much", "long", "little",
        "go", "going", "went", "gone", "get", "got", "make", "made", "see", "saw",
        "know", "knew", "think", "thought", "take", "took", "come", "came", "want",
        "use", "used", "find", "found", "give", "gave", "tell", "told", "ask", "work",
        "to's", "lose", "loose", "affect", "effect", "accept", "except", "then's",
    ]
    .into_iter()
    .collect()
});

pub struct CorrectionClassifier;

impl CorrectionClassifier {
    /// Classify a post-insertion edit (where `inserted_char_range` is a char-index range within `before`)
    /// into a learnable vocabulary correction when appropriate.
    pub fn classify(
        before: &str,
        after: &str,
        inserted_char_range: Range<usize>,
    ) -> Option<LearnedCorrection> {
        let before_chars: Vec<char> = before.chars().collect();
        let after_chars: Vec<char> = after.chars().collect();

        let max_prefix = before_chars.len().min(after_chars.len());
        let mut prefix = 0;
        while prefix < max_prefix && before_chars[prefix] == after_chars[prefix] {
            prefix += 1;
        }

        let mut suffix = 0;
        while suffix < (max_prefix - prefix)
            && before_chars[before_chars.len() - 1 - suffix]
                == after_chars[after_chars.len() - 1 - suffix]
        {
            suffix += 1;
        }

        let mut before_start = prefix;
        let mut before_end = before_chars.len() - suffix;
        let mut after_end = after_chars.len() - suffix;
        if before_start > before_end || prefix > after_end {
            return None;
        }
        if before_start == before_end && prefix == after_end {
            return None;
        }

        while before_start > 0 && !before_chars[before_start - 1].is_whitespace() {
            before_start -= 1;
        }
        while before_end < before_chars.len() && !before_chars[before_end].is_whitespace() {
            before_end += 1;
            after_end += 1;
        }
        let after_start = before_start;

        let from: String = before_chars[before_start..before_end].iter().collect();
        let to: String = after_chars[after_start..after_end].iter().collect();
        let from = from.trim().to_string();
        let to = to.trim().to_string();
        if from.is_empty() || to.is_empty() || from == to {
            return None;
        }

        // Overlap with inserted range
        if !(before_start < inserted_char_range.end && inserted_char_range.start < before_end) {
            return None;
        }

        if token_count(&from) > 2 || token_count(&to) != 1 || !Self::is_likely_vocabulary(&to) {
            return None;
        }

        Some(LearnedCorrection { from, to })
    }

    pub fn is_likely_vocabulary(word: &str) -> bool {
        if token_count(word) != 1 {
            return false;
        }
        let cleaned = word.trim_matches(|c: char| !c.is_alphanumeric() && c != '\'');
        if cleaned.is_empty() {
            return false;
        }
        let mut chars = cleaned.chars();
        let first = chars.next();
        if chars.any(|c| c.is_uppercase()) {
            return true;
        }
        if first.is_some_and(|c| c.is_uppercase()) {
            return true;
        }
        !COMMON_WORDS.contains(cleaned.to_lowercase().as_str())
    }
}

fn token_count(text: &str) -> usize {
    text.split_whitespace().count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn learns_proper_noun_and_brand_corrections() {
        let before = "Open fig ma please.";
        let after = "Open Figma please.";
        let correction = CorrectionClassifier::classify(before, after, 0..before.chars().count());
        assert_eq!(
            correction,
            Some(LearnedCorrection {
                from: "fig ma".to_string(),
                to: "Figma".to_string(),
            })
        );
    }

    #[test]
    fn rejects_common_homophone_grammar_edits() {
        let before = "Go over there.";
        let after = "Go over their.";
        assert_eq!(
            CorrectionClassifier::classify(before, after, 0..before.chars().count()),
            None
        );
    }

    #[test]
    fn ignores_edits_outside_inserted_span() {
        let before = "Old fig ma. New text.";
        let after = "Old Figma. New text.";
        // Inserted span only covers "New text."
        let start = "Old fig ma. ".chars().count();
        assert_eq!(
            CorrectionClassifier::classify(before, after, start..before.chars().count()),
            None
        );
    }
}

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

pub const DEFAULT_SIMILARITY_THRESHOLD: f64 = 0.8;
pub const DEFAULT_MINIMUM_TOKEN_COUNT: usize = 3;
pub const DEFAULT_OVERLAP_TOLERANCE_MS: i64 = 1_500;
pub const TWO_TRACK_THEM_SPEAKER_ID: &str = "them";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EchoSegmentRef {
    pub speaker_id: String,
    pub text: String,
    pub start_ms: i64,
    pub end_ms: Option<i64>,
}

pub struct EchoSuppression;

impl EchoSuppression {
    pub fn is_echo_of_system_audio(
        mic_text: &str,
        mic_start_ms: i64,
        mic_end_ms: Option<i64>,
        segments: &[EchoSegmentRef],
        similarity_threshold: f64,
        minimum_token_count: usize,
        overlap_tolerance_ms: i64,
    ) -> bool {
        let mic_tokens = tokens(mic_text);
        if mic_tokens.len() < minimum_token_count {
            return false;
        }

        let mic_end = mic_end_ms.unwrap_or(mic_start_ms);
        let mut system_tokens = HashSet::new();
        for segment in segments {
            if segment.speaker_id != TWO_TRACK_THEM_SPEAKER_ID {
                continue;
            }
            let seg_end = segment.end_ms.unwrap_or(segment.start_ms);
            let overlaps = mic_start_ms <= seg_end + overlap_tolerance_ms
                && segment.start_ms <= mic_end + overlap_tolerance_ms;
            if overlaps {
                system_tokens.extend(tokens(&segment.text));
            }
        }
        if system_tokens.is_empty() {
            return false;
        }

        let shared = mic_tokens.intersection(&system_tokens).count();
        (shared as f64) / (mic_tokens.len() as f64) >= similarity_threshold
    }
}

fn tokens(text: &str) -> HashSet<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suppresses_speaker_bleed_from_system_track() {
        let segments = vec![EchoSegmentRef {
            speaker_id: "them".to_string(),
            text: "We should ship the release on Tuesday morning".to_string(),
            start_ms: 1000,
            end_ms: Some(4000),
        }];
        assert!(EchoSuppression::is_echo_of_system_audio(
            "We should ship the release on Tuesday",
            1200,
            Some(3900),
            &segments,
            DEFAULT_SIMILARITY_THRESHOLD,
            DEFAULT_MINIMUM_TOKEN_COUNT,
            DEFAULT_OVERLAP_TOLERANCE_MS,
        ));
    }

    #[test]
    fn fails_open_on_short_acknowledgements_and_double_talk() {
        let segments = vec![EchoSegmentRef {
            speaker_id: "them".to_string(),
            text: "Yeah that makes sense".to_string(),
            start_ms: 1000,
            end_ms: Some(2500),
        }];
        assert!(!EchoSuppression::is_echo_of_system_audio(
            "yeah",
            1100,
            Some(1400),
            &segments,
            DEFAULT_SIMILARITY_THRESHOLD,
            DEFAULT_MINIMUM_TOKEN_COUNT,
            DEFAULT_OVERLAP_TOLERANCE_MS,
        ));
        assert!(!EchoSuppression::is_echo_of_system_audio(
            "Actually I disagree with that timeline completely",
            1100,
            Some(2500),
            &segments,
            DEFAULT_SIMILARITY_THRESHOLD,
            DEFAULT_MINIMUM_TOKEN_COUNT,
            DEFAULT_OVERLAP_TOLERANCE_MS,
        ));
    }
}

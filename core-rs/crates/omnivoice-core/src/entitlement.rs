use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum EntitlementStatus {
    None,
    Trialing { ends_at_unix: i64 },
    Active,
    Expired,
}

impl EntitlementStatus {
    pub fn is_entitled(&self) -> bool {
        matches!(self, Self::Active | Self::Trialing { .. })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntitlementSnapshot {
    pub status: EntitlementStatus,
    pub fetched_at_unix: i64,
}

pub struct EntitlementGate;

impl EntitlementGate {
    pub fn effective_status(
        cached: Option<&EntitlementSnapshot>,
        now_unix: i64,
        grace_days: i64,
    ) -> EntitlementStatus {
        let Some(cached) = cached else {
            return EntitlementStatus::None;
        };

        if let EntitlementStatus::Trialing { ends_at_unix } = cached.status {
            if now_unix >= ends_at_unix {
                return EntitlementStatus::Expired;
            }
        }

        if !cached.status.is_entitled() {
            return cached.status.clone();
        }

        let grace_seconds = grace_days.max(0) * 86_400;
        if now_unix - cached.fetched_at_unix > grace_seconds {
            return EntitlementStatus::Expired;
        }

        cached.status.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trial_expiry_is_authoritative_even_within_offline_grace() {
        let snap = EntitlementSnapshot {
            status: EntitlementStatus::Trialing { ends_at_unix: 1_000 },
            fetched_at_unix: 900,
        };
        assert_eq!(
            EntitlementGate::effective_status(Some(&snap), 999, 7),
            EntitlementStatus::Trialing { ends_at_unix: 1_000 }
        );
        assert_eq!(
            EntitlementGate::effective_status(Some(&snap), 1_000, 7),
            EntitlementStatus::Expired
        );
    }

    #[test]
    fn active_subscription_honors_offline_grace_then_expires() {
        let snap = EntitlementSnapshot {
            status: EntitlementStatus::Active,
            fetched_at_unix: 10_000,
        };
        assert_eq!(
            EntitlementGate::effective_status(Some(&snap), 10_000 + 7 * 86_400, 7),
            EntitlementStatus::Active
        );
        assert_eq!(
            EntitlementGate::effective_status(Some(&snap), 10_000 + 7 * 86_400 + 1, 7),
            EntitlementStatus::Expired
        );
    }
}

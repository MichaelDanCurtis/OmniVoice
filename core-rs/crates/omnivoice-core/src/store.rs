use std::collections::HashMap;
use std::path::Path;
use std::sync::Mutex;

use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("conversation not found: {0}")]
    NotFound(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptRecord {
    pub id: String,
    pub created_at: String,
    pub source: String,
    pub raw_text: String,
    pub cleaned_text: Option<String>,
    pub provider: Option<String>,
    pub style: Option<String>,
    pub audio_bytes: Option<i64>,
    pub sample_rate: Option<i64>,
    pub duration_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EngineEvent {
    pub id: String,
    pub created_at: String,
    pub event_type: String,
    pub message: String,
    pub level: String,
    pub detail: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConversationSessionRecord {
    pub id: String,
    pub title: String,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub capture_mode: String,
    pub asr_provider: String,
    pub diarization_provider: String,
    pub external_processing_enabled: bool,
    pub source_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConversationSegmentRecord {
    pub id: String,
    pub session_id: String,
    pub speaker_id: String,
    pub speaker_display_name: String,
    pub start_ms: i64,
    pub end_ms: Option<i64>,
    pub text: String,
    pub state: String,
    pub confidence: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConversationAssistCardRecord {
    pub id: String,
    pub session_id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub source_references: Vec<String>,
    pub confidence: Option<f64>,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ConversationDetail {
    pub session: ConversationSessionRecord,
    pub segments: Vec<ConversationSegmentRecord>,
    pub assist_cards: Vec<ConversationAssistCardRecord>,
}

pub struct RuntimeStore {
    conn: Mutex<Connection>,
}

impl RuntimeStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        if let Some(parent) = path.as_ref().parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let conn = Connection::open(path)?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    pub fn in_memory() -> Result<Self, StoreError> {
        let conn = Connection::open_in_memory()?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    fn init_schema(&self) -> Result<(), StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        conn.execute_batch(
            r#"
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS transcripts (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                source TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                cleaned_text TEXT,
                provider TEXT,
                style TEXT,
                audio_bytes INTEGER,
                sample_rate INTEGER,
                duration_ms INTEGER
            );
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                event_type TEXT NOT NULL,
                message TEXT NOT NULL,
                level TEXT NOT NULL,
                detail_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                capture_mode TEXT NOT NULL,
                asr_provider TEXT NOT NULL,
                diarization_provider TEXT NOT NULL,
                external_processing_enabled INTEGER NOT NULL,
                source_ids_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS conversation_segments (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                speaker_id TEXT NOT NULL,
                speaker_display_name TEXT NOT NULL,
                start_ms INTEGER NOT NULL,
                end_ms INTEGER,
                text TEXT NOT NULL,
                state TEXT NOT NULL,
                confidence REAL
            );
            CREATE TABLE IF NOT EXISTS conversation_assist_cards (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                source_references_json TEXT NOT NULL,
                confidence REAL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            "#,
        )?;
        Ok(())
    }

    pub fn record_transcript(
        &self,
        source: &str,
        raw_text: &str,
        cleaned_text: Option<&str>,
        provider: Option<&str>,
        style: Option<&str>,
        audio_bytes: Option<i64>,
        sample_rate: Option<i64>,
        duration_ms: Option<i64>,
    ) -> Result<TranscriptRecord, StoreError> {
        let record = TranscriptRecord {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: source.to_string(),
            raw_text: raw_text.to_string(),
            cleaned_text: cleaned_text.map(ToString::to_string),
            provider: provider.map(ToString::to_string),
            style: style.map(ToString::to_string),
            audio_bytes,
            sample_rate,
            duration_ms,
        };
        let conn = self.conn.lock().expect("store mutex poisoned");
        conn.execute(
            "INSERT INTO transcripts (id, created_at, source, raw_text, cleaned_text, provider, style, audio_bytes, sample_rate, duration_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                record.id,
                record.created_at,
                record.source,
                record.raw_text,
                record.cleaned_text,
                record.provider,
                record.style,
                record.audio_bytes,
                record.sample_rate,
                record.duration_ms,
            ],
        )?;
        Ok(record)
    }

    pub fn list_transcripts(&self, limit: usize) -> Result<Vec<TranscriptRecord>, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let mut stmt = conn.prepare(
            "SELECT id, created_at, source, raw_text, cleaned_text, provider, style, audio_bytes, sample_rate, duration_ms
             FROM transcripts ORDER BY rowid DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], |row| {
            Ok(TranscriptRecord {
                id: row.get(0)?,
                created_at: row.get(1)?,
                source: row.get(2)?,
                raw_text: row.get(3)?,
                cleaned_text: row.get(4)?,
                provider: row.get(5)?,
                style: row.get(6)?,
                audio_bytes: row.get(7)?,
                sample_rate: row.get(8)?,
                duration_ms: row.get(9)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn record_event(
        &self,
        event_type: &str,
        message: &str,
        level: &str,
        detail: serde_json::Value,
    ) -> Result<EngineEvent, StoreError> {
        let event = EngineEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            event_type: event_type.to_string(),
            message: message.to_string(),
            level: level.to_string(),
            detail,
        };
        let detail_json = serde_json::to_string(&event.detail).unwrap_or_else(|_| "{}".to_string());
        let conn = self.conn.lock().expect("store mutex poisoned");
        conn.execute(
            "INSERT INTO events (id, created_at, event_type, message, level, detail_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                event.id,
                event.created_at,
                event.event_type,
                event.message,
                event.level,
                detail_json,
            ],
        )?;
        Ok(event)
    }

    pub fn list_events(&self, limit: usize) -> Result<Vec<EngineEvent>, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let mut stmt = conn.prepare(
            "SELECT id, created_at, event_type, message, level, detail_json
             FROM events ORDER BY rowid DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], |row| {
            let detail_json: String = row.get(5)?;
            let detail = serde_json::from_str(&detail_json).unwrap_or(serde_json::json!({}));
            Ok(EngineEvent {
                id: row.get(0)?,
                created_at: row.get(1)?,
                event_type: row.get(2)?,
                message: row.get(3)?,
                level: row.get(4)?,
                detail,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn create_conversation(
        &self,
        title: &str,
        capture_mode: &str,
        asr_provider: &str,
        diarization_provider: &str,
        external_processing_enabled: bool,
        source_ids: Vec<String>,
    ) -> Result<ConversationSessionRecord, StoreError> {
        let session = ConversationSessionRecord {
            id: Uuid::new_v4().to_string(),
            title: title.to_string(),
            started_at: Utc::now().to_rfc3339(),
            ended_at: None,
            capture_mode: capture_mode.to_string(),
            asr_provider: asr_provider.to_string(),
            diarization_provider: diarization_provider.to_string(),
            external_processing_enabled,
            source_ids,
        };
        let source_ids_json =
            serde_json::to_string(&session.source_ids).unwrap_or_else(|_| "[]".to_string());
        let conn = self.conn.lock().expect("store mutex poisoned");
        conn.execute(
            "INSERT INTO conversations (id, title, started_at, ended_at, capture_mode, asr_provider, diarization_provider, external_processing_enabled, source_ids_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                session.id,
                session.title,
                session.started_at,
                session.ended_at,
                session.capture_mode,
                session.asr_provider,
                session.diarization_provider,
                if session.external_processing_enabled { 1 } else { 0 },
                source_ids_json,
            ],
        )?;
        Ok(session)
    }

    pub fn list_conversations(&self, limit: usize) -> Result<Vec<ConversationSessionRecord>, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let mut stmt = conn.prepare(
            "SELECT id, title, started_at, ended_at, capture_mode, asr_provider, diarization_provider, external_processing_enabled, source_ids_json
             FROM conversations ORDER BY rowid DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], Self::map_conversation_row)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn conversation_detail(&self, session_id: &str) -> Result<ConversationDetail, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let session = conn
            .query_row(
                "SELECT id, title, started_at, ended_at, capture_mode, asr_provider, diarization_provider, external_processing_enabled, source_ids_json
                 FROM conversations WHERE id = ?1",
                [session_id],
                Self::map_conversation_row,
            )
            .optional()?
            .ok_or_else(|| StoreError::NotFound(session_id.to_string()))?;

        let mut stmt = conn.prepare(
            "SELECT id, session_id, speaker_id, speaker_display_name, start_ms, end_ms, text, state, confidence
             FROM conversation_segments WHERE session_id = ?1 ORDER BY start_ms ASC, rowid ASC",
        )?;
        let segments = stmt
            .query_map([session_id], |row| {
                Ok(ConversationSegmentRecord {
                    id: row.get(0)?,
                    session_id: row.get(1)?,
                    speaker_id: row.get(2)?,
                    speaker_display_name: row.get(3)?,
                    start_ms: row.get(4)?,
                    end_ms: row.get(5)?,
                    text: row.get(6)?,
                    state: row.get(7)?,
                    confidence: row.get(8)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        let mut card_stmt = conn.prepare(
            "SELECT id, session_id, kind, title, body, source_references_json, confidence, status, created_at
             FROM conversation_assist_cards WHERE session_id = ?1 ORDER BY rowid ASC",
        )?;
        let assist_cards = card_stmt
            .query_map([session_id], |row| {
                let refs_json: String = row.get(5)?;
                let source_references = serde_json::from_str(&refs_json).unwrap_or_default();
                Ok(ConversationAssistCardRecord {
                    id: row.get(0)?,
                    session_id: row.get(1)?,
                    kind: row.get(2)?,
                    title: row.get(3)?,
                    body: row.get(4)?,
                    source_references,
                    confidence: row.get(6)?,
                    status: row.get(7)?,
                    created_at: row.get(8)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(ConversationDetail {
            session,
            segments,
            assist_cards,
        })
    }

    pub fn add_conversation_segment(
        &self,
        session_id: &str,
        speaker_id: &str,
        speaker_display_name: &str,
        start_ms: i64,
        end_ms: Option<i64>,
        text: &str,
        state: &str,
        confidence: Option<f64>,
    ) -> Result<ConversationSegmentRecord, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let exists: Option<String> = conn
            .query_row(
                "SELECT id FROM conversations WHERE id = ?1",
                [session_id],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_none() {
            return Err(StoreError::NotFound(session_id.to_string()));
        }

        let segment = ConversationSegmentRecord {
            id: Uuid::new_v4().to_string(),
            session_id: session_id.to_string(),
            speaker_id: speaker_id.to_string(),
            speaker_display_name: speaker_display_name.to_string(),
            start_ms,
            end_ms,
            text: text.to_string(),
            state: state.to_string(),
            confidence,
        };
        conn.execute(
            "INSERT INTO conversation_segments (id, session_id, speaker_id, speaker_display_name, start_ms, end_ms, text, state, confidence)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                segment.id,
                segment.session_id,
                segment.speaker_id,
                segment.speaker_display_name,
                segment.start_ms,
                segment.end_ms,
                segment.text,
                segment.state,
                segment.confidence,
            ],
        )?;
        Ok(segment)
    }

    pub fn stop_conversation(&self, session_id: &str) -> Result<ConversationSessionRecord, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let ended_at = Utc::now().to_rfc3339();
        let affected = conn.execute(
            "UPDATE conversations SET ended_at = COALESCE(ended_at, ?1) WHERE id = ?2",
            params![ended_at, session_id],
        )?;
        if affected == 0 {
            return Err(StoreError::NotFound(session_id.to_string()));
        }
        conn.query_row(
            "SELECT id, title, started_at, ended_at, capture_mode, asr_provider, diarization_provider, external_processing_enabled, source_ids_json
             FROM conversations WHERE id = ?1",
            [session_id],
            Self::map_conversation_row,
        )
        .map_err(StoreError::from)
    }

    pub fn update_conversation(
        &self,
        session_id: &str,
        title: Option<&str>,
        speaker_names: &HashMap<String, String>,
        segment_texts: &HashMap<String, String>,
    ) -> Result<ConversationDetail, StoreError> {
        {
            let conn = self.conn.lock().expect("store mutex poisoned");
            let exists: Option<String> = conn
                .query_row(
                    "SELECT id FROM conversations WHERE id = ?1",
                    [session_id],
                    |row| row.get(0),
                )
                .optional()?;
            if exists.is_none() {
                return Err(StoreError::NotFound(session_id.to_string()));
            }
            if let Some(new_title) = title.map(str::trim).filter(|t| !t.is_empty()) {
                conn.execute(
                    "UPDATE conversations SET title = ?1 WHERE id = ?2",
                    params![new_title, session_id],
                )?;
            }
            for (speaker_id, display_name) in speaker_names {
                conn.execute(
                    "UPDATE conversation_segments SET speaker_display_name = ?1 WHERE session_id = ?2 AND speaker_id = ?3",
                    params![display_name, session_id, speaker_id],
                )?;
            }
            for (segment_id, text) in segment_texts {
                let updated = conn.execute(
                    "UPDATE conversation_segments SET text = ?1 WHERE session_id = ?2 AND id = ?3",
                    params![text, session_id, segment_id],
                )?;
                if updated == 0 {
                    return Err(StoreError::NotFound(format!("segment {segment_id}")));
                }
            }
        }
        self.conversation_detail(session_id)
    }

    pub fn add_assist_card(
        &self,
        session_id: &str,
        kind: &str,
        title: &str,
        body: &str,
        source_references: Vec<String>,
        confidence: Option<f64>,
    ) -> Result<ConversationAssistCardRecord, StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let exists: Option<String> = conn
            .query_row(
                "SELECT id FROM conversations WHERE id = ?1",
                [session_id],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_none() {
            return Err(StoreError::NotFound(session_id.to_string()));
        }

        let card = ConversationAssistCardRecord {
            id: Uuid::new_v4().to_string(),
            session_id: session_id.to_string(),
            kind: kind.to_string(),
            title: title.to_string(),
            body: body.to_string(),
            source_references,
            confidence,
            status: "active".to_string(),
            created_at: Utc::now().to_rfc3339(),
        };
        let refs_json = serde_json::to_string(&card.source_references).unwrap_or_else(|_| "[]".to_string());
        conn.execute(
            "INSERT INTO conversation_assist_cards (id, session_id, kind, title, body, source_references_json, confidence, status, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                card.id,
                card.session_id,
                card.kind,
                card.title,
                card.body,
                refs_json,
                card.confidence,
                card.status,
                card.created_at,
            ],
        )?;
        Ok(card)
    }

    pub fn delete_conversation(&self, session_id: &str) -> Result<(), StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let affected = conn.execute("DELETE FROM conversations WHERE id = ?1", [session_id])?;
        if affected == 0 {
            return Err(StoreError::NotFound(session_id.to_string()));
        }
        Ok(())
    }

    pub fn counts(&self) -> Result<(usize, usize, usize), StoreError> {
        let conn = self.conn.lock().expect("store mutex poisoned");
        let transcripts: i64 =
            conn.query_row("SELECT COUNT(*) FROM transcripts", [], |r| r.get(0))?;
        let events: i64 = conn.query_row("SELECT COUNT(*) FROM events", [], |r| r.get(0))?;
        let conversations: i64 =
            conn.query_row("SELECT COUNT(*) FROM conversations", [], |r| r.get(0))?;
        Ok((
            transcripts as usize,
            events as usize,
            conversations as usize,
        ))
    }

    fn map_conversation_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ConversationSessionRecord> {
        let external_int: i64 = row.get(7)?;
        let source_ids_json: String = row.get(8)?;
        let source_ids = serde_json::from_str(&source_ids_json).unwrap_or_default();
        Ok(ConversationSessionRecord {
            id: row.get(0)?,
            title: row.get(1)?,
            started_at: row.get(2)?,
            ended_at: row.get(3)?,
            capture_mode: row.get(4)?,
            asr_provider: row.get(5)?,
            diarization_provider: row.get(6)?,
            external_processing_enabled: external_int != 0,
            source_ids,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stores_transcripts_events_and_conversations() {
        let store = RuntimeStore::in_memory().unwrap();
        let tx = store
            .record_transcript(
                "cleanup",
                "raw text",
                Some("Raw text."),
                Some("parakeet-tdt-coreml-ane"),
                Some("neutral"),
                Some(32_000),
                Some(16_000),
                Some(140),
            )
            .unwrap();
        assert_eq!(store.list_transcripts(10).unwrap().len(), 1);
        assert_eq!(store.list_transcripts(10).unwrap()[0].id, tx.id);

        store
            .record_event("cleanup.completed", "ok", "info", serde_json::json!({"n": 1}))
            .unwrap();
        assert_eq!(store.list_events(10).unwrap().len(), 1);

        let convo = store
            .create_conversation(
                "Design Sync",
                "microphone_and_system_audio",
                "parakeet-tdt-coreml-ane",
                "sortformer-coreml",
                false,
                vec!["mic".to_string()],
            )
            .unwrap();
        let seg = store
            .add_conversation_segment(&convo.id, "me", "Me", 500, Some(1200), "Hey there", "settled", Some(0.95))
            .unwrap();
        store
            .add_assist_card(
                &convo.id,
                "action_item",
                "Follow up",
                "Send updated benchmark numbers",
                vec![seg.id.clone()],
                Some(0.9),
            )
            .unwrap();
        let mut names = HashMap::new();
        names.insert("me".to_string(), "Michael".to_string());
        let mut edits = HashMap::new();
        edits.insert(seg.id.clone(), "Hey team".to_string());
        let updated = store
            .update_conversation(&convo.id, Some("Design Review"), &names, &edits)
            .unwrap();
        assert_eq!(updated.session.title, "Design Review");
        assert_eq!(updated.segments[0].speaker_display_name, "Michael");
        assert_eq!(updated.segments[0].text, "Hey team");
        assert_eq!(updated.assist_cards.len(), 1);
        assert_eq!(updated.assist_cards[0].title, "Follow up");

        let stopped = store.stop_conversation(&convo.id).unwrap();
        assert!(stopped.ended_at.is_some());

        store.delete_conversation(&convo.id).unwrap();
        assert!(matches!(
            store.conversation_detail(&convo.id),
            Err(StoreError::NotFound(_))
        ));
    }
}

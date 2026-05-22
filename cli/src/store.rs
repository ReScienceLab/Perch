use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use uuid::Uuid;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct Session {
    pub id: String,
    pub agent: String,
    pub session_id: String,
    pub working_dir: String,
    pub title: String,
    pub note: String,
    pub priority: String,
    pub status: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub resume_cmd: String,
}

fn sessions_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config/perch/sessions.json")
}

fn load_from_path(path: &Path) -> Result<Vec<Session>> {
    if !path.exists() {
        return Ok(vec![]);
    }
    let text = std::fs::read_to_string(path)?;
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

fn save_to_path(path: &Path, sessions: &[Session]) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, serde_json::to_string_pretty(sessions)?)?;
    Ok(())
}

pub fn add(
    title: String,
    agent: String,
    session_id: String,
    working_dir: Option<String>,
    note: String,
) -> Result<()> {
    let output = add_to_path(
        &sessions_path(),
        title,
        agent,
        session_id,
        working_dir,
        note,
    )?;
    println!("{output}");
    Ok(())
}

fn add_to_path(
    path: &Path,
    title: String,
    agent: String,
    session_id: String,
    working_dir: Option<String>,
    note: String,
) -> Result<String> {
    let working_dir = working_dir.unwrap_or_else(|| {
        std::env::current_dir()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    });

    let session_id = normalize_session_id(&agent, &session_id);
    let resume_cmd = resume_command(&agent, &session_id, &working_dir);
    let output = title.clone();
    let now = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    let mut sessions = load_from_path(path)?;
    if let Some(index) = sessions
        .iter()
        .position(|s| s.agent == agent && s.session_id == session_id)
    {
        let keep_id = sessions[index].id.clone();
        sessions[index].working_dir = working_dir;
        sessions[index].title = title;
        sessions[index].note = note;
        sessions[index].status = "pending".to_string();
        sessions[index].resume_cmd = resume_cmd;
        sessions[index].updated_at = Some(now);
        sessions.retain(|s| s.id == keep_id || !(s.agent == agent && s.session_id == session_id));
        save_to_path(path, &sessions)?;
        return Ok(output);
    }

    let entry = Session {
        id: Uuid::new_v4().to_string(),
        agent,
        session_id,
        working_dir,
        title,
        note,
        priority: "medium".to_string(),
        status: "pending".to_string(),
        created_at: now,
        updated_at: None,
        resume_cmd,
    };

    sessions.push(entry);
    save_to_path(path, &sessions)?;
    Ok(output)
}

fn normalize_session_id(agent: &str, session_id: &str) -> String {
    if agent == "codex" && session_id.starts_with("rollout-") {
        let parts: Vec<&str> = session_id.split('-').collect();
        if parts.len() >= 10 {
            return parts[parts.len() - 5..].join("-");
        }
    }
    session_id.to_string()
}

impl Session {
    fn display_timestamp(&self) -> &str {
        self.updated_at.as_deref().unwrap_or(&self.created_at)
    }
}

fn resume_command(agent: &str, session_id: &str, working_dir: &str) -> String {
    match agent {
        "codex" => format!("codex resume {session_id}"),
        "pi" => format!("pi --session {session_id}"),
        "windsurf" => format!("windsurf {working_dir}"),
        "cursor" => format!("cursor {working_dir}"),
        "trae" => format!("trae {working_dir}"),
        "droid" => format!("droid --resume {session_id}"),
        "goose" => format!("goose session -r --name {session_id}"),
        "opencode" => format!("opencode session resume {session_id}"),
        "kiro" => format!("kiro-cli chat --resume-id {session_id}"),
        "amp" => format!("amp threads continue {session_id}"),
        "hermes" => format!("hermes --resume {session_id}"),
        _ => format!("claude --resume {session_id}"),
    }
}

pub fn list(all: bool, json: bool) -> Result<()> {
    let output = list_from_path(&sessions_path(), all, json)?;
    print!("{output}");
    Ok(())
}

fn list_from_path(path: &Path, all: bool, json: bool) -> Result<String> {
    let sessions = load_from_path(path)?;
    let filtered: Vec<&Session> = sessions
        .iter()
        .filter(|s| all || s.status == "pending")
        .collect();

    if json {
        return Ok(format!("{}\n", serde_json::to_string_pretty(&filtered)?));
    }

    if filtered.is_empty() {
        return Ok("No sessions.\n".to_string());
    }

    let mut output = String::new();
    for s in &filtered {
        let age = time_ago(s.display_timestamp());
        output.push_str(&format!(
            "{:.8}  {:<6}  {}  {}\n",
            s.id, s.agent, s.title, age
        ));
    }
    Ok(output)
}

pub fn done(id_or_prefix: Option<String>, session_id: Option<String>) -> Result<()> {
    let output = set_status_at_path(&sessions_path(), id_or_prefix, session_id, "done", "Done")?;
    println!("{output}");
    Ok(())
}

pub fn reopen(id_or_prefix: Option<String>, session_id: Option<String>) -> Result<()> {
    let output = set_status_at_path(
        &sessions_path(),
        id_or_prefix,
        session_id,
        "pending",
        "Reopened",
    )?;
    println!("{output}");
    Ok(())
}

fn set_status_at_path(
    path: &Path,
    id_or_prefix: Option<String>,
    session_id: Option<String>,
    status: &str,
    verb: &str,
) -> Result<String> {
    let mut sessions = load_from_path(path)?;

    let matches: Vec<usize> = match (id_or_prefix, session_id) {
        (_, Some(sid)) => sessions
            .iter()
            .enumerate()
            .filter(|(_, s)| s.session_id == sid)
            .map(|(i, _)| i)
            .collect(),
        (Some(prefix), None) => sessions
            .iter()
            .enumerate()
            .filter(|(_, s)| s.id.starts_with(&prefix))
            .map(|(i, _)| i)
            .collect(),
        (None, None) => bail!("Provide a session ID or --session-id"),
    };

    match matches.len() {
        0 => bail!("No session found"),
        1 => {
            let title = sessions[matches[0]].title.clone();
            sessions[matches[0]].status = status.to_string();
            save_to_path(path, &sessions)?;
            Ok(format!("{verb}: {title}"))
        }
        _ => {
            for i in &matches {
                sessions[*i].status = status.to_string();
            }
            save_to_path(path, &sessions)?;
            Ok(format!("{verb}: {} sessions", matches.len()))
        }
    }
}

fn time_ago(iso: &str) -> String {
    time_ago_at(iso, Utc::now())
}

fn time_ago_at(iso: &str, now: DateTime<Utc>) -> String {
    let Ok(dt) = iso.parse::<DateTime<Utc>>() else {
        return String::new();
    };
    let secs = (now - dt).num_seconds().max(0) as u64;
    let hours = secs / 3600;
    let days = secs / 86400;
    if hours < 1 {
        "< 1h".to_string()
    } else if days < 1 {
        format!("{hours}h ago")
    } else {
        format!("{days}d ago")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn temp_sessions_path(name: &str) -> PathBuf {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!(
            "perch-store-tests-{}-{name}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        dir.join(".config/perch/sessions.json")
    }

    fn sample_session(id: &str, session_id: &str, title: &str, status: &str) -> Session {
        Session {
            id: id.to_string(),
            agent: "claude".to_string(),
            session_id: session_id.to_string(),
            working_dir: "/tmp/project".to_string(),
            title: title.to_string(),
            note: String::new(),
            priority: "medium".to_string(),
            status: status.to_string(),
            created_at: "2026-05-18T10:00:00Z".to_string(),
            updated_at: None,
            resume_cmd: format!("claude --resume {session_id}"),
        }
    }

    fn read_sessions(path: &Path) -> Vec<Session> {
        let text = fs::read_to_string(path).unwrap();
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn load_returns_empty_for_missing_or_invalid_files() {
        let path = temp_sessions_path("load");
        assert_eq!(load_from_path(&path).unwrap(), Vec::<Session>::new());

        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "not json").unwrap();
        assert_eq!(load_from_path(&path).unwrap(), Vec::<Session>::new());
    }

    #[test]
    fn save_creates_parent_directories_and_round_trips_sessions() {
        let path = temp_sessions_path("save");
        let sessions = vec![sample_session("abc", "sid", "Saved", "pending")];

        save_to_path(&path, &sessions).unwrap();

        assert_eq!(load_from_path(&path).unwrap(), sessions);
    }

    #[test]
    fn add_writes_defaults_and_uses_explicit_working_directory() {
        let path = temp_sessions_path("add");

        let output = add_to_path(
            &path,
            "My title".to_string(),
            "codex".to_string(),
            "codex-session".to_string(),
            Some("/tmp/work tree".to_string()),
            "remember this".to_string(),
        )
        .unwrap();

        assert_eq!(output, "My title");
        let saved = read_sessions(&path);
        assert_eq!(saved.len(), 1);
        let entry = &saved[0];
        assert!(Uuid::parse_str(&entry.id).is_ok());
        assert_eq!(entry.agent, "codex");
        assert_eq!(entry.session_id, "codex-session");
        assert_eq!(entry.working_dir, "/tmp/work tree");
        assert_eq!(entry.title, "My title");
        assert_eq!(entry.note, "remember this");
        assert_eq!(entry.priority, "medium");
        assert_eq!(entry.status, "pending");
        assert!(entry.created_at.parse::<DateTime<Utc>>().is_ok());
        assert_eq!(entry.resume_cmd, "codex resume codex-session");
    }

    #[test]
    fn add_upserts_existing_agent_session_and_reopens_it() {
        let path = temp_sessions_path("upsert");
        let existing = sample_session("existing-id", "same-session", "Old", "done");
        save_to_path(&path, std::slice::from_ref(&existing)).unwrap();

        let output = add_to_path(
            &path,
            "Updated".to_string(),
            "claude".to_string(),
            "same-session".to_string(),
            Some("/tmp/updated".to_string()),
            "new note".to_string(),
        )
        .unwrap();

        assert_eq!(output, "Updated");
        let saved = read_sessions(&path);
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].id, "existing-id");
        assert_eq!(saved[0].created_at, existing.created_at);
        assert!(saved[0].updated_at.is_some());
        assert_eq!(saved[0].title, "Updated");
        assert_eq!(saved[0].working_dir, "/tmp/updated");
        assert_eq!(saved[0].note, "new note");
        assert_eq!(saved[0].status, "pending");
        assert_eq!(saved[0].resume_cmd, "claude --resume same-session");
    }

    #[test]
    fn add_upsert_deduplicates_older_matching_entries() {
        let path = temp_sessions_path("upsert-dedupe");
        let first = sample_session("first-id", "same-session", "First", "done");
        let duplicate = sample_session("duplicate-id", "same-session", "Duplicate", "pending");
        let other = sample_session("other-id", "other-session", "Other", "pending");
        save_to_path(&path, &[first.clone(), duplicate, other.clone()]).unwrap();

        add_to_path(
            &path,
            "Updated".to_string(),
            "claude".to_string(),
            "same-session".to_string(),
            Some("/tmp/updated".to_string()),
            String::new(),
        )
        .unwrap();

        let saved = read_sessions(&path);
        assert_eq!(saved.len(), 2);
        assert_eq!(saved[0].id, first.id);
        assert_eq!(saved[0].title, "Updated");
        assert_eq!(saved[1], other);
    }

    #[test]
    fn add_appends_to_existing_sessions() {
        let path = temp_sessions_path("append");
        let existing = sample_session("existing", "old-session", "Existing", "pending");
        save_to_path(&path, std::slice::from_ref(&existing)).unwrap();

        add_to_path(
            &path,
            "New".to_string(),
            "pi".to_string(),
            "new-session".to_string(),
            Some("/tmp/new".to_string()),
            String::new(),
        )
        .unwrap();

        let saved = read_sessions(&path);
        assert_eq!(saved.len(), 2);
        assert_eq!(saved[0], existing);
        assert_eq!(saved[1].title, "New");
        assert_eq!(saved[1].resume_cmd, "pi --session new-session");
    }

    #[test]
    fn codex_add_normalizes_rollout_filename_to_resumable_uuid() {
        let path = temp_sessions_path("codex-rollout-normalize");

        add_to_path(
            &path,
            "Codex".to_string(),
            "codex".to_string(),
            "rollout-2026-05-18T13-17-18-019e3984-633d-7ac2-9f70-297ce65e79be".to_string(),
            Some("/tmp/project".to_string()),
            String::new(),
        )
        .unwrap();

        let saved = read_sessions(&path);
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].session_id, "019e3984-633d-7ac2-9f70-297ce65e79be");
        assert_eq!(
            saved[0].resume_cmd,
            "codex resume 019e3984-633d-7ac2-9f70-297ce65e79be"
        );
    }

    #[test]
    fn resume_command_covers_every_supported_agent_and_default_claude() {
        let cases = [
            ("claude", "claude --resume sid"),
            ("codex", "codex resume sid"),
            ("pi", "pi --session sid"),
            ("windsurf", "windsurf /tmp/project"),
            ("cursor", "cursor /tmp/project"),
            ("trae", "trae /tmp/project"),
            ("droid", "droid --resume sid"),
            ("goose", "goose session -r --name sid"),
            ("opencode", "opencode session resume sid"),
            ("kiro", "kiro-cli chat --resume-id sid"),
            ("amp", "amp threads continue sid"),
            ("hermes", "hermes --resume sid"),
            ("unknown", "claude --resume sid"),
        ];

        for (agent, expected) in cases {
            assert_eq!(resume_command(agent, "sid", "/tmp/project"), expected);
        }
    }

    #[test]
    fn list_reports_no_sessions_for_empty_store() {
        let path = temp_sessions_path("empty-list");
        assert_eq!(
            list_from_path(&path, false, false).unwrap(),
            "No sessions.\n"
        );
    }

    #[test]
    fn list_filters_pending_sessions_in_text_output() {
        let path = temp_sessions_path("list-text");
        let sessions = vec![
            sample_session("pending123456", "s1", "Pending title", "pending"),
            sample_session("done123456", "s2", "Done title", "done"),
        ];
        save_to_path(&path, &sessions).unwrap();

        let output = list_from_path(&path, false, false).unwrap();

        assert!(output.contains("pending1"));
        assert!(output.contains("claude"));
        assert!(output.contains("Pending title"));
        assert!(output.contains("ago"));
        assert!(!output.contains("Done title"));
    }

    #[test]
    fn list_text_uses_updated_at_when_present() {
        let path = temp_sessions_path("list-updated-time");
        let mut session = sample_session("pending123456", "s1", "Pending title", "pending");
        session.created_at = "2026-05-16T12:00:00Z".to_string();
        session.updated_at = Some(Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string());
        save_to_path(&path, &[session]).unwrap();

        let output = list_from_path(&path, false, false).unwrap();

        assert!(output.contains("< 1h"), "{output}");
        assert!(!output.contains("2d ago"), "{output}");
    }

    #[test]
    fn list_all_json_includes_pending_and_done_sessions() {
        let path = temp_sessions_path("list-json");
        let sessions = vec![
            sample_session("pending", "s1", "Pending", "pending"),
            sample_session("done", "s2", "Done", "done"),
        ];
        save_to_path(&path, &sessions).unwrap();

        let output = list_from_path(&path, true, true).unwrap();
        let parsed: Vec<Session> = serde_json::from_str(&output).unwrap();

        assert_eq!(parsed, sessions);
    }

    #[test]
    fn done_by_id_or_prefix_updates_one_matching_session() {
        let path = temp_sessions_path("done-id-or-prefix");
        let sessions = vec![
            sample_session("abc123", "s1", "First", "pending"),
            sample_session("def456", "s2", "Second", "pending"),
        ];
        save_to_path(&path, &sessions).unwrap();

        let output =
            set_status_at_path(&path, Some("abc".to_string()), None, "done", "Done").unwrap();

        assert_eq!(output, "Done: First");
        let saved = read_sessions(&path);
        assert_eq!(saved[0].status, "done");
        assert_eq!(saved[1].status, "pending");
    }

    #[test]
    fn reopen_by_session_id_updates_all_matching_sessions() {
        let path = temp_sessions_path("reopen-session-id");
        let sessions = vec![
            sample_session("abc123", "shared", "First", "done"),
            sample_session("def456", "shared", "Second", "done"),
        ];
        save_to_path(&path, &sessions).unwrap();

        let output = set_status_at_path(
            &path,
            None,
            Some("shared".to_string()),
            "pending",
            "Reopened",
        )
        .unwrap();

        assert_eq!(output, "Reopened: 2 sessions");
        let saved = read_sessions(&path);
        assert!(saved.iter().all(|s| s.status == "pending"));
    }

    #[test]
    fn status_changes_require_a_selector_and_an_existing_match() {
        let path = temp_sessions_path("status-errors");
        save_to_path(&path, &[sample_session("abc123", "s1", "Only", "pending")]).unwrap();

        let missing_selector = set_status_at_path(&path, None, None, "done", "Done")
            .unwrap_err()
            .to_string();
        assert_eq!(missing_selector, "Provide a session ID or --session-id");

        let no_match = set_status_at_path(&path, Some("zzz".to_string()), None, "done", "Done")
            .unwrap_err()
            .to_string();
        assert_eq!(no_match, "No session found");
    }

    #[test]
    fn time_ago_handles_invalid_recent_hour_day_and_future_inputs() {
        let now = "2026-05-18T12:00:00Z".parse::<DateTime<Utc>>().unwrap();

        assert_eq!(time_ago_at("not a date", now), "");
        assert_eq!(time_ago_at("2026-05-18T11:30:00Z", now), "< 1h");
        assert_eq!(time_ago_at("2026-05-18T07:00:00Z", now), "5h ago");
        assert_eq!(time_ago_at("2026-05-16T12:00:00Z", now), "2d ago");
        assert_eq!(time_ago_at("2026-05-18T13:00:00Z", now), "< 1h");
    }
}

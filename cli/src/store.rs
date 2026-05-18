use anyhow::{bail, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Serialize, Deserialize, Clone)]
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
    pub resume_cmd: String,
}

fn sessions_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config/perch/sessions.json")
}

fn load() -> Result<Vec<Session>> {
    let path = sessions_path();
    if !path.exists() {
        return Ok(vec![]);
    }
    let text = std::fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

fn save(sessions: &[Session]) -> Result<()> {
    let path = sessions_path();
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
    let working_dir = working_dir.unwrap_or_else(|| {
        std::env::current_dir()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    });

    let resume_cmd = match agent.as_str() {
        "codex"    => format!("codex resume {session_id}"),
        "pi"       => format!("pi --session {session_id}"),
        "windsurf" => format!("windsurf {}", working_dir),
        "cursor"   => format!("cursor {}", working_dir),
        "trae"     => format!("trae {}", working_dir),
        "droid"    => format!("droid --resume {session_id}"),
        "goose"    => format!("goose session -r --name {session_id}"),
        "opencode" => format!("opencode session resume {session_id}"),
        "kiro"     => format!("kiro-cli chat --resume-id {session_id}"),
        "amp"      => format!("amp threads continue {session_id}"),
        _          => format!("claude --resume {session_id}"),
    };

    let entry = Session {
        id: Uuid::new_v4().to_string(),
        agent,
        session_id,
        working_dir,
        title: title.clone(),
        note,
        priority: "medium".to_string(),
        status: "pending".to_string(),
        created_at: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        resume_cmd,
    };

    let mut sessions = load()?;
    sessions.push(entry);
    save(&sessions)?;
    println!("{title}");
    Ok(())
}

pub fn list(all: bool, json: bool) -> Result<()> {
    let sessions = load()?;
    let filtered: Vec<&Session> = sessions
        .iter()
        .filter(|s| all || s.status == "pending")
        .collect();

    if json {
        println!("{}", serde_json::to_string_pretty(&filtered)?);
        return Ok(());
    }

    if filtered.is_empty() {
        println!("No sessions.");
        return Ok(());
    }

    for s in &filtered {
        let age = time_ago(&s.created_at);
        println!("{:.8}  {:<6}  {}  {}", s.id, s.agent, s.title, age);
    }
    Ok(())
}

pub fn done(id_prefix: String) -> Result<()> {
    let mut sessions = load()?;
    let matches: Vec<usize> = sessions
        .iter()
        .enumerate()
        .filter(|(_, s)| s.id.starts_with(&id_prefix))
        .map(|(i, _)| i)
        .collect();

    match matches.len() {
        0 => bail!("No session found matching '{id_prefix}'"),
        1 => {
            let title = sessions[matches[0]].title.clone();
            sessions[matches[0]].status = "done".to_string();
            save(&sessions)?;
            println!("Done: {title}");
        }
        _ => bail!("Multiple sessions match '{id_prefix}', be more specific"),
    }
    Ok(())
}

pub fn reopen(id_prefix: String) -> Result<()> {
    let mut sessions = load()?;
    let matches: Vec<usize> = sessions
        .iter()
        .enumerate()
        .filter(|(_, s)| s.id.starts_with(&id_prefix))
        .map(|(i, _)| i)
        .collect();

    match matches.len() {
        0 => bail!("No session found matching '{id_prefix}'"),
        1 => {
            let title = sessions[matches[0]].title.clone();
            sessions[matches[0]].status = "pending".to_string();
            save(&sessions)?;
            println!("Reopened: {title}");
        }
        _ => bail!("Multiple sessions match '{id_prefix}', be more specific"),
    }
    Ok(())
}

fn time_ago(iso: &str) -> String {
    let Ok(dt) = iso.parse::<DateTime<Utc>>() else {
        return String::new();
    };
    let secs = (Utc::now() - dt).num_seconds().max(0) as u64;
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

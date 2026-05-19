use anyhow::Result;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Serialize)]
struct DoctorReport {
    ok: bool,
    checks: Vec<DoctorCheck>,
}

#[derive(Serialize)]
struct DoctorCheck {
    name: String,
    status: CheckStatus,
    message: String,
    path: Option<String>,
    fix: Option<String>,
}

#[derive(Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum CheckStatus {
    Ok,
    Warning,
    Error,
}

struct AgentSpec {
    name: &'static str,
    binary: &'static str,
    command_path: &'static str,
}

const AGENTS: &[AgentSpec] = &[
    AgentSpec {
        name: "Claude Code",
        binary: "claude",
        command_path: ".claude/commands/perch.md",
    },
    AgentSpec {
        name: "Codex",
        binary: "codex",
        command_path: ".codex/skills/perch/SKILL.md",
    },
    AgentSpec {
        name: "Pi",
        binary: "pi",
        command_path: ".pi/agent/skills/perch/SKILL.md",
    },
    AgentSpec {
        name: "Droid",
        binary: "droid",
        command_path: ".factory/skills/perch/SKILL.md",
    },
    AgentSpec {
        name: "OpenCode",
        binary: "opencode",
        command_path: ".config/opencode/commands/perch.md",
    },
];

pub fn run(json: bool) -> Result<()> {
    let report = build_report();
    if json {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        print_report(&report);
    }

    if report.ok {
        Ok(())
    } else {
        std::process::exit(1);
    }
}

fn build_report() -> DoctorReport {
    let mut checks = Vec::new();
    checks.push(check_cli_location());
    checks.push(check_file(
        "sessions file",
        sessions_path(),
        "Run install.sh or save a session with /perch.",
    ));
    checks.push(check_file(
        "config file",
        config_path(),
        "Run install.sh to create the default Perch config.",
    ));

    for agent in AGENTS {
        checks.extend(check_agent(agent));
    }

    let ok = !checks
        .iter()
        .any(|check| check.status == CheckStatus::Error);
    DoctorReport { ok, checks }
}

fn check_cli_location() -> DoctorCheck {
    let current = std::env::current_exe().ok();
    let expected = home_path(".local/bin/perch");
    match current {
        Some(path) if path == expected => DoctorCheck::ok(
            "cli location",
            format!("perch CLI is installed at {}", path.display()),
            Some(path),
        ),
        Some(path) => DoctorCheck::warning(
            "cli location",
            format!(
                "running perch from {}; recommended install path is {}",
                path.display(),
                expected.display()
            ),
            Some(path),
            "Run install.sh or set your Raycast Perch CLI Path to this binary.",
        ),
        None => DoctorCheck::error(
            "cli location",
            "could not determine current perch executable",
            None,
            "Run install.sh again.",
        ),
    }
}

fn check_file(name: &str, path: PathBuf, fix: &str) -> DoctorCheck {
    if path.is_file() {
        DoctorCheck::ok(name, format!("found {}", path.display()), Some(path))
    } else {
        DoctorCheck::error(name, format!("missing {}", path.display()), Some(path), fix)
    }
}

fn check_agent(agent: &AgentSpec) -> Vec<DoctorCheck> {
    let mut checks = Vec::new();
    let binary = find_on_path(agent.binary);
    let command_path = home_path(agent.command_path);

    if let Some(path) = binary {
        checks.push(DoctorCheck::ok(
            format!("{} binary", agent.name),
            format!("found {} at {}", agent.binary, path.display()),
            Some(path),
        ));
        if command_path.is_file() {
            checks.push(DoctorCheck::ok(
                format!("{} /perch command", agent.name),
                format!("found {}", command_path.display()),
                Some(command_path),
            ));
        } else {
            checks.push(DoctorCheck::error(
                format!("{} /perch command", agent.name),
                format!(
                    "{} is installed but /perch command is missing",
                    agent.binary
                ),
                Some(command_path),
                "Run install.sh again, then restart the agent.",
            ));
        }
    } else {
        checks.push(DoctorCheck::warning(
            format!("{} binary", agent.name),
            format!("{} not found in PATH", agent.binary),
            None,
            "Install this agent if you want Perch slash-command support for it.",
        ));
    }

    checks
}

fn print_report(report: &DoctorReport) {
    println!("Perch doctor\n");
    for check in &report.checks {
        let marker = match check.status {
            CheckStatus::Ok => "✓",
            CheckStatus::Warning => "-",
            CheckStatus::Error => "✗",
        };
        println!("{marker} {}: {}", check.name, check.message);
        if let Some(fix) = &check.fix {
            println!("  fix: {fix}");
        }
    }
    println!();
    if report.ok {
        println!("Perch setup looks usable.");
    } else {
        println!("Perch setup has errors. Apply the suggested fixes and rerun `perch doctor`.");
    }
}

fn find_on_path(binary: &str) -> Option<PathBuf> {
    let paths = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&paths) {
        let candidate = directory.join(binary);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn sessions_path() -> PathBuf {
    home_path(".config/perch/sessions.json")
}

fn config_path() -> PathBuf {
    home_path(".config/perch/config")
}

fn home_path(relative: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(relative)
}

impl DoctorCheck {
    fn ok(name: impl Into<String>, message: impl Into<String>, path: Option<PathBuf>) -> Self {
        Self {
            name: name.into(),
            status: CheckStatus::Ok,
            message: message.into(),
            path: path.map(|path| path.display().to_string()),
            fix: None,
        }
    }

    fn warning(
        name: impl Into<String>,
        message: impl Into<String>,
        path: Option<PathBuf>,
        fix: impl Into<String>,
    ) -> Self {
        Self {
            name: name.into(),
            status: CheckStatus::Warning,
            message: message.into(),
            path: path.map(|path| path.display().to_string()),
            fix: Some(fix.into()),
        }
    }

    fn error(
        name: impl Into<String>,
        message: impl Into<String>,
        path: Option<PathBuf>,
        fix: impl Into<String>,
    ) -> Self {
        Self {
            name: name.into(),
            status: CheckStatus::Error,
            message: message.into(),
            path: path.map(|path| path.display().to_string()),
            fix: Some(fix.into()),
        }
    }
}

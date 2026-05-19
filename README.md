# Perch

Perch helps developers park AI coding sessions and resume them later from the CLI, menu bar, or Raycast. Run `/perch` inside a supported coding agent, and Perch saves the current session into `~/.config/perch/sessions.json`.

## 60-Second Quick Start

Install the Perch CLI and supported agent `/perch` commands:

```sh
curl -fsSL https://raw.githubusercontent.com/ReScienceLab/Perch/main/install.sh | sh
```

Then:

1. Make sure `~/.local/bin` is in your shell `PATH`.
2. Restart your coding agent.
3. Type `/perch My task title` inside Claude Code, Codex, Pi, Droid, or OpenCode to save the current session.
4. Resume from Raycast with **Search Sessions**, from the menu bar, or by running `perch list` and copying the resume command.
5. Verify setup any time with:

```sh
perch doctor
```

Perch stores sessions locally only; no service or account is required.

## Highlights

- One `/perch` command shared across agents — no per-agent prompt drift.
- Fast session detection where the agent exposes a session ID (for example `CLAUDE_CODE_SESSION_ID` in Claude Code), with safe fallbacks when needed.
- Simple local JSON storage; no service or account required.
- Menu bar UI for viewing pending/completed sessions.
- CLI for scripting, listing, marking done, and reopening sessions.

## Supported Agents

| Agent       | `/perch` install | Resume command                   |
| ----------- | ---------------- | -------------------------------- |
| Claude Code | Automatic        | `claude --resume <id>`           |
| Codex       | Automatic        | `codex resume <id>`              |
| Pi          | Automatic        | `pi --session <id>`              |
| Droid       | Automatic        | `droid --resume <id>`            |
| OpenCode    | Automatic        | `opencode session resume <id>`   |
| Goose       | Manual CLI add   | `goose session -r --name <id>`   |
| Kiro        | Manual CLI add   | `kiro-cli chat --resume-id <id>` |
| Windsurf    | Manual CLI add   | `windsurf <working-dir>`         |
| Cursor      | Manual CLI add   | `cursor <working-dir>`           |
| Trae        | Manual CLI add   | `trae <working-dir>`             |
| Amp         | Manual CLI add   | `amp threads continue <id>`      |

> **Automatic** means `install.sh` detects the agent binary and installs `/perch` into that agent's command/skill directory. **Manual CLI add** means Perch supports the resume command, but there is no installed slash-command path yet.

## Install

Recommended remote install:

```sh
curl -fsSL https://raw.githubusercontent.com/ReScienceLab/Perch/main/install.sh | sh
```

Local repo install for contributors:

```sh
git clone https://github.com/ReScienceLab/Perch.git
cd Perch
./install.sh
```

The installer is idempotent. It:

- Installs the `perch` CLI to `~/.local/bin/perch`, using the latest GitHub Release prebuilt binary by default.
- Falls back to a local Cargo build only when running from a cloned repo and release download is unavailable.
- Installs the native macOS `PerchApp` menu bar app to `~/.local/share/perch/PerchApp` by default on macOS.
- Installs the same agent-agnostic command from `Commands/perch.md` for every detected agent.
- Creates `~/.config/perch/sessions.json` if missing.
- Creates `~/.config/perch/config` if missing.

Installer environment flags:

```sh
PERCH_INSTALL_APP=0          # skip native menu bar app installation
PERCH_INSTALL_APP=1          # force native menu bar app installation on macOS
PERCH_APP_INSTALL_DIR=...    # override app install directory; default ~/.local/share/perch
PERCH_OPEN_APP=0             # install but do not open PerchApp after install
```

Make sure `~/.local/bin` is in your shell `PATH` and is also visible inside your coding agents. Run `perch doctor` after installation for actionable diagnostics.

### Installed command locations

| Agent       | Installed file                         |
| ----------- | -------------------------------------- |
| Claude Code | `~/.claude/commands/perch.md`          |
| Codex       | `~/.codex/skills/perch/SKILL.md`       |
| Pi          | `~/.pi/agent/skills/perch/SKILL.md`    |
| Droid       | `~/.factory/skills/perch/SKILL.md`     |
| OpenCode    | `~/.config/opencode/commands/perch.md` |

## Menu Bar App

On macOS, the one-line installer installs and opens the native menu bar app by default:

```sh
curl -fsSL https://raw.githubusercontent.com/ReScienceLab/Perch/main/install.sh | sh
```

The app is installed to `~/.local/share/perch/PerchApp` unless `PERCH_APP_INSTALL_DIR` is set. The Perch icon appears in the menu bar. Open it to view active and completed sessions.

Control the app from the CLI:

```sh
perch menubar start [--app-path <path>]
perch menubar stop
perch menubar status
perch menubar login enable [--app-path <path>]
perch menubar login disable
perch menubar login status
```

`perch menubar login enable` writes `~/Library/LaunchAgents/com.resciencelab.perch.plist` and uses `launchctl bootstrap/enable` for the current GUI user. The LaunchAgent runs with your user privileges and only launches the configured PerchApp binary. The installer opens the app after install but does not enable launch-at-login automatically.

If launch-at-login fails with permission errors, check that your terminal has the required macOS privacy permissions for writing `~/Library/LaunchAgents` and running `launchctl` in your GUI session.

Local development still requires macOS 13+ and a Swift toolchain:

```sh
cd App
swift build
.build/debug/PerchApp
```

## Raycast Extension

Perch also includes a Raycast extension for searching, resuming, and managing parked sessions from Raycast.

```sh
cd raycast-extension
npm install
npm run dev
```

Available commands:

- **Search Sessions** — browse `~/.config/perch/sessions.json`, copy/paste project-aware resume commands, open working directories, mark sessions done, and reopen sessions.
- **Add Session** — manually add sessions for agents that do not yet have an installed `/perch` command.

Run `npm run lint` and `npm run build` in `raycast-extension/` before publishing or submitting changes.

## Usage

### Save the current session

Inside a supported agent:

```text
/perch [optional title]
```

Examples:

```text
/perch
/perch Backend: add auth endpoint
```

If you omit the title, the agent generates a short `Project: action` title.

### Mark the current session done

Inside a supported agent:

```text
/perch done
```

Or from a terminal:

```sh
perch done <perch-id-or-prefix>
perch done --session-id <agent-session-id>
```

### Delete a saved session

Open the Perch menu bar item, open a session's submenu, and choose **Delete Session**. This removes the saved Perch entry only; it does not delete the underlying agent history from Claude/Codex/Pi/etc.

### Resume a session

Open the Perch menu bar item and click a session. Perch copies a project-aware shell command to your clipboard:

```sh
cd '/absolute/path/to/project' && claude --resume <id>
cd '/absolute/path/to/project' && pi --session <id>
cd '/absolute/path/to/project' && opencode session resume <id>
```

Paste it into any terminal to resume from the correct working directory.

### Add a session manually

Use this for agents that do not yet have an installed `/perch` command:

```sh
perch add \
  --title "MyApp: fix login" \
  --agent claude \
  --session-id <id> \
  --working-dir "$PWD"
```

For workspace-based agents such as Cursor/Windsurf/Trae, Perch stores the working directory and creates the appropriate resume command:

```sh
perch add --title "Site: continue CSS" --agent cursor --session-id unused --working-dir "$PWD"
```

## CLI Reference

```sh
perch add --title "..." --agent <agent> --session-id <id> [--working-dir <dir>] [--note "..."]  # create or update
perch list
perch list --all
perch list --all --json
perch done <perch-id-or-prefix>
perch done --session-id <agent-session-id>
perch reopen <perch-id-or-prefix>
perch reopen --session-id <agent-session-id>
perch menubar start [--app-path <path>]
perch menubar stop
perch menubar status
perch menubar login enable [--app-path <path>]
perch menubar login disable
perch menubar login status
perch doctor
perch doctor --json
```

## Save Semantics

`perch add` is an upsert keyed by `agent + session_id`:

- First save creates a new pending entry.
- Saving the same resumed session again updates the existing entry instead of creating a duplicate.
- Updates refresh `title`, `working_dir`, `note`, `resume_cmd`, set `status` back to `pending`, and write `updated_at`.
- `created_at` remains the original first-save timestamp.

## How `/perch` Finds the Current Session

Perch uses one shared command file. The agent identifies itself (`claude`, `codex`, `pi`, `droid`, or `opencode`) and runs only its own session detector.

Current fast paths and fallbacks:

- **Claude Code**: prefers `CLAUDE_CODE_SESSION_ID`, then older env vars, then the current project's `~/.claude/projects/.../sessions-index.json`.
- **Pi**: prefers `PI_SESSION_ID`, then the current project's `~/.pi/agent/sessions/.../*.jsonl`.
- **Codex**: prefers `CODEX_SESSION_ID`, then the latest file in `~/.codex/sessions`.
- **Droid**: prefers `DROID_SESSION_ID`, then `droid session list --json`.
- **OpenCode**: prefers `OPENCODE_SESSION_ID`, then `opencode session list`.

The command is intentionally strict: it should not try another agent's detector just because that binary exists on your machine.

## Data Storage

Sessions are stored locally at:

```text
~/.config/perch/sessions.json
```

Each entry looks like:

```json
{
  "id": "perch-entry-uuid",
  "agent": "claude",
  "session_id": "agent-native-session-id",
  "working_dir": "/path/to/project",
  "title": "Project: action",
  "note": "",
  "priority": "medium",
  "status": "pending",
  "created_at": "2026-05-18T10:00:00Z",
  "updated_at": "2026-05-18T10:30:00Z",
  "resume_cmd": "claude --resume agent-native-session-id"
}
```

The schema is documented in [`schema/session.json`](schema/session.json).

## Configuration

Open config from the menu bar (**Open Config**) or edit:

```text
~/.config/perch/config
```

Default file:

```toml
# Perch configuration
terminal = ghostty
sort-by = date
max-sessions = 20
auto-start = true
show-badge = true
```

`show-badge` controls whether the menu bar icon shows the pending session count. Other keys are kept for app behavior and future UI options.

## Development

Run the full test suite:

```sh
./scripts/test.sh
```

Run individual suites:

```sh
cargo test --manifest-path cli/Cargo.toml
cd App && swift test
./tests/install.sh
python3 tests/schema.py
```

Build release artifacts locally:

```sh
cargo build --release --manifest-path cli/Cargo.toml
cd App && swift build -c release
```

## Troubleshooting

### `/perch` says `perch: command not found`

Add `~/.local/bin` to your `PATH`, then restart the agent so it inherits the updated environment.

### `/perch` cannot determine the session ID

Update the relevant agent and reinstall Perch:

```sh
./install.sh
```

For Claude Code, newer versions expose `CLAUDE_CODE_SESSION_ID` to Bash tools, which is the fastest path.

### The menu bar app shows no sessions

Check what the CLI sees:

```sh
perch list --all
```

Also verify that `~/.config/perch/sessions.json` exists and contains valid JSON.

### The menu bar app did not install or start

Check app status:

```sh
perch menubar status
```

Re-run the installer with app installation enabled:

```sh
PERCH_INSTALL_APP=1 ./install.sh
```

If a checksum mismatch is reported, the artifact was not installed. Retry later or install from a known-good release asset.

### Launch at login is not working

Inspect and reset the LaunchAgent:

```sh
perch menubar login status
perch menubar login disable
perch menubar login enable
```

## Links

- **GitHub**: https://github.com/ReScienceLab/Perch
- **Issues**: https://github.com/ReScienceLab/Perch/issues

# Perch

A macOS menu bar app that lets you park AI coding sessions and resume them instantly. Run `/perch` in any supported agent to save the current session — Perch shows it in the menu bar. Click a session to copy its resume command to the clipboard, then paste it in any terminal.

## Supported Agents

| Agent | `/perch` command | Resume |
|---|---|---|
| **Claude Code** | `/perch` | `claude --resume <id>` |
| **Codex** | `/perch` | `codex resume <id>` |
| **Pi** | `/perch` | `pi --session <id>` |
| **Droid** | `/perch` | `droid --resume <id>` |
| **OpenCode** | `/perch` | `opencode session resume <id>` |
| **Goose** | `/perch` (manual) | `goose session -r --name <id>` |
| **Kiro** | `/perch` (manual) | `kiro-cli chat --resume-id <uuid>` |
| **Windsurf** | `/perch` (manual) | `windsurf <dir>` |
| **Cursor** | `/perch` (manual) | `cursor <dir>` |
| **Trae** | `/perch` (manual) | `trae <dir>` |

> **Manual** = no global command install path; add the session via `perch add` directly.

## Install

```sh
git clone https://github.com/ReScienceLab/Perch.git
cd Perch
./install.sh
```

The installer:
- Builds and installs the `perch` CLI to `~/.local/bin/`
- Installs `/perch` commands for every detected agent (claude, codex, pi, droid, opencode)
- Creates `~/.config/perch/` with a default `config` and empty `sessions.json`

Make sure `~/.local/bin` is in your `PATH`.

## Build the Menu Bar App

Requires macOS 13+ and Swift toolchain:

```sh
cd App
swift build
.build/debug/PerchApp
```

The Perch logo appears in the menu bar. Click it to see pending sessions.

## Usage

### Saving a session

Inside a supported agent, run:

```
/perch [optional title]
```

The agent auto-generates a title in `Project: action` format (≤30 chars) if none is provided.

You can also save manually from the terminal:

```sh
perch add --title "MyApp: fix login" --agent claude --session-id <id>
```

### Resuming a session

Click any session in the menu bar — the resume command is copied to your clipboard. Paste it in any terminal to resume.

### CLI commands

```sh
perch add --title "..." --agent <agent> --session-id <id>   # save a session
perch list                                                   # list pending sessions
perch list --all --json                                      # all sessions as JSON
perch done <id-prefix>                                       # mark a session done
```

### Marking sessions done

Right-click (or hover) any session in the menu and choose **Mark as Done**.

## Configure

Open via the menu bar → **Open Config** (⌘,), or edit directly:

```
~/.config/perch/config
```

```
# Show pending session count badge on the menu bar icon
show-badge = true

# Maximum sessions to show
max-sessions = 20
```

## Links

- **GitHub**: https://github.com/ReScienceLab/Perch
- **Issues**: https://github.com/ReScienceLab/Perch/issues

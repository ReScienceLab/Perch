# Perch

Perch is a macOS menu bar app that lets you resume AI coding sessions (Claude, Codex, Pi) directly from your menu bar. Sessions are saved to `~/.config/perch/sessions.json` by agent-specific slash commands, and Perch displays them with a single click to reopen in your preferred terminal.

## Install

Run the installer from the project root:

```sh
./install.sh
```

This installs the `/todo` command for Claude Code (and `/todo` skills for Codex and Pi if they are installed), and initialises `~/.config/perch/` with a default `config` file and an empty `sessions.json`.

## Build and Run

```sh
cd App
swift build
.build/debug/PerchApp
```

The app appears as a bird icon (🐦) in the menu bar. Click it to see your pending sessions.

## Configure

Edit `~/.config/perch/config` to customise behaviour:

```
# Terminal to use when opening sessions
terminal = ghostty   # ghostty | warp | iterm2 | terminal

# Session sort order
sort-by = date

# Maximum sessions to show
max-sessions = 20

# Show pending session count badge on menu bar icon
show-badge = true
```

## Saving Sessions with /todo

Inside a Claude Code session, run:

```
/todo [optional note]
```

This saves the current session to `~/.config/perch/sessions.json` so it appears in the Perch menu. The session entry includes the working directory, a resume command, and your optional note.

For Codex and Pi, the equivalent `/todo` skill works the same way once installed via `./install.sh`.

## Marking Sessions Done

Right-click (or hover) any session in the Perch menu and choose **Mark as Done** to remove it from the list.

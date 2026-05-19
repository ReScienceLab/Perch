# Perch Raycast Extension

Search, resume, and manage Perch AI coding sessions from Raycast.

## Requirements

- macOS with Raycast installed
- Perch CLI installed with `./install.sh`
- Sessions stored at `~/.config/perch/sessions.json` (default)

## Commands

### Search Sessions

Lists parked sessions from Perch. Press Enter to copy (or paste, depending on preferences) a project-aware resume command:

```sh
cd '/path/to/project' && claude --resume <session-id>
```

Actions include copy resume command, paste resume command, open working directory, mark done, reopen, and copy IDs.

### Add Session

Manually add a session for agents that do not yet have a `/perch` command installed.

## Preferences

- **Sessions File**: Override the path to `sessions.json`.
- **Perch CLI Path**: Override the path to the `perch` binary for add/done/reopen actions.
- **Default Status Filter**: Choose Pending, Done, or All as the default list filter.
- **Default Resume Action**: Choose whether Enter copies or pastes the resume command.

## Troubleshooting

If mutation actions fail, ensure `perch` is installed and available in your shell PATH or set **Perch CLI Path** to `~/.local/bin/perch`.

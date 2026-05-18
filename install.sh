#!/bin/sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$HOME/.config/perch"

if [ ! -f "$HOME/.config/perch/sessions.json" ]; then
    printf '[]' > "$HOME/.config/perch/sessions.json"
fi

if [ ! -f "$HOME/.config/perch/config" ]; then
    cat > "$HOME/.config/perch/config" <<'EOF'
# Perch configuration
terminal = ghostty
sort-by = date
max-sessions = 20
auto-start = true
show-badge = true
EOF
fi

if command -v claude >/dev/null 2>&1; then
    mkdir -p "$HOME/.claude/commands"
    cp "$SCRIPT_DIR/Commands/claude-todo.md" "$HOME/.claude/commands/todo.md"
    printf '[✓] claude → %s\n' "$HOME/.claude/commands/todo.md"
else
    printf '[✗] claude (not found in PATH)\n'
fi

if command -v codex >/dev/null 2>&1; then
    mkdir -p "$HOME/.codex/skills/todo"
    cp "$SCRIPT_DIR/Commands/codex-todo/SKILL.md" "$HOME/.codex/skills/todo/SKILL.md"
    printf '[✓] codex → %s\n' "$HOME/.codex/skills/todo/SKILL.md"
else
    printf '[✗] codex (not found in PATH)\n'
fi

if command -v pi >/dev/null 2>&1; then
    mkdir -p "$HOME/.pi/agent/skills/todo"
    cp "$SCRIPT_DIR/Commands/pi-todo/SKILL.md" "$HOME/.pi/agent/skills/todo/SKILL.md"
    printf '[✓] pi → %s\n' "$HOME/.pi/agent/skills/todo/SKILL.md"
else
    printf '[✗] pi (not found in PATH)\n'
fi

printf 'Done. Type /todo in any session to save it to Perch.\n'

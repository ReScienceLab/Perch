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

# Build and install the perch CLI
if command -v cargo >/dev/null 2>&1; then
    printf 'Building perch CLI...\n'
    cargo build --release --manifest-path "$SCRIPT_DIR/cli/Cargo.toml" --quiet
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT_DIR/cli/target/release/perch" "$HOME/.local/bin/perch"
    printf '[✓] perch CLI → %s\n' "$HOME/.local/bin/perch"
else
    printf '[✗] cargo not found — skipping CLI build (install Rust from https://rustup.rs)\n'
fi

if command -v claude >/dev/null 2>&1; then
    mkdir -p "$HOME/.claude/commands"
    cp "$SCRIPT_DIR/Commands/claude-perch.md" "$HOME/.claude/commands/perch.md"
    printf '[✓] claude → %s\n' "$HOME/.claude/commands/perch.md"
else
    printf '[✗] claude (not found in PATH)\n'
fi

if command -v codex >/dev/null 2>&1; then
    mkdir -p "$HOME/.codex/skills/perch"
    cp "$SCRIPT_DIR/Commands/codex-perch/SKILL.md" "$HOME/.codex/skills/perch/SKILL.md"
    printf '[✓] codex → %s\n' "$HOME/.codex/skills/perch/SKILL.md"
else
    printf '[✗] codex (not found in PATH)\n'
fi

if command -v pi >/dev/null 2>&1; then
    mkdir -p "$HOME/.pi/agent/skills/perch"
    cp "$SCRIPT_DIR/Commands/pi-perch/SKILL.md" "$HOME/.pi/agent/skills/perch/SKILL.md"
    printf '[✓] pi → %s\n' "$HOME/.pi/agent/skills/perch/SKILL.md"
else
    printf '[✗] pi (not found in PATH)\n'
fi

if command -v droid >/dev/null 2>&1; then
    mkdir -p "$HOME/.factory/skills/perch"
    cp "$SCRIPT_DIR/Commands/droid-perch/SKILL.md" "$HOME/.factory/skills/perch/SKILL.md"
    printf '[✓] droid → %s\n' "$HOME/.factory/skills/perch/SKILL.md"
else
    printf '[✗] droid (not found in PATH)\n'
fi

if command -v opencode >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/opencode/commands"
    cp "$SCRIPT_DIR/Commands/opencode-perch.md" "$HOME/.config/opencode/commands/perch.md"
    printf '[✓] opencode → %s\n' "$HOME/.config/opencode/commands/perch.md"
else
    printf '[✗] opencode (not found in PATH)\n'
fi

printf 'Done. Type /perch in any session to save it to Perch.\n'
printf 'Make sure ~/.local/bin is in your PATH.\n'

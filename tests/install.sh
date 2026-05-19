#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

BIN_DIR="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
TEST_REPO="$TMP_DIR/repo"
mkdir -p "$BIN_DIR" "$HOME_DIR" "$TEST_REPO/cli"
cp "$REPO_ROOT/install.sh" "$TEST_REPO/install.sh"
cp -R "$REPO_ROOT/Commands" "$TEST_REPO/Commands"
cp "$REPO_ROOT/cli/Cargo.toml" "$TEST_REPO/cli/Cargo.toml"
chmod +x "$TEST_REPO/install.sh"

cat >"$BIN_DIR/cargo" <<'EOF'
#!/bin/sh
manifest=""
previous=""
for arg in "$@"; do
    if [ "$previous" = "--manifest-path" ]; then
        manifest=$arg
        break
    fi
    previous=$arg
done
if [ -n "$manifest" ]; then
    cli_dir=$(dirname "$manifest")
    mkdir -p "$cli_dir/target/release"
    cat > "$cli_dir/target/release/perch" <<'PERCH'
#!/bin/sh
printf 'mock perch\n'
PERCH
    chmod +x "$cli_dir/target/release/perch"
fi
EOF
chmod +x "$BIN_DIR/cargo"

for agent in claude codex pi droid opencode; do
	cat >"$BIN_DIR/$agent" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$BIN_DIR/$agent"
done

run_install() {
	HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" PERCH_INSTALL_SOURCE=local "$TEST_REPO/install.sh" >"$TMP_DIR/install.out"
}

assert_file() {
	if [ ! -f "$1" ]; then
		printf 'Expected file to exist: %s\n' "$1" >&2
		exit 1
	fi
}

assert_contains() {
	file=$1
	text=$2
	if ! grep -Fq -- "$text" "$file"; then
		printf 'Expected %s to contain: %s\n' "$file" "$text" >&2
		printf 'Actual contents:\n' >&2
		cat "$file" >&2
		exit 1
	fi
}

run_install

assert_file "$HOME_DIR/.config/perch/sessions.json"
assert_file "$HOME_DIR/.config/perch/config"
assert_file "$HOME_DIR/.local/bin/perch"
assert_file "$HOME_DIR/.claude/commands/perch.md"
assert_file "$HOME_DIR/.codex/skills/perch/SKILL.md"
assert_file "$HOME_DIR/.pi/agent/skills/perch/SKILL.md"
assert_file "$HOME_DIR/.factory/skills/perch/SKILL.md"
assert_file "$HOME_DIR/.config/opencode/commands/perch.md"

cmp "$TEST_REPO/Commands/perch.md" "$HOME_DIR/.claude/commands/perch.md"
cmp "$TEST_REPO/Commands/perch.md" "$HOME_DIR/.config/opencode/commands/perch.md"
for skill_file in \
	"$HOME_DIR/.codex/skills/perch/SKILL.md" \
	"$HOME_DIR/.pi/agent/skills/perch/SKILL.md" \
	"$HOME_DIR/.factory/skills/perch/SKILL.md"; do
	assert_contains "$skill_file" "name: perch"
	assert_contains "$skill_file" "Save the current AI coding agent session to Perch"
	assert_contains "$skill_file" 'If you are Claude Code, `AGENT=claude`'
	assert_contains "$skill_file" 'CLAUDE_CODE_SESSION_ID'
	assert_contains "$skill_file" "[0-9a-f]{8}-[0-9a-f]{4}"
	assert_contains "$skill_file" 'Do not try detectors for other agents.'
	assert_contains "$skill_file" "s#^/##; s#/#-#g"
	assert_contains "$skill_file" 'perch add --title "<TITLE>" --agent "<AGENT>" --session-id "<SESSION_ID>"'
done

if [ "$(cat "$HOME_DIR/.config/perch/sessions.json")" != "[]" ]; then
	printf 'sessions.json should be initialized to []\n' >&2
	exit 1
fi
assert_contains "$HOME_DIR/.config/perch/config" "terminal = ghostty"
assert_contains "$HOME_DIR/.config/perch/config" "show-badge = true"
assert_contains "$TMP_DIR/install.out" "Next steps:"
assert_contains "$TMP_DIR/install.out" "Run perch doctor to verify your setup."

printf '[{"id":"keep"}]' >"$HOME_DIR/.config/perch/sessions.json"
printf 'terminal = terminal\n' >"$HOME_DIR/.config/perch/config"
run_install

if [ "$(cat "$HOME_DIR/.config/perch/sessions.json")" != '[{"id":"keep"}]' ]; then
	printf 'install.sh should not overwrite an existing sessions.json\n' >&2
	exit 1
fi
if [ "$(cat "$HOME_DIR/.config/perch/config")" != 'terminal = terminal' ]; then
	printf 'install.sh should not overwrite an existing config\n' >&2
	exit 1
fi

NO_AGENT_HOME="$TMP_DIR/no-agent-home"
NO_AGENT_BIN="$TMP_DIR/no-agent-bin"
mkdir -p "$NO_AGENT_HOME" "$NO_AGENT_BIN"
cp "$BIN_DIR/cargo" "$NO_AGENT_BIN/cargo"
HOME="$NO_AGENT_HOME" PATH="$NO_AGENT_BIN:/usr/bin:/bin:/usr/sbin:/sbin" PERCH_INSTALL_SOURCE=local "$TEST_REPO/install.sh" >"$TMP_DIR/no-agent-install.out"
assert_file "$NO_AGENT_HOME/.config/perch/sessions.json"
assert_contains "$TMP_DIR/no-agent-install.out" "- claude not found"
assert_contains "$TMP_DIR/no-agent-install.out" "- codex not found"
assert_contains "$TMP_DIR/no-agent-install.out" "- pi not found"

printf 'install.sh tests passed\n'

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

case "$(uname -s):$(uname -m)" in
Darwin:arm64)
	RELEASE_ARTIFACT=perch-aarch64-apple-darwin
	APP_ARTIFACT=PerchApp-aarch64-apple-darwin.zip
	;;
Darwin:x86_64)
	RELEASE_ARTIFACT=perch-x86_64-apple-darwin
	APP_ARTIFACT=PerchApp-x86_64-apple-darwin.zip
	;;
*)
	RELEASE_ARTIFACT=
	APP_ARTIFACT=
	;;
esac

if [ -n "$RELEASE_ARTIFACT" ]; then
	REMOTE_HOME="$TMP_DIR/remote-home"
	REMOTE_BIN="$TMP_DIR/remote-bin"
	REMOTE_RELEASE="$TMP_DIR/remote-release"
	mkdir -p "$REMOTE_HOME" "$REMOTE_BIN" "$REMOTE_RELEASE"
	cat >"$REMOTE_RELEASE/$RELEASE_ARTIFACT" <<'EOF'
#!/bin/sh
case "$1" in
	--help)
		printf 'mock release perch help\n'
		exit 0
		;;
	--version)
		printf 'perch 0.1.0\n'
		exit 0
		;;
esac
printf 'mock release perch\n'
EOF
	chmod +x "$REMOTE_RELEASE/$RELEASE_ARTIFACT"
	shasum -a 256 "$REMOTE_RELEASE/$RELEASE_ARTIFACT" >"$REMOTE_RELEASE/$RELEASE_ARTIFACT.sha256"

	APP_BUILD_DIR="$TMP_DIR/app-build"
	mkdir -p "$APP_BUILD_DIR/Perch.app/Contents/MacOS"
	python3 - "$APP_BUILD_DIR/Perch.app/Contents/MacOS/PerchApp" <<'PY'
import sys
with open(sys.argv[1], "wb") as app:
    app.write(bytes.fromhex("cffaedfe"))
    app.write(b"mock Mach-O PerchApp\n")
PY
	chmod +x "$APP_BUILD_DIR/Perch.app/Contents/MacOS/PerchApp"
	python3 - "$REMOTE_RELEASE/$APP_ARTIFACT" "$APP_BUILD_DIR/Perch.app/Contents/MacOS/PerchApp" <<'PY'
import sys
import zipfile
zip_path, app_path = sys.argv[1], sys.argv[2]
info = zipfile.ZipInfo("Perch.app/Contents/MacOS/PerchApp")
info.external_attr = 0o755 << 16
with open(app_path, "rb") as source, zipfile.ZipFile(zip_path, "w") as archive:
    archive.writestr(info, source.read())
PY
	shasum -a 256 "$REMOTE_RELEASE/$APP_ARTIFACT" >"$REMOTE_RELEASE/$APP_ARTIFACT.sha256"
	cat >"$REMOTE_BIN/curl" <<EOF
#!/bin/sh
url= dest=
while [ \$# -gt 0 ]; do
	case "\$1" in
		-o) shift; dest=\$1 ;;
		http*) url=\$1 ;;
	esac
	shift
 done
case "\$url" in
	*"$APP_ARTIFACT.sha256") cp "$REMOTE_RELEASE/$APP_ARTIFACT.sha256" "\$dest" ;;
	*"$APP_ARTIFACT") cp "$REMOTE_RELEASE/$APP_ARTIFACT" "\$dest" ;;
	*.sha256) cp "$REMOTE_RELEASE/$RELEASE_ARTIFACT.sha256" "\$dest" ;;
	*) cp "$REMOTE_RELEASE/$RELEASE_ARTIFACT" "\$dest" ;;
esac
EOF
	chmod +x "$REMOTE_BIN/curl"
	cat >"$REMOTE_BIN/otool" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$REMOTE_BIN/otool"
	cat >"$REMOTE_BIN/lipo" <<EOF
#!/bin/sh
printf '%s\n' "$(uname -m)"
EOF
	chmod +x "$REMOTE_BIN/lipo"
	HOME="$REMOTE_HOME" PATH="$REMOTE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" "$TEST_REPO/install.sh" >"$TMP_DIR/remote-install.out"
	assert_file "$REMOTE_HOME/.local/bin/perch"
	assert_file "$REMOTE_HOME/.local/share/perch/PerchApp"
	assert_contains "$TMP_DIR/remote-install.out" "Verified SHA-256 checksum"
	assert_contains "$TMP_DIR/remote-install.out" "Verified Perch CLI identity"
	assert_contains "$TMP_DIR/remote-install.out" "Installed PerchApp to $REMOTE_HOME/.local/share/perch/PerchApp"
	assert_contains "$TMP_DIR/remote-install.out" "  ✓ Opened $REMOTE_HOME/.local/share/perch/PerchApp"

	SKIP_APP_HOME="$TMP_DIR/skip-app-home"
	mkdir -p "$SKIP_APP_HOME"
	HOME="$SKIP_APP_HOME" PATH="$REMOTE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" PERCH_INSTALL_APP=0 "$TEST_REPO/install.sh" >"$TMP_DIR/skip-app-install.out"
	assert_file "$SKIP_APP_HOME/.local/bin/perch"
	if [ -e "$SKIP_APP_HOME/.local/share/perch/PerchApp" ]; then
		printf 'PERCH_INSTALL_APP=0 should skip app installation\n' >&2
		exit 1
	fi
	assert_contains "$TMP_DIR/skip-app-install.out" "PerchApp install skipped"
fi

printf 'install.sh tests passed\n'

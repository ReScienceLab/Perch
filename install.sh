#!/bin/sh
set -eu

REPO="ReScienceLab/Perch"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
RELEASE_BASE="https://github.com/$REPO/releases"
INSTALL_DIR="${PERCH_INSTALL_DIR:-$HOME/.local/bin}"
CLI_DEST="$INSTALL_DIR/perch"
CONFIG_DIR="$HOME/.config/perch"
SESSIONS_FILE="$CONFIG_DIR/sessions.json"
CONFIG_FILE="$CONFIG_DIR/config"
SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || pwd)
LOCAL_COMMAND_SOURCE="$SCRIPT_DIR/Commands/perch.md"
LOCAL_CARGO_MANIFEST="$SCRIPT_DIR/cli/Cargo.toml"
LOCAL_MODE=0

if [ -f "$LOCAL_COMMAND_SOURCE" ] || [ -f "$LOCAL_CARGO_MANIFEST" ]; then
	LOCAL_MODE=1
fi

if [ "${PERCH_INSTALL_SOURCE:-}" = "local" ]; then
	LOCAL_MODE=1
fi

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

platform_artifact() {
	os=$(uname -s 2>/dev/null || printf unknown)
	arch=$(uname -m 2>/dev/null || printf unknown)
	case "$os:$arch" in
		Darwin:arm64) printf 'perch-aarch64-apple-darwin' ;;
		Darwin:x86_64) printf 'perch-x86_64-apple-darwin' ;;
		*)
			warn "Perch prebuilt binaries are currently available for macOS only. Detected: $os $arch"
			return 1
			;;
	esac
}

download() {
	url=$1
	dest=$2
	if have curl; then
		curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$dest"
	elif have wget; then
		wget -q "$url" -O "$dest"
	else
		warn "curl or wget is required to download Perch release artifacts."
		return 1
	fi
}

release_url() {
	artifact=$1
	if [ -n "${PERCH_VERSION:-}" ]; then
		printf '%s/download/%s/%s' "$RELEASE_BASE" "$PERCH_VERSION" "$artifact"
	else
		printf '%s/latest/download/%s' "$RELEASE_BASE" "$artifact"
	fi
}

sha256_file() {
	file=$1
	if have shasum; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif have sha256sum; then
		sha256sum "$file" | awk '{print $1}'
	else
		warn "shasum or sha256sum is required to verify Perch release artifacts."
		return 1
	fi
}

verify_checksum() {
	file=$1
	checksum_file=$2
	expected=$(awk '{print $1; exit}' "$checksum_file")
	actual=$(sha256_file "$file") || return 1
	if [ -z "$expected" ]; then
		warn "Checksum file is empty or invalid."
		return 1
	fi
	if [ "$expected" != "$actual" ]; then
		warn "Checksum verification failed for downloaded Perch CLI."
		warn "Expected: $expected"
		warn "Actual:   $actual"
		return 1
	fi
}

install_cli_from_release() {
	artifact=$(platform_artifact) || return 1
	url=$(release_url "$artifact")
	checksum_url=$(release_url "$artifact.sha256")
	tmp=$(mktemp "${TMPDIR:-/tmp}/perch.XXXXXX")
	checksum_tmp=$(mktemp "${TMPDIR:-/tmp}/perch.XXXXXX.sha256")
	if download "$url" "$tmp" && download "$checksum_url" "$checksum_tmp" && verify_checksum "$tmp" "$checksum_tmp"; then
		chmod +x "$tmp"
		if "$tmp" --help >/dev/null 2>&1 && "$tmp" --version 2>/dev/null | grep -qi '^perch '; then
			mkdir -p "$INSTALL_DIR"
			mv "$tmp" "$CLI_DEST"
			rm -f "$checksum_tmp"
			log "  ✓ Downloaded $artifact from GitHub Release"
			log "  ✓ Verified SHA-256 checksum"
			log "  ✓ Verified Perch CLI identity"
			log "  ✓ Installed to $CLI_DEST"
			return 0
		fi
		warn "Downloaded binary did not identify as Perch CLI."
	fi
	rm -f "$tmp" "$checksum_tmp"
	return 1
}

install_cli_from_cargo() {
	if [ ! -f "$LOCAL_CARGO_MANIFEST" ]; then
		warn "Local Cargo manifest not found: $LOCAL_CARGO_MANIFEST"
		return 1
	fi
	if ! have cargo; then
		warn "cargo not found — cannot build local CLI fallback (install Rust from https://rustup.rs)"
		return 1
	fi
	log "  - Building perch CLI from local source..."
	cargo build --release --manifest-path "$LOCAL_CARGO_MANIFEST" --quiet
	mkdir -p "$INSTALL_DIR"
	cp "$SCRIPT_DIR/cli/target/release/perch" "$CLI_DEST"
	chmod +x "$CLI_DEST"
	log "  ✓ Built and installed to $CLI_DEST"
}

fetch_command_template() {
	command_template_dest=$1
	if [ "$LOCAL_MODE" -eq 1 ] && [ -f "$LOCAL_COMMAND_SOURCE" ]; then
		cp "$LOCAL_COMMAND_SOURCE" "$command_template_dest"
		return 0
	fi
	download "$RAW_BASE/Commands/perch.md" "$command_template_dest"
}

install_skill() {
	skill_dest=$1
	tmp=$(mktemp "${TMPDIR:-/tmp}/perch-command.XXXXXX")
	fetch_command_template "$tmp"
	mkdir -p "$(dirname "$skill_dest")"
	{
		cat <<'EOF'
---
name: perch
description: 'Save current AI coding agent session to Perch, or mark it as done'
disable-model-invocation: true
---

EOF
		cat "$tmp"
	} >"$skill_dest"
	rm -f "$tmp"
}

install_command() {
	command_dest=$1
	tmp=$(mktemp "${TMPDIR:-/tmp}/perch-command.XXXXXX")
	fetch_command_template "$tmp"
	mkdir -p "$(dirname "$command_dest")"
	cp "$tmp" "$command_dest"
	rm -f "$tmp"
}

init_config() {
	mkdir -p "$CONFIG_DIR"
	if [ ! -f "$SESSIONS_FILE" ]; then
		printf '[]' >"$SESSIONS_FILE"
	fi
	if [ ! -f "$CONFIG_FILE" ]; then
		cat >"$CONFIG_FILE" <<'EOF'
# Perch configuration
terminal = ghostty
sort-by = date
max-sessions = 20
auto-start = true
show-badge = true
EOF
	fi
}

install_agent_commands() {
	if have claude; then
		install_command "$HOME/.claude/commands/perch.md"
		log "  ✓ Claude Code → $HOME/.claude/commands/perch.md"
	else
		log "  - claude not found"
	fi

	if have codex; then
		install_skill "$HOME/.codex/skills/perch/SKILL.md"
		log "  ✓ Codex → $HOME/.codex/skills/perch/SKILL.md"
	else
		log "  - codex not found"
	fi

	if have pi; then
		install_skill "$HOME/.pi/agent/skills/perch/SKILL.md"
		log "  ✓ Pi → $HOME/.pi/agent/skills/perch/SKILL.md"
	else
		log "  - pi not found"
	fi

	if have droid; then
		install_skill "$HOME/.factory/skills/perch/SKILL.md"
		log "  ✓ Droid → $HOME/.factory/skills/perch/SKILL.md"
	else
		log "  - droid not found"
	fi

	if have opencode; then
		install_command "$HOME/.config/opencode/commands/perch.md"
		log "  ✓ OpenCode → $HOME/.config/opencode/commands/perch.md"
	else
		log "  - opencode not found"
	fi
}

open_local_app_if_available() {
	if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
		return 0
	fi
	for app in "$SCRIPT_DIR/App/.build/release/PerchApp" "$SCRIPT_DIR/App/.build/debug/PerchApp" "/Applications/Perch.app"; do
		if [ -e "$app" ] && have open; then
			open "$app" >/dev/null 2>&1 || true
			log "  ✓ Opened $app"
			return 0
		fi
	done
	log "  - Perch.app not found locally, skipped"
}

log "Perch installer"
log ""
log "Installing CLI:"
if [ "${PERCH_INSTALL_SOURCE:-}" = "local" ]; then
	install_cli_from_cargo
elif ! install_cli_from_release; then
	if [ "$LOCAL_MODE" -eq 1 ]; then
		warn "  - Release download failed; falling back to local Cargo build."
		install_cli_from_cargo
	else
		warn "Could not download Perch CLI from GitHub Releases."
		exit 1
	fi
fi

log ""
log "Configuration:"
init_config
log "  ✓ $SESSIONS_FILE"
log "  ✓ $CONFIG_FILE"

log ""
log "Installing agent commands:"
install_agent_commands

log ""
log "Opening Perch:"
open_local_app_if_available

log ""
log "Next steps:"
log "  1. Make sure $INSTALL_DIR is in your PATH."
log "  2. Restart your coding agent."
log "  3. Type /perch inside a coding session."
log "  4. Run perch doctor to verify your setup."

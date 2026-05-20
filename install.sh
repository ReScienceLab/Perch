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
APP_INSTALL_DIR="${PERCH_APP_INSTALL_DIR:-$HOME/.local/share/perch}"
APP_DEST="$APP_INSTALL_DIR/PerchApp"
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

PERCH_INSTALL_APP_EXPLICIT=1
if [ -z "${PERCH_INSTALL_APP+x}" ]; then
	PERCH_INSTALL_APP_EXPLICIT=0
	if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
		PERCH_INSTALL_APP=1
	else
		PERCH_INSTALL_APP=0
	fi
fi

PERCH_OPEN_APP="${PERCH_OPEN_APP:-1}"

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

platform_app_artifact() {
	os=$(uname -s 2>/dev/null || printf unknown)
	arch=$(uname -m 2>/dev/null || printf unknown)
	case "$os:$arch" in
	Darwin:arm64) printf 'PerchApp-aarch64-apple-darwin.zip' ;;
	Darwin:x86_64) printf 'PerchApp-x86_64-apple-darwin.zip' ;;
	*)
		warn "PerchApp is currently available for macOS only. Detected: $os $arch"
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
	label=${3:-downloaded Perch artifact}
	expected=$(awk '{print $1; exit}' "$checksum_file")
	actual=$(sha256_file "$file") || return 1
	if [ -z "$expected" ]; then
		warn "Checksum file is empty or invalid."
		return 1
	fi
	if [ "$expected" != "$actual" ]; then
		warn "Checksum verification failed for $label."
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
	if download "$url" "$tmp" && download "$checksum_url" "$checksum_tmp" && verify_checksum "$tmp" "$checksum_tmp" "downloaded Perch CLI"; then
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

extract_zip() {
	zip_file=$1
	dest_dir=$2
	if have unzip; then
		unzip -q "$zip_file" -d "$dest_dir" || return 1
	else
		warn "unzip is required to install PerchApp release artifacts."
		return 1
	fi
}

find_extracted_app() {
	extract_dir=$1
	for app in \
		"$extract_dir/PerchApp" \
		"$extract_dir/Perch.app/Contents/MacOS/PerchApp" \
		"$extract_dir/PerchApp.app/Contents/MacOS/PerchApp"; do
		if [ -f "$app" ]; then
			printf '%s' "$app"
			return 0
		fi
	done
	return 1
}

expected_macho_arch() {
	case "$(uname -m 2>/dev/null || true)" in
	arm64) printf 'arm64' ;;
	x86_64) printf 'x86_64' ;;
	*) return 1 ;;
	esac
}

validate_macho_executable() {
	app=$1
	magic=$(od -An -tx1 -N4 "$app" 2>/dev/null | tr -d ' \n')
	case "$magic" in
	feedface | cefaedfe | feedfacf | cffaedfe | cafebabe | bebafeca)
		;;
	*)
		warn "Downloaded PerchApp is not a Mach-O executable: $app"
		return 1
		;;
	esac
	if have otool; then
		otool -hv "$app" >/dev/null 2>&1 || {
			warn "Downloaded PerchApp failed Mach-O header validation: $app"
			return 1
		}
	fi
	if have lipo; then
		expected_arch=$(expected_macho_arch) || expected_arch=
		if [ -n "$expected_arch" ]; then
			lipo_archs=$(lipo -archs "$app" 2>/dev/null || true)
			case " $lipo_archs " in
			*" $expected_arch "*) ;;
			*)
				warn "Downloaded PerchApp does not contain expected architecture $expected_arch: $lipo_archs"
				return 1
				;;
			esac
		fi
	fi
	return 0
}

install_app_from_release() {
	if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
		log "  - PerchApp install skipped (macOS only)"
		return 0
	fi
	artifact=$(platform_app_artifact) || return 1
	url=$(release_url "$artifact")
	checksum_url=$(release_url "$artifact.sha256")
	zip_tmp=$(mktemp "${TMPDIR:-/tmp}/perch-app.XXXXXX.zip")
	checksum_tmp=$(mktemp "${TMPDIR:-/tmp}/perch-app.XXXXXX.sha256")
	extract_tmp=$(mktemp -d "${TMPDIR:-/tmp}/perch-app.XXXXXX")
	if download "$url" "$zip_tmp" && download "$checksum_url" "$checksum_tmp" && verify_checksum "$zip_tmp" "$checksum_tmp" "downloaded PerchApp"; then
		extract_zip "$zip_tmp" "$extract_tmp" || {
			warn "Failed to extract PerchApp artifact."
			rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
			return 1
		}
		extracted_app=$(find_extracted_app "$extract_tmp") || {
			warn "Downloaded PerchApp artifact did not contain PerchApp."
			rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
			return 1
		}
		if [ ! -x "$extracted_app" ]; then
			warn "Downloaded PerchApp is not executable: $extracted_app"
			rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
			return 1
		fi
		if ! validate_macho_executable "$extracted_app"; then
			rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
			return 1
		fi
		mkdir -p "$APP_INSTALL_DIR"
		app_tmp=$(mktemp "$APP_DEST.tmp.XXXXXX")
		cp "$extracted_app" "$app_tmp"
		chmod +x "$app_tmp"
		mv "$app_tmp" "$APP_DEST"
		rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
		log "  ✓ Downloaded $artifact from GitHub Release"
		log "  ✓ Verified SHA-256 checksum"
		log "  ✓ Installed PerchApp to $APP_DEST"
		return 0
	fi
	rm -rf "$zip_tmp" "$checksum_tmp" "$extract_tmp"
	return 1
}

local_app_candidate() {
	for app in \
		"$SCRIPT_DIR/App/.build/arm64-apple-macosx/release/PerchApp" \
		"$SCRIPT_DIR/App/.build/x86_64-apple-macosx/release/PerchApp" \
		"$SCRIPT_DIR/App/.build/release/PerchApp" \
		"$SCRIPT_DIR/App/.build/arm64-apple-macosx/debug/PerchApp" \
		"$SCRIPT_DIR/App/.build/x86_64-apple-macosx/debug/PerchApp" \
		"$SCRIPT_DIR/App/.build/debug/PerchApp" \
		"$HOME/Applications/Perch.app" \
		"/Applications/Perch.app"; do
		if [ -e "$app" ]; then
			printf '%s' "$app"
			return 0
		fi
	done
	return 1
}

install_app_from_local_build_if_available() {
	app=$(local_app_candidate 2>/dev/null || true)
	if [ -z "$app" ] || [ ! -f "$app" ]; then
		return 1
	fi
	if [ ! -x "$app" ]; then
		warn "Local PerchApp is not executable: $app"
		return 1
	fi
	mkdir -p "$APP_INSTALL_DIR"
	cp "$app" "$APP_DEST"
	chmod +x "$APP_DEST"
	log "  ✓ Installed local PerchApp to $APP_DEST"
}

install_perch_app() {
	if [ "$PERCH_INSTALL_APP" = "0" ]; then
		log "  - PerchApp install skipped (PERCH_INSTALL_APP=0)"
		return 0
	fi
	if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
		log "  - PerchApp install skipped (macOS only)"
		return 0
	fi
	if [ "${PERCH_INSTALL_SOURCE:-}" = "local" ]; then
		if install_app_from_local_build_if_available; then
			return 0
		fi
		log "  - Local PerchApp build not found, skipped"
		return 0
	fi
	if install_app_from_release; then
		return 0
	fi
	if [ "$PERCH_INSTALL_APP_EXPLICIT" -eq 1 ]; then
		warn "PerchApp installation failed. Set PERCH_INSTALL_APP=0 to skip app installation."
		return 1
	fi
	warn "  - PerchApp release artifact unavailable; CLI installation will continue."
	warn "  - Re-run with PERCH_INSTALL_APP=1 after the next release to require app installation."
	return 0
}

open_app_path() {
	app=$1
	if [ -z "$app" ] || [ ! -e "$app" ]; then
		return 1
	fi
	case "$app" in
	*.app)
		if have open; then
			open "$app" >/dev/null 2>&1 || true
			log "  ✓ Opened $app"
			return 0
		fi
		;;
	*)
		if [ -x "$app" ]; then
			"$app" >/dev/null 2>&1 &
			log "  ✓ Opened $app"
			return 0
		fi
		;;
	esac
	return 1
}

open_perch_app_if_available() {
	if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
		return 0
	fi
	if [ "$PERCH_OPEN_APP" = "0" ]; then
		log "  - PerchApp open skipped (PERCH_OPEN_APP=0)"
		return 0
	fi
	if open_app_path "$APP_DEST"; then
		return 0
	fi
	if [ "$LOCAL_MODE" -eq 1 ]; then
		local_candidate=$(local_app_candidate 2>/dev/null || true)
		if [ -n "$local_candidate" ] && [ "$local_candidate" != "$APP_DEST" ] && open_app_path "$local_candidate"; then
			return 0
		fi
	fi
	log "  - PerchApp not found, skipped"
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
log "Installing PerchApp:"
install_perch_app

log ""
log "Opening Perch:"
open_perch_app_if_available

log ""
log "Next steps:"
log "  1. Make sure $INSTALL_DIR is in your PATH."
log "  2. Restart your coding agent."
log "  3. Type /perch inside a coding session."
log "  4. Run perch doctor to verify your setup."

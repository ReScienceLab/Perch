#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

cargo test --manifest-path "$ROOT/cli/Cargo.toml"
(cd "$ROOT/App" && swift test)
"$ROOT/tests/install.sh"
python3 "$ROOT/tests/schema.py"

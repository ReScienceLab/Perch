Save the current AI coding agent session to Perch, or mark it as done.

This is one shared command for all agents. You are already running inside exactly one agent, so first choose your own agent identity and then use only that agent's session-ID detector.

Hard rules:

- Do not try detectors for other agents.
- Do not run `droid`, `codex`, `pi`, `opencode`, `hermes`, or `claude` discovery commands unless that is the agent you are currently running inside.
- If you are Claude Code, `AGENT=claude`. If you are Codex, `AGENT=codex`. If you are Pi, `AGENT=pi`. If you are Droid, `AGENT=droid`. If you are OpenCode, `AGENT=opencode`. If you are Hermes Agent, `AGENT=hermes`.

## 1. Get the current session ID

Run only the detector for your current `AGENT`.

### Claude Code (`AGENT=claude`)

```sh
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-${CLAUDE_CONVERSATION_ID:-${SESSION_ID:-}}}}"
if [ -z "$SESSION_ID" ]; then
  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/$(pwd | sed 's#/#-#g')"
  SESSION_ID=$(python3 - "$CLAUDE_PROJECT_DIR/sessions-index.json" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
    entries = [e for e in data.get("entries", []) if not e.get("isSidechain")]
    def sort_key(e):
        fp = e.get("fullPath")
        if fp and os.path.exists(fp):
            return os.path.getmtime(fp)
        return float(e.get("fileMtime") or 0)
    entries.sort(key=sort_key, reverse=True)
    print(entries[0].get("sessionId", "") if entries else "")
except Exception:
    print("")
PY
)
fi
printf '%s\n' "$SESSION_ID"
```

### Codex (`AGENT=codex`)

```sh
SESSION_ID="${CODEX_SESSION_ID:-${SESSION_ID:-}}"
if [ -z "$SESSION_ID" ]; then
  SESSION_FILE=$(find "$HOME/.codex/sessions" -name '*.jsonl' -type f 2>/dev/null | sort | tail -1)
  SESSION_ID=$(basename "$SESSION_FILE" .jsonl | sed -E 's/^.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/\1/')
fi
printf '%s\n' "$SESSION_ID"
```

### Pi (`AGENT=pi`)

```sh
SESSION_ID="${PI_SESSION_ID:-${SESSION_ID:-}}"
if [ -z "$SESSION_ID" ]; then
  ENCODED_CWD="--$(pwd | sed 's#^/##; s#/#-#g')--"
  SESSION_FILE=$(ls -t "$HOME/.pi/agent/sessions/$ENCODED_CWD/"*.jsonl 2>/dev/null | head -1)
  SESSION_ID=$(basename "$SESSION_FILE" .jsonl | sed 's/^.*_//')
fi
printf '%s\n' "$SESSION_ID"
```

### Droid (`AGENT=droid`)

```sh
SESSION_ID="${DROID_SESSION_ID:-${SESSION_ID:-}}"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(droid session list --json 2>/dev/null | python3 -c "import json,sys; s=json.load(sys.stdin); print(s[0]['id'] if s else '')" 2>/dev/null)
fi
printf '%s\n' "$SESSION_ID"
```

### OpenCode (`AGENT=opencode`)

```sh
SESSION_ID="${OPENCODE_SESSION_ID:-${SESSION_ID:-}}"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(opencode session list 2>/dev/null | head -1 | awk '{print $1}')
fi
printf '%s\n' "$SESSION_ID"
```

### Hermes Agent (`AGENT=hermes`)

```sh
SESSION_ID="${HERMES_SESSION_ID:-${SESSION_ID:-}}"
if [ -z "$SESSION_ID" ] && [ -n "${HERMES_TUI_ACTIVE_SESSION_FILE:-}" ]; then
  SESSION_ID=$(python3 - "$HERMES_TUI_ACTIVE_SESSION_FILE" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("session_id", ""))
except Exception:
    print("")
PY
)
fi
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(hermes sessions list --source cli --limit 1 2>/dev/null | awk 'NR>2 {print $NF; exit}')
fi
printf '%s\n' "$SESSION_ID"
```

If the selected detector prints an empty value, stop and tell the user Perch could not determine the current session ID.

## 2. If `$ARGUMENTS` is `done`

Run:

```sh
perch done --session-id "<SESSION_ID>"
```

Then confirm:

✓ Perch: marked as done

## 3. Otherwise, save the session

1. Determine the title:
   - If `$ARGUMENTS` is non-empty, use it as the title (truncate to 30 characters if needed).
   - Otherwise, auto-generate a title in the format `[Project/Topic]: [brief description]`:
     - `[Project/Topic]`: the main app, codebase, or subject (1–3 words)
     - `[brief description]`: what was done or decided, ≤15 characters
     - Total title must be ≤30 characters
     - Examples: `MyApp: fix login bug`, `Backend: add auth endpoint`, `CLI: refactor config`

2. Run:

```sh
perch add --title "<TITLE>" --agent "<AGENT>" --session-id "<SESSION_ID>"
```

3. Confirm:

✓ Perch: <title>

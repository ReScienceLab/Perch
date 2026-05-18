Save the current Claude Code session to Perch for later resumption.

Steps:

1. Determine the title:
   - If $ARGUMENTS is non-empty, use it as the title (truncate to 30 characters if needed).
   - Otherwise, auto-generate a title in the format `[Project/Topic]: [brief description]`:
     - `[Project/Topic]`: the main app, codebase, or subject (1–3 words)
     - `[brief description]`: what was done or decided, **≤10 Chinese characters or ≤15 English characters**
     - Total title must be ≤30 characters
     - Examples: `Perch: icon 渲染修复`, `AWS Bedrock: 申诉跟进`, `SnapAction: 域名改名调研`

2. Run the following shell commands:

```sh
mkdir -p ~/.config/perch
```

3. Append a new session entry to `~/.config/perch/sessions.json` using Python. If the file does not exist or is empty, start with an empty list `[]`.

Run this Python snippet (replace placeholders with actual values before running):

```python
import json, uuid, datetime, subprocess, os, pathlib

sessions_path = pathlib.Path.home() / ".config" / "perch" / "sessions.json"

try:
    sessions = json.loads(sessions_path.read_text())
except Exception:
    sessions = []

working_dir = subprocess.check_output(["pwd"], text=True).strip()
session_id = "${CLAUDE_SESSION_ID}"
note = ""
title = "<GENERATED_OR_ARGUMENT_TITLE>"

entry = {
    "id": str(uuid.uuid4()).lower(),
    "agent": "claude",
    "session_id": session_id,
    "working_dir": working_dir,
    "title": title,
    "note": note,
    "priority": "medium",
    "status": "pending",
    "created_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "resume_cmd": f"claude --resume {session_id}",
}

sessions.append(entry)
sessions_path.write_text(json.dumps(sessions, indent=2))
print(entry["title"])
```

Important: Replace `<GENERATED_OR_ARGUMENT_TITLE>` with the actual title determined in step 1 before executing.

4. Confirm to the user with exactly this message (substituting the real title):

✓ Perch: <title>

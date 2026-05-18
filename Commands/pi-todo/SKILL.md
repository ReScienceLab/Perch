---
name: todo
description: 'Save current Pi session to Perch for later resumption'
disable-model-invocation: true
---

Save the current Pi session to Perch for later resumption.

Steps:

1. Get the current working directory:

```sh
pwd
```

2. Compute `ENCODED_CWD` by replacing every `/` in the CWD with `-` and wrapping the result with `--` on both ends. For example, `/Users/me/proj` becomes `--Users-me-proj--`.

3. Find the most recent Pi session file for this directory:

```sh
ls -t "$HOME/.pi/agent/sessions/$ENCODED_CWD/"*.jsonl 2>/dev/null | head -1
```

4. Extract the session ID as the UUID portion of the filename: everything after the last `_` and before `.jsonl`. For example, from `2026-03-01T04-10-17-716Z_48750e16-1234-5678-abcd-ef0123456789.jsonl` the session ID is `48750e16-1234-5678-abcd-ef0123456789`.

5. Determine the title:
   - If $ARGUMENTS is non-empty, use it as the title (truncate to 60 characters if needed).
   - Otherwise, auto-generate a concise title (≤60 characters) that summarises the current conversation.

6. Append a new session entry to `~/.config/perch/sessions.json` using Python. If the file does not exist or is empty, start with an empty list `[]`.

Run this Python snippet (replace placeholders with actual values before running):

```python
import json, uuid, datetime, subprocess, os, pathlib

sessions_path = pathlib.Path.home() / ".config" / "perch" / "sessions.json"
pathlib.Path.home().joinpath(".config", "perch").mkdir(parents=True, exist_ok=True)

try:
    sessions = json.loads(sessions_path.read_text())
except Exception:
    sessions = []

working_dir = subprocess.check_output(["pwd"], text=True).strip()
session_id = "<SESSION_ID>"
note = ""
title = "<GENERATED_OR_ARGUMENT_TITLE>"

entry = {
    "id": str(uuid.uuid4()).lower(),
    "agent": "pi",
    "session_id": session_id,
    "working_dir": working_dir,
    "title": title,
    "note": note,
    "priority": "medium",
    "status": "pending",
    "created_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "resume_cmd": f"pi --session {session_id}",
}

sessions.append(entry)
sessions_path.write_text(json.dumps(sessions, indent=2))
print(entry["title"])
```

Important: Replace `<SESSION_ID>` with the session ID from step 4 and `<GENERATED_OR_ARGUMENT_TITLE>` with the actual title determined in step 5 before executing.

7. Confirm to the user with exactly this message (substituting the real title):

✓ Perch: <title>

---
name: perch
description: 'Save current Pi session to Perch for later resumption'
disable-model-invocation: true
---

Save the current Pi session to Perch for later resumption.

Steps:

1. Get the current working directory and compute the encoded path:

```sh
pwd
```

Encode by replacing every `/` with `-` and wrapping with `--` on both ends.
Example: `/Users/me/proj` → `--Users-me-proj--`

2. Find the most recent Pi session ID:

```sh
ls -t "$HOME/.pi/agent/sessions/<ENCODED_CWD>/"*.jsonl 2>/dev/null | head -1
```

Extract the UUID: everything after the last `_` and before `.jsonl`.

3. Determine the title:
   - If $ARGUMENTS is non-empty, use it as the title (truncate to 30 characters if needed).
   - Otherwise, auto-generate a title in the format `[Project/Topic]: [brief description]`:
     - `[Project/Topic]`: the main app, codebase, or subject (1–3 words)
     - `[brief description]`: what was done or decided, ≤15 characters
     - Total title must be ≤30 characters
     - Examples: `MyApp: fix login bug`, `Backend: add auth endpoint`, `CLI: refactor config`

4. Run:

```sh
perch add --title "<TITLE>" --agent pi --session-id <SESSION_ID>
```

Replace `<TITLE>` and `<SESSION_ID>` with the values from steps 2–3.

5. Confirm to the user with exactly this message (substituting the real title):

✓ Perch: <title>

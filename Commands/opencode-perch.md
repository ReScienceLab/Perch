Save the current OpenCode session to Perch for later resumption.

Steps:

1. Find the most recent OpenCode session ID:

```sh
opencode session list 2>/dev/null | head -1
```

Extract the session ID from the first line of the output (OpenCode lists sessions newest first).

2. Determine the title:
   - If $ARGUMENTS is non-empty, use it as the title (truncate to 30 characters if needed).
   - Otherwise, auto-generate a title in the format `[Project/Topic]: [brief description]`:
     - `[Project/Topic]`: the main app, codebase, or subject (1–3 words)
     - `[brief description]`: what was done or decided, ≤15 characters
     - Total title must be ≤30 characters
     - Examples: `MyApp: fix login bug`, `Backend: add auth endpoint`, `CLI: refactor config`

3. Run:

```sh
perch add --title "<TITLE>" --agent opencode --session-id <SESSION_ID>
```

Replace `<TITLE>` and `<SESSION_ID>` with the values from steps 1–2.

4. Confirm to the user with exactly this message (substituting the real title):

✓ Perch: <title>

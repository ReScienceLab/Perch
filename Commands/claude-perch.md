Save the current Claude Code session to Perch for later resumption.

Steps:

1. Determine the title:
   - If $ARGUMENTS is non-empty, use it as the title (truncate to 30 characters if needed).
   - Otherwise, auto-generate a title in the format `[Project/Topic]: [brief description]`:
     - `[Project/Topic]`: the main app, codebase, or subject (1–3 words)
     - `[brief description]`: what was done or decided, ≤15 characters
     - Total title must be ≤30 characters
     - Examples: `MyApp: fix login bug`, `Backend: add auth endpoint`, `CLI: refactor config`

2. Run:

```sh
perch add --title "<TITLE>" --agent claude --session-id ${CLAUDE_SESSION_ID}
```

Replace `<TITLE>` with the title from step 1.

3. Confirm to the user with exactly this message (substituting the real title):

✓ Perch: <title>

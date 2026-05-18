Save the current Claude Code session to Perch, or mark it as done.

## If $ARGUMENTS is "done"

Run:

```sh
perch done --session-id ${CLAUDE_SESSION_ID}
```

Then confirm:

✓ Perch: marked as done

## Otherwise (save session)

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

3. Confirm:

✓ Perch: <title>

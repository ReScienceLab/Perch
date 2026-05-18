Save the current OpenCode session to Perch, or mark it as done.

## If $ARGUMENTS is "done"

1. Find the most recent OpenCode session ID:

```sh
opencode session list 2>/dev/null | head -1
```

Extract the session ID from the first line.

2. Run:

```sh
perch done --session-id <SESSION_ID>
```

3. Confirm:

✓ Perch: marked as done

## Otherwise (save session)

1. Find the most recent OpenCode session ID (same as above).

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

4. Confirm:

✓ Perch: <title>

---
name: phx:investigate
description: Investigate a bug or error in Elixir/Phoenix code. Uses Ralph Wiggum approach - checks obvious things first, reads errors literally. Add --parallel for 4-track deep investigation.
argument-hint: <bug description> [--parallel]
disable-model-invocation: true
---

# Investigate Bug

Investigate bugs using the Ralph Wiggum approach: check the
obvious, read errors literally.

## Usage

```
/phx:investigate Users can't log in after password reset
/phx:investigate FunctionClauseError in UserController.show
/phx:investigate Complex auth bug --parallel
```

## Arguments

`$ARGUMENTS` = Bug description or error message. Add `--parallel`
for deep 4-track investigation.

## Mode Selection

Use **parallel mode** (spawn `deep-bug-investigator`) when:
bug mentions 3+ modules, spans multiple contexts, is intermittent
or involves concurrency, or user says `--parallel`/`deep`.

**Otherwise**: Run the sequential workflow below.

## Investigation Workflow

### Step 0: Consult Compound Docs

```bash
grep -rl "KEYWORD" .claude/solutions/ 2>/dev/null
```

If matching solution exists, present it and ask: "Apply this
fix, or investigate fresh?"

### Step 1: Sanity Checks

```bash
mix compile --warnings-as-errors 2>&1 | head -50
mix ecto.migrate
```

### Step 2: Reproduce

```bash
mix test test/path_test.exs --trace
tail -200 log/dev.log | grep -A 5 -i "error\|exception"
```

### Step 3: Read Error LITERALLY

Parse the error message — check `references/error-patterns.md`.

### Step 4: Check the Obvious (Ralph Wiggum Checklist)

File saved? Atom vs string? Data preloaded? Pattern match
correct? Nil? Return value? Server restarted?

**LiveView form saves silently failing?** Check changeset errors
FIRST — not viewport, click mechanics, or JS. A missing
`hidden_input` for a required embedded field causes `{:error,
changeset}` with no visible UI feedback.

### Step 5: IO.inspect / mix run -e

### Step 6: Identify Root Cause

What's actually happening vs what should happen.

## Autonomous Iteration

For autonomous debugging, use `/ralph-loop:ralph-loop` with
clear completion criteria and `--max-iterations`.

## References

- `references/error-patterns.md` — Common errors and checklist
- `references/investigation-template.md` — Output format
- `references/debug-commands.md` — Debug commands and common fixes

---
name: audit-task
description: Audit developed work on the current branch for quality, security, and correctness. Use after development is complete.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Task, AskUserQuestion
argument-hint: [ optional: ticket ID, plan file path, or description ]
---

# Audit Task Implementation

Perform a comprehensive audit of developed work to ensure quality, security, and correctness.

## Arguments

- `$0`: (Optional) Ticket ID, plan file path, or brief task description. If omitted, the audit uses git diff to determine scope and asks the user for acceptance criteria.

## Pre-requisites

### 1. Verify Clean Context

This audit MUST be performed with a clean context to ensure unbiased review.

**Check context state:**

- If this is NOT the first message in the conversation, the context is not clean

**If context is NOT clean:**

Use `AskUserQuestion` to ask:

```
This audit should be performed with a clean context for an unbiased review.

Please run `/clear` and then invoke `/audit-task` again.

Alternatively, if you want to proceed anyway (not recommended), type "continue".
```

**Do NOT proceed until user responds.**

### 2. Identify Changed Files

Get the list of files changed for this task:

```bash
# Get the branch name
git branch --show-current

# Get commits for this task
git log main..HEAD --oneline

# Get all changed files
git diff --name-only main..HEAD
```

If there are no commits ahead of main, fall back to uncommitted changes:

```bash
git diff --name-only HEAD
git diff --name-only --cached
```

Categorize files:

- **Backend**: `lib/storyarn/**`, `lib/storyarn_web/**`, `test/**`
- **Frontend**: `assets/js/**`, `assets/css/**`
- **Config/Infra**: `config/**`, `mix.exs`, `priv/repo/migrations/**`
- **Mixed**: Combination of above

## Audit Process

### 3. Gather Acceptance Criteria

Determine acceptance criteria based on available context:

1. **If a plan file path is provided**: Read the plan file and extract expected outcomes
2. **If a ticket ID is provided**: Ask the user to paste or describe the acceptance criteria
3. **If a description is provided**: Use it as the basis for verification
4. **If nothing is provided**: Infer scope from git diff and ask the user to confirm what the changes should accomplish

Create a checklist:

```markdown
## Acceptance Criteria Checklist

- [ ] AC1: {description}
- [ ] AC2: {description}
  ...
```

### 4. Acceptance Criteria Verification

For EACH acceptance criterion:

1. **Read relevant code** to verify implementation
2. **Check tests** that validate this criterion
3. **Mark as:**
    - PASS: Implemented and tested
    - PARTIAL: Implemented but missing tests or edge cases
    - FAIL: Not implemented or incorrectly implemented

### 5. Bug Detection Audit

Review code for common bugs:

#### Logic Errors

- [ ] Off-by-one errors in loops/comprehensions
- [ ] Incorrect pattern matching (missing clauses, wrong order)
- [ ] Missing nil/empty checks
- [ ] Incorrect guard clauses
- [ ] Unhandled `{:error, _}` tuples (unhappy paths ignored)

#### Process and Concurrency

- [ ] GenServer state leaks or unbounded growth
- [ ] Missing `handle_info` catch-all clause
- [ ] Deadlocks from synchronous GenServer calls
- [ ] Race conditions in concurrent operations
- [ ] Missing process supervision (unsupervised children)
- [ ] Task/Agent misuse where GenServer is appropriate

#### Ecto and Database

- [ ] N+1 query problems (missing preloads)
- [ ] Missing indexes for new queries or foreign keys
- [ ] Unsafe `Repo.get!` without proper error handling
- [ ] Missing `Ecto.Multi` for operations that should be atomic
- [ ] Changeset validations missing or insufficient
- [ ] Missing unique constraints at DB level (relying only on changeset)
- [ ] Migration rollback support (`down/0` function)
- [ ] Stale data issues (missing optimistic locking where needed)

#### LiveView

- [ ] Memory leaks in `handle_info` (assigns growing unbounded)
- [ ] Missing `connected?/1` checks for socket-only operations
- [ ] Expensive operations in `mount/3` instead of `handle_params/3`
- [ ] PubSub subscriptions without corresponding `handle_info`
- [ ] Assigns bloat (large data structures that should be streamed)
- [ ] Missing `phx-debounce` on frequent events

#### Data Handling

- [ ] Type mismatches between Ecto schema and actual usage
- [ ] Incorrect data transformations in pipelines
- [ ] Missing input validation at context boundaries
- [ ] Unsafe string interpolation in queries

### 6. Security Audit

Review for OWASP Top 10 and Elixir/Phoenix-specific vulnerabilities:

#### Input Validation

- [ ] All user input is validated (changesets, params)
- [ ] Validation happens server-side (LiveView events, controller params)
- [ ] File uploads are restricted by type and size
- [ ] Params are cast and validated before use (no raw `params["key"]` in business logic)

#### Injection Prevention

- [ ] SQL injection: Using Ecto queries (no raw SQL with interpolation)
- [ ] XSS: Content is properly escaped (no `raw/1` or `Phoenix.HTML.raw/1` with user data)
- [ ] Command injection: No `System.cmd` or `:os.cmd` with user input
- [ ] Atom exhaustion: No `String.to_atom/1` with user input (use `String.to_existing_atom/1`)

#### Authentication & Authorization

- [ ] LiveView routes have proper `on_mount` hooks
- [ ] Controller routes have proper plugs/pipelines
- [ ] Authorization checks before data mutations
- [ ] Sensitive data not exposed in socket assigns sent to client
- [ ] Resource scoping (users can only access their own data)

#### Data Protection

- [ ] Sensitive data not logged (passwords, tokens, PII)
- [ ] Secrets not hardcoded (use `Application.get_env` or runtime config)
- [ ] PubSub topics scoped to prevent information leakage
- [ ] Downloads/exports don't leak data from other users

#### Frontend Security (LiveView + JS hooks)

- [ ] No sensitive data in `data-*` attributes visible to client
- [ ] CSRF tokens present on forms (automatic in Phoenix, but verify custom forms)
- [ ] JS hooks don't trust client-pushed data without server validation
- [ ] Upload metadata validated server-side

### 7. Code Quality Audit

#### Elixir Idioms and Style

- [ ] Pattern matching preferred over conditional logic
- [ ] Pipeline operator (`|>`) used for data transformations (no deeply nested calls)
- [ ] `with` used for multi-step operations that can fail (not nested `case`)
- [ ] Functions have clear input/output contracts (typespecs on public functions)
- [ ] No unnecessary `if`/`else` when pattern matching suffices
- [ ] Tagged tuples used consistently (`{:ok, result}`, `{:error, reason}`)

#### Module Design

- [ ] Modules have a single, clear responsibility
- [ ] Public API is minimal (private functions for internals)
- [ ] Context modules (facade pattern) used as the public boundary
- [ ] No cross-context direct calls (go through the context module)
- [ ] `@moduledoc` and `@doc` on public modules and functions

#### Function Design

- [ ] Functions are short and focused (< 20 lines preferred)
- [ ] Multi-clause functions ordered from specific to general
- [ ] Guard clauses used to constrain function heads
- [ ] Default arguments used sparingly and clearly
- [ ] No excessive function arity (> 4 args suggests a struct/map)

#### YAGNI (You Aren't Gonna Need It)

- [ ] No unused parameters or function arguments
- [ ] No over-engineered abstractions for single-use cases
- [ ] No features "for the future" beyond the task scope
- [ ] No unnecessary configuration options or indirection

#### KISS (Keep It Simple)

- [ ] Solutions are straightforward
- [ ] No premature optimization
- [ ] No unnecessary metaprogramming (macros where functions suffice)
- [ ] Simple solutions preferred over clever ones

### 8. Dead Code Detection

Search for potentially dead code in changed files:

```bash
# Unused module attributes
# Check @attr definitions not referenced

# Unused private functions
# Search for defp definitions not called within their module

# Unused aliases
# Check alias declarations not used in the module

# Commented-out code blocks
# Search for large blocks of commented code
```

Check for:

- [ ] Unused `alias`, `import`, or `require` declarations
- [ ] Unused private functions (`defp`)
- [ ] Unused module attributes (`@attr`)
- [ ] Commented-out code blocks
- [ ] Unreachable function clauses (shadowed by earlier, broader clauses)
- [ ] Dead LiveView event handlers (no corresponding client-side trigger)

### 9. Run Quality Commands

Run static analysis and tests on the changed code:

```bash
# Format check
mix format --check-formatted

# Static analysis (strict mode)
mix credo --strict

# Run tests
mix test

# Run tests with coverage (if configured)
mix test --cover
```

**Record the output:**

- All checks passed
- Failures (list each)

If only specific test files are relevant, also run them individually:

```bash
mix test path/to/changed_test.exs
```

### 10. Convention Verification

Review changed files for project and Elixir/Phoenix conventions:

#### Naming Conventions

- [ ] Modules use `CamelCase` and reflect their purpose
- [ ] Context modules follow `Storyarn.{ContextName}` pattern
- [ ] Schema modules follow `Storyarn.{Context}.{Schema}` pattern
- [ ] LiveView modules follow `StoryarnWeb.{Resource}Live.{Action}` pattern
- [ ] Component modules follow `StoryarnWeb.Components.{Name}` pattern
- [ ] Controller modules follow `StoryarnWeb.{Resource}Controller` pattern
- [ ] Functions use `snake_case`
- [ ] Predicate functions end with `?` (not prefixed with `is_`)
- [ ] Bang functions end with `!` for functions that raise on error

#### Context Boundaries

- [ ] Business logic lives in context modules (`lib/storyarn/`), not in web layer
- [ ] LiveViews delegate to contexts (thin dispatchers, not fat handlers)
- [ ] No `Repo` calls outside of context modules
- [ ] No `Ecto.Query` imports in web layer

#### Test Conventions

- [ ] Tests exist for new public functions
- [ ] Test module names mirror source module names
- [ ] Tests use `describe` blocks for grouping
- [ ] Tests use meaningful assertion messages where helpful
- [ ] No test interdependence (`async: true` where possible)
- [ ] Fixtures/factories used consistently

#### Gettext / i18n

- [ ] All user-facing strings wrapped in `gettext/1` or `ngettext/3`
- [ ] No hardcoded user-facing strings in templates or flash messages
- [ ] Error messages in changesets use Gettext

### 11. Generate Audit Report

Compile findings into a comprehensive report:

```markdown
# Audit Report: {task description or ticket ID}

## Summary

| Category              | Status            | Issues          |
|-----------------------|-------------------|-----------------|
| Acceptance Criteria   | pass/partial/fail | X of Y passed   |
| Bug Detection         | pass/partial/fail | X issues found  |
| Security              | pass/partial/fail | X issues found  |
| Code Quality          | pass/partial/fail | X issues found  |
| Dead Code             | pass/partial/fail | X items found   |
| Quality Commands      | pass/fail         | Pass/Fail       |
| Convention Compliance | pass/partial/fail | X issues found  |

## Acceptance Criteria

- AC1: {description} — {status and detail}
- AC2: {description} — {status and detail}

## Bugs Found

### Critical

- {bug description} in {file:line}

### Warning

- {potential issue} in {file:line}

## Security Issues

### High

- {security issue}

### Medium

- {security issue}

## Code Quality Issues

### Elixir Idiom Violations

- {violation} in {file}

### Design Issues

- {issue} in {file}

## Dead Code

- {unused item} in {file:line}

## Quality Command Output

{output from mix credo, mix test, mix format}

## Convention Violations

- {violation} in {file}

## Recommendations

1. {High priority fix}
2. {Medium priority fix}
3. {Low priority improvement}

## Verdict

APPROVED — Ready for merge
APPROVED WITH NOTES — Minor issues to address
NEEDS WORK — Critical issues must be fixed

---
Audit completed on {date}
```

## Audit Severity Levels

| Level    | Description                                            | Action                  |
|----------|--------------------------------------------------------|-------------------------|
| Critical | Security vulnerabilities, data loss risk, AC failures  | Must fix before merge   |
| High     | Bugs, significant quality issues                       | Should fix before merge |
| Medium   | Code quality, minor bugs                               | Fix or document         |
| Low      | Suggestions, minor improvements                        | Optional                |

## Final Checklist

Before concluding audit:

- [ ] All acceptance criteria reviewed
- [ ] Security review completed
- [ ] Code quality assessed
- [ ] Dead code checked
- [ ] Quality commands executed (`mix format`, `mix credo`, `mix test`)
- [ ] Convention compliance verified
- [ ] Report generated
- [ ] Verdict provided

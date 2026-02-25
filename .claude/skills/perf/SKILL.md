---
name: phx:perf
description: Analyze Elixir/Phoenix code for performance issues — N+1 queries, LiveView memory, query patterns, OTP bottlenecks. Use when optimizing or profiling.
argument-hint: [ page|context|module ] [ --focus ecto|liveview|otp ]
disable-model-invocation: true
---

# Performance Analysis

Analyze code for performance issues across Ecto, LiveView,
and OTP layers. Prioritize findings by impact and effort.

## Usage

```
/phx:perf                           # Analyze full project
/phx:perf lib/my_app/accounts.ex    # Analyze specific module
/phx:perf --focus ecto              # Ecto queries only
/phx:perf --focus liveview          # LiveView memory only
/phx:perf --focus otp               # OTP bottlenecks only
```

## Arguments

`$ARGUMENTS` = Optional module/context path and `--focus` flag.

## Iron Laws

1. **MEASURE BEFORE OPTIMIZING** — Never optimize without evidence of a problem
2. **DATABASE FIRST** — 90% of Elixir performance issues are query-related
3. **ONE CHANGE AT A TIME** — Isolate optimizations to measure impact

## Workflow

### Step 1: Identify Scope

If specific file provided, focus there. Otherwise:

```bash
# Find hot paths: contexts, LiveViews, workers
find lib/ -name "*.ex" | head -50
```

### Step 2: Run Analysis Tracks

Spawn analysis agents in parallel based on focus:

**Ecto Track** (default or `--focus ecto`):

Spawn `elixir-phoenix:elixir-reviewer` with prompt:
"Analyze for N+1 queries, missing preloads, unindexed queries,
and inefficient patterns. Check: `Repo.all` in loops,
`Enum.map` with Repo calls, missing `preload`, queries without
indexes on WHERE/JOIN columns."

**LiveView Track** (default or `--focus liveview`):

Spawn `elixir-phoenix:elixir-reviewer` with prompt:
"Analyze LiveViews for memory issues: large assigns, missing
streams for lists, assigns that grow unbounded, heavy
`handle_info` processing, missing `assign_async` for slow ops."

**OTP Track** (only with `--focus otp`):

Spawn `elixir-phoenix:otp-advisor` with prompt:
"Analyze for OTP bottlenecks: GenServer mailbox growth,
synchronous calls in hot paths, missing Task.async for
parallel work, ETS opportunities for read-heavy state."

### Step 3: Prioritize Findings

Score each finding on a 2x2 matrix:

|                 | Low Effort | High Effort |
|-----------------|------------|-------------|
| **High Impact** | DO FIRST   | PLAN        |
| **Low Impact**  | QUICK WIN  | SKIP        |

High impact = affects response time, memory per user, or query count.
Low effort = single file change, no migration needed.

### Step 4: Present Top 5

Present findings sorted by priority:

```markdown
## Performance Analysis: {scope}

### 1. {Finding} — DO FIRST

**Impact**: {what improves}
**Location**: {file}:{line}
**Current**: {problematic pattern}
**Fix**: {optimized pattern}
**Estimated gain**: {e.g., "eliminates N+1, reduces queries from O(n) to O(1)"}

### 2. {Finding} — PLAN

...
```

### Step 5: Offer Next Steps

```
How would you like to proceed?

- `/phx:plan` — Plan the optimizations
- `/phx:work` — Apply top priority fix directly
- `/phx:investigate` — Deep-dive into a specific finding
```

## References

- `references/benchmarking.md` — Benchee patterns, profiling, flame graphs

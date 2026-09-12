# Elixir test performance

> Owner: Engineering
>
> Last reviewed: 2026-09-12
>
> Source of truth: [Mix aliases](../../mix.exs), [test bootstrap](../../test/test_helper.exs),
> [runtime configuration](../../config/runtime.exs), [CI workflow](../../.github/workflows/ci.yml)

`mix test` runs server-side tests without Node, Playwright, an asset build, or
starting the application HTTP listener. LiveView renders use `test/fixtures/vite_manifest.json`; these
tests inspect server state and Vue props, not browser execution.

Browser tests still build and load the real assets and start the HTTP endpoint:

```sh
mix test.e2e
mix test test/e2e/blog_test.exs --include e2e
mix test test/e2e/blog_test.exs:16
```

Select `e2e` with `--include` or `--only`, including the `e2e:true` form. An E2E
file with a line selector also activates browser mode, following ExUnit's
location filters. A bare E2E path keeps the default tag exclusions; add
`--include e2e` to run the whole file or directory. Merely installing Playwright
does not start its supervisor in ordinary test runs. The alias passes browser
mode to both runtime configuration and the test helper through
`STORYARN_E2E_TESTS`, so they use the same selection. Scripts that bypass the
alias through `Mix.Tasks.Test.run/1` must set `STORYARN_E2E_TESTS=true` before
starting the application when running browser tests.
`MIX_TEST_PORT` selects the HTTP port; `MIX_TEST_PARTITION` selects the database.
Use a fresh partition for independent worktrees and performance measurements.

The persistence ownership scanner indexes local calls once per source analysis,
and indexes clauses by function name and every accepted arity. Fixed-point
provenance checks reuse those indexes; captures, ambiguous callers and omitted
arguments remain conservative. This removes repeated whole-module traversals
without dropping the ownership inventories or their negative fixtures.
Ownership inventories discover schemas in one pass, then analyze one source
file at a time, reusing its aliases, clauses and Repo provenance across target
tables. Table-specific taint starts fresh for every target. Snapshots retain
source text rather than every file's AST, and are not cached across tests or
runs.

The widest source-only architecture scans share ExUnit's `:source_scans` async
group. They run alongside database tests but do not compete with each other for
the VM file server. Do not add tests that change global application state to this
group without first isolating that state.
Flow snapshot rollback tests that issue `ALTER TABLE` remain in separate
synchronous modules, so the other builder and restore tests can use the SQL
sandbox concurrently without competing for those table locks.

Asset integration tests monitor their own outstanding supervised tasks before
reading the result instead of sleeping for a fixed interval. Analytics tests use immediate
negative mailbox assertions only where their test adapter sends synchronously.
Database-backed workflows retain the real SQL sandbox.
The search regression for more than 250 homonymous definitions seeds its 250
nonmatching sheets and blocks in two database inserts. The matching 251st
definition still uses the normal creation workflow; all candidates and the
original search assertion are retained.

CI caches dependencies by the root `mix.lock`. Build cache keys additionally
include the job, runtime, Mix environment and commit. The first restore prefix
matches the same lock, allowing incremental compilation to be saved after each
commit instead of repeatedly restoring an immutable old build.
Compilation and ExUnit run in separate CI steps. The test Vite manifest is read
by `runtime.exs`, because putting its raw contents in compile configuration
causes even whitespace-only fixture edits to invalidate every application
module. A cache restore followed by recompilation can therefore be correct;
check configuration and source changes before treating it as a cache miss.
Per-commit build entries consume cache capacity for each job and are subject to
[GitHub's cache retention and eviction rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

For focused timing, `mix test PATH --slowest 10` is useful, but it enables trace
mode and serializes test execution. Do not use its wall time as a parallel-suite
benchmark. Compare complete runs with the same revision, seed, scheduler count,
database state and warmed dependencies, and separate compilation from ExUnit time.

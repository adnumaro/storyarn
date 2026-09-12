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
```

Select `e2e` with `--include` or `--only`, including the `e2e:true` form. Merely
installing Playwright does not start its supervisor in ordinary test runs. The
alias passes browser mode to runtime configuration through `STORYARN_E2E_TESTS`,
so Mix configuration reloads retain the selected server and manifest.
`MIX_TEST_PORT` selects the HTTP port; `MIX_TEST_PARTITION` selects the database.
Use a fresh partition for independent worktrees and performance measurements.

The persistence ownership scanner indexes local calls once per source analysis,
and indexes clauses by function name and every accepted arity. Fixed-point
provenance checks reuse those indexes; captures, ambiguous callers and omitted
arguments remain conservative. This removes repeated whole-module traversals
without dropping the ownership inventories or their negative fixtures.

The widest source-only architecture scans share ExUnit's `:source_scans` async
group. They run alongside database tests but do not compete with each other for
the VM file server. Do not add tests that change global application state to this
group without first isolating that state.

Asset integration tests monitor outstanding supervised tasks before reading the
result instead of sleeping for a fixed interval. Analytics tests use immediate
negative mailbox assertions only where their test adapter sends synchronously.
Database-backed workflows retain the real SQL sandbox.

CI caches dependencies by the root `mix.lock`. Build cache keys additionally
include the job, runtime, Mix environment and commit. The first restore prefix
matches the same lock, allowing incremental compilation to be saved after each
commit instead of repeatedly restoring an immutable old build.

For focused timing, `mix test PATH --slowest 10` is useful, but it enables trace
mode and serializes test execution. Do not use its wall time as a parallel-suite
benchmark. Compare complete runs with the same revision, seed, scheduler count,
database state and warmed dependencies, and separate compilation from ExUnit time.

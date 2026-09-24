# Elixir test performance

> Owner: Engineering
>
> Last reviewed: 2026-09-24
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
group without first isolating that state. The group runs serially for about 80
seconds, so wherever the seed placed it, it set the end of the async phase. CI
therefore runs it as its own shard with `--only test_group:source_scans` and
excludes it from the partitioned shards. `test_group` is the tag ExUnit derives
from `group:`, so a module that joins the group moves with it. Local `mix test`
still runs everything.
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
Sharded jobs restore the same build key, and only their first shard saves it.

CI runs Elixir lint, JS lint and Vitest, and export validation as separate jobs.
ExUnit runs in two `--partitions` shards plus the source-scan shard, and
Playwright in two partitions. Each shard sets its own `MIX_TEST_PARTITION`, but
only on the steps after compilation. The variable changes the Repo's database in
`config/test.exs`. On a fresh checkout the config files are newer than the
restored manifest, so Mix compares the evaluated configuration, finds a change
for `:storyarn` and recompiles every module. The
JS job needs `deps/` for the Phoenix and LiveVue npm packages but never compiles
Elixir. Vitest drops LiveVue's Vite plugin. Its dev-server hook exits the
process when stdin closes, and CI runners close it, so Vitest used to exit 0
before running a single test. The CI step still fails when its JSON report
counts no tests.

The docs and blog builders read the public locales into a module attribute,
`@public_locales Locales.locales()`, instead of calling `Locales.valid?/1` while
they build. NimblePublisher runs builders in `Kernel.ParallelCompiler.pmap/2`
tasks, after `Code.ensure_compiled!/1` on the builder. A `.po` change recompiles
`Storyarn.Gettext`, and with it `Storyarn.Public.Publication.Locales`, in the
same cycle. Elixir 1.20 releases pmap tasks waiting on a module only at its
10-second long-compilation check. The compile-time read makes each builder wait
for `Locales` in its own compilation, so no task waits. With runtime calls, a
one-line catalog change took about 40 seconds to recompile locally and about
three minutes per CI job; now it takes a few seconds. `mix compile --profile
time` shows the symptom as repeated `10000ms waiting for module` lines under a
pmap-using file. Any compile-time `pmap` builder must only call application
modules that are already compiled before its tasks start. The formatter hoists
`use` above other module-body expressions, so an ensure call placed before
`use NimblePublisher` does not hold.

For focused timing, `mix test PATH --slowest 10` is useful, but it enables trace
mode and serializes test execution. Do not use its wall time as a parallel-suite
benchmark. Compare complete runs with the same revision, seed, scheduler count,
database state and warmed dependencies, and separate compilation from ExUnit time.

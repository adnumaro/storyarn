# Ownership integrity preflight

> Owner: Engineering
>
> Last reviewed: 2026-08-30
>
> Source of truth: `Storyarn.Architecture.OwnershipIntegrityAudit` and
> `config/architecture_boundaries.exs`

Projects and Workspaces each persist canonical ownership twice: the aggregate's
`owner_id` and one membership whose role is `owner`. The valid state has exactly
one such membership and its `user_id` equals the aggregate's `owner_id`.

The production deploy runs this preflight automatically. Fly's
`release_command` executes `/app/bin/migrate` from the candidate image; after
that image applies its migrations, `Storyarn.Platform.Release` runs
`OwnershipIntegrityAudit.audit!/1`. A finding or SQL failure makes the release
command fail, so Fly does not send traffic to the candidate release.

The Mix task remains a local/development check. It uses the repository
configuration already loaded for the selected `MIX_ENV`; it deliberately does
not load `config/runtime.exs`. Setting `DATABASE_URL` on this command alone
therefore does not retarget it to that database. Verify which repository
configuration it will use:

```console
mix storyarn.ownership.audit
```

This Mix task starts only Ecto, Postgrex and `Storyarn.Repo`; it does not start
`Storyarn.Application`, Oban or the web endpoint. A packaged production release
does not include Mix. For an ad-hoc production diagnosis, use the same
fail-closed entrypoint invoked by the automatic release preflight:

```console
/app/bin/storyarn rpc 'Storyarn.Architecture.OwnershipIntegrityAudit.audit!()'
```

`audit!/0` returns `:ok` only for a clean database and raises for findings or a
query failure, so neither the RPC nor the release command can silently succeed
with drift.

Both entrypoints execute one read-only SQL statement over `projects`,
`project_memberships`, `workspaces`, and `workspace_memberships`. It takes no
explicit row locks, writes no rows, and performs no repair (PostgreSQL still
takes its normal `ACCESS SHARE` table locks for a `SELECT`). A clean database
exits successfully. Drift prints the aggregate type, ID, canonical owner ID,
and all memberships currently carrying the `owner` role, then exits
unsuccessfully.

The release command does not stop the currently serving machines while it runs.
Their ordinary transactional ownership rules remain the protection against a
concurrent write after the audit statement. The preflight proves the database
state observed by its query; it is not a global ownership lock.

The query includes soft-deleted Projects deliberately: they can still return
through restore/recovery workflows, so ownership drift in the trash is not safe
to ignore.

Treat any finding as a deploy stop. Investigate the originating workflow and
repair the specific data under a separately reviewed operational procedure;
never turn this preflight into an automatic data mutation. The audit is an
application-level safety check, not a PostgreSQL constraint and not proof that
concurrent writes after the statement completes cannot introduce drift.

The reviewed source-writer inventory and the explicit list of decentralized
invariant implementations live in `config/architecture_boundaries.exs`. The
architecture tests fail when a statically visible writer or an unclassified
source file carrying the conservative invariant markers appears. The config
also records the limits of that source-level discovery; it is a review ratchet,
not a semantic proof.

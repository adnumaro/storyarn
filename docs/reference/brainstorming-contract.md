# Brainstorming session contract

> Owner: Engineering
>
> Last reviewed: 2026-09-07
>
> Source of truth: `Storyarn.Ideation` and its session commands/queries

This is the internal session foundation of ENG-130, not a released brainstorming
tool. The board, ideas and publication are separate deliveries in ENG-132/133/134.
The broader plan remains in Linear's Brainstorming initiative.

## Ownership and entry points

`Storyarn.Ideation` owns sessions, their independent configuration and session
revisions. Projects retains project identity and effective access. The session
read query and mutation adapter enter its public facade through two exact
cross-context edges. The root Ideation facade delegates through the Sessions
capability facade; schemas live in its `entities/` folder. Ideation starts with an
empty, sealed dependency baseline. No foreign ordinary writer is authorized for
its tables.

The facade exposes create, list, get, update, assign responsibilities, archive,
reopen and history queries. Every call takes current user scope and project ID.
Session IDs are always scoped to that project. Lists/history use descending ID
cursors (`before_id`), default to 50 rows, and reject limits outside 1–200. Session
listing defaults to open sessions; `status: :archived` and `:all` are explicit.

## Access and responsibilities

Session title, objective, context, settings and their history are shared project
content. They must never be presented as private drafts. A title is required;
objective and context are optional. No other entities or participants are needed.

| Operation                          | Project viewer | Project editor | Current facilitator | Project owner |
| ---------------------------------- | -------------- | -------------- | ------------------- | ------------- |
| Read session and history           | Yes            | Yes            | With project access | Yes           |
| Create a session                   | No             | Yes            | With editing access | Yes           |
| Change settings / archive / reopen | No             | No             | With editing access | Yes           |
| Assign responsibilities            | No             | No             | With editing access | Yes           |

Creation appoints the creator as facilitator and decision owner. These are two
separate assignments. Decision ownership grants no session-management rights.
Delegating facilitation removes the previous holder's authority, including when
that person created the session. There is no permanent creator privilege.

Delegates must have current project editing access. These assignments never
create project membership. Projects resolves direct roles before inherited
workspace roles, so a direct viewer role denies writing even for a workspace
editor. Revocation and downgrade apply to already-created scopes; callers cannot
rely on cached UI permissions. The owner can repair responsibilities if the
facilitator leaves, including while the session is archived.

Physical account deletion can leave either responsibility unassigned. Repair may
update one responsibility while preserving the other, including an existing
unassigned value. Explicit blank assignments are rejected. Candidate eligibility
is checked by ID through an actor-scoped Projects port; no candidate identity is
used to authenticate the caller.

## Configuration and concurrency

Configuration stores separate round and timer preferences, optional duration,
new-idea default visibility and publication policy. Defaults disable rounds and
timer and specify private, author-controlled drafts. Enabling the timer requires
a duration between 15 seconds and 24 hours. These are preferences only: this
delivery contains no running rounds, clock, drafts or reveal operation.

Writes take Project authorization locks before the session row lock and validate
any requested delegate under current access locks. Updates require the revision
the caller read. A competing edit returns `{:error, :stale_revision}` without
overwriting the head or history; adapters must retain their unsaved input.

Each effective mutation atomically stores the session and a full revision in the
same transaction. Session revisions increase on any effective change; the separate
configuration version increases only on configuration changes. No-op writes add
no revision. Historical content is not rewritten by subsequent edits.

## Lifecycle and recovery boundary

Archive preserves ID, configuration and revision history. Ordinary editing is
rejected until reopen, while responsibility repair remains available. Archive
does not discard ideas or initiate retention. Project soft deletion denies access;
physical project deletion cascades its session and revision rows. Physical account
deletion nulls live user references without deleting history. Historical snapshots
retain opaque user IDs, not copied names/emails; future displays must handle an
unavailable author.

**Existing Project snapshots do not include these tables.** There is no navigation,
route or user-facing ingestion path for this foundation. Enabling the tool is
gated by ENG-147 recovery coverage and ENG-129 private-content handling, not merely
by completing a Vue board. No claim of complete brainstorming backup/export is
valid until that integration ships.

## Validation

`test/storyarn/ideation/` exercises project isolation, direct/inherited permissions,
revocation, responsibility changes, configuration versions, archive/reopen,
bounded reads and retained revisions. Concurrency tests use independent database
connections: only one stale-head contender commits, and a writer waiting behind
a membership downgrade reauthorizes after the downgrade commits.

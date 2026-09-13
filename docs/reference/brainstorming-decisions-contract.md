# Brainstorming decisions

> Scope: decision recording slice of ENG-141
>
> Last reviewed: 2026-09-13

Decisions record a proposed conclusion, its reason, a responsible participant and
the shared ideas or group synthesis supporting it. Acceptance is explicit.
Exploring content, grouping notes, writing synthesis and ending a round do not
create or accept a decision automatically. A session can use decisions without
using rounds or a timer, and can remain an exploration without any decisions.

## Proposal and agreement

A proposal requires a title, conclusion, reason, responsible participant and at
least one shared source from its own session. An editor selects published ideas
or groups; the server prepares the exact identities and versions available to
that editor. The responsible participant must have current project edit access.
Assigning responsibility does not grant membership or publish private material.
Only the proposal's responsible participant, with current edit access, can
accept it. Project ownership, facilitation and the session's decision-owner
assignment do not grant acceptance authority. An explicit revision can reassign
responsibility only when submitted by the current responsible participant or
the project owner; the owner can repair an unavailable assignment without
accepting on that participant's behalf.

Each decision has one current proposal and may also have a previously accepted
agreement. Creating the proposal writes revision 1. Every revision or acceptance
adds an immutable numbered record with the acting participant, responsibility,
text, sources, timestamp and durable request receipt.

Acceptance preserves the proposal's content and records a new `accept` revision.
`accepted_version` points to that revision number. Revising an accepted decision
creates a new `proposed` revision and retains the previous accepted agreement.
Accepting the new proposal updates the accepted pointer while all earlier
agreements and their supporting sources remain in history. Revising a conclusion
does not silently withdraw or replace the existing agreement.

The two persisted statuses are `proposed` and `accepted`. A proposed decision
with an accepted version has a pending revision alongside its earlier agreement.
This slice has no rejection, deletion, automatic application or undo of agreement
history. Responsibility changes are explicit revisions rather than mutable
metadata outside the audit trail.

## Sources and visibility

Each source pin contains its type, database ID, immutable recovery identity,
published idea revision or group revision, and original author. Frozen source
text is separate encrypted content indexed by recovery UUID. A group contributes
its title and synthesis; its retained group revision already pins the underlying
published ideas. Decision metadata does not duplicate that membership graph.

Only source revisions already shared with the session can support a proposal.
An author's unpublished head is never substituted for a published source. The
source context is a record of what was consulted, not a live copy. Later changes
are identified through current source versions and do not rewrite earlier pins.

Acceptance can confirm a previously consulted version when its source is still
shared and has the same identity. The current version may be newer; the retained
agreement continues to cite the version actually reviewed. Missing, deleted,
inaccessible or unpublished sources prevent acceptance and have their frozen
details redacted in ordinary reads. Their historical pins remain intact.

Current project access governs every query and command. Session private mode
hides decisions before decryption and blocks shared decision mutations. Project
ownership, facilitation, decision authority and responsibility do not grant
access to other authors' private notes. Readers can inspect readable decisions;
mutations recheck current edit permission, session lifecycle and the authority
required for that action. Acceptance rechecks the proposal's current responsible
participant, not a cached session role.

## Persistence, concurrency and limits

Ideation owns the Decisions capability and both `ideation_decisions` and
`ideation_decision_revisions`. External callers use `Storyarn.Ideation`; other
capabilities supply shared sources through their own facades. Decisions never
edit the original notes, group synthesis or referenced authoring tools.

Commands use the existing Project access locks, session lock and an optimistic
decision version. A UUID request identity and content fingerprint make uncertain
retries recognizable. A request cannot acquire a different meaning by reusing
its key. Retry responses are subject to current access and do not execute a
second acceptance or revise an agreement already retained in history.

Proposal and revision commands validate the responsible participant's effective
membership with `FOR SHARE NOWAIT`. If a concurrent membership change holds that
row, the command returns `responsible_busy` without writing a decision revision.
The caller can retry after the change completes; eligibility is checked again.
Successful membership locks remain held through commit. This bounded candidate
check avoids waiting on a second participant while already holding the actor's
membership lock; it does not change the existing blocking authorization port.

A session permits at most 100 decisions, each with at most 100 revisions and
1–20 sources per revision. Decision titles are limited to 160 characters;
conclusions and reasons to 4,000 characters each. Frozen source context is capped
at 256,000 encoded JSON bytes. Reaching a limit produces an explicit failure;
history and provenance are not silently pruned. Events carry invalidation and
identity information rather than creative text.

## Recovery

The sealed Ideation inventory version 6 includes the decision records and every
immutable revision, including all accepted versions and request receipts.
Versions 1–5 normalize to empty decision collections. The Project snapshot
format and the outer encrypted compartment format remain unchanged.

Recovery copies encrypted decision text and source context directly from
persistence. Sessions, decisions, source IDs and actor IDs are remapped through
their existing recovery identities. Revision numbers and recovery UUIDs remain
stable, so the frozen source text needs no ID rewriting. A missing actor becomes
unavailable; no replacement owner or facilitator is credited with the agreement.

Validation requires contiguous revision history, coherent current and accepted
versions, unique receipts, same-session sources, and actual published idea or
retained group revisions. Frozen source text must match the cited revision.
An acceptance must retain the prior proposal's content, responsibility and
sources. Malformed or undecryptable inventories fail before replacement.

Every decision revision participates in session-generation matching. Restoring
an identical generation reuses it; distinct historical generations remain
recoverable. Deleted source notes and groups remain provenance tombstones and
are not republished. Restoring an agreement copies its prior acceptance as a
historical fact; it never invokes acceptance, changes current authority, sends
messages or applies content. See the
[privacy and recovery contract](brainstorming-recovery-contract.md).

Restoring a generation from before a command also preserves the rollback against
retries of that command. The currently authorized generation's receipt takes
precedence. If its receipt is absent but a replaced generation retains the same
actor and request key, scoped to the same project and stable session identity,
the command returns `idempotency_conflict`. This check reads only receipt
existence; it does not expose historical decision content or grant access to the
replaced session. The same key in a different logical session is independent.
Accepting the restored proposal requires a fresh explicit request with a new key.

## Boundaries

Decisions do not create Drafts, materialize authoring entities, apply proposals to
Sheets, Flows or Scenes, create comment conversations, run AI, or send work to
external tools. Those workflows must consume explicit decisions through their
own authorization and provenance contracts when implemented.

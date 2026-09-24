# Brainstorming decisions

> Scope: the decision record and panel of ENG-141 (ENG-234)
>
> Last reviewed: 2026-09-23

A decision records what a team agreed to do: one verb, the content it affects, a
conclusion, and the shared ideas or group synthesis behind it. Acceptance is
explicit. Exploring content, grouping notes, writing synthesis and ending a round
do not create or accept a decision automatically. A session can use decisions
without rounds or a timer, and can remain an exploration without any decisions.

## The object

A decision has exactly one verb: `create`, `change`, `test`, `keep` or
`discard`. It affects zero to five targets. A target is an existing Sheet, Flow or
Scene, pinned by type, ID and creation identity, or a free label and type for
something that does not exist yet and will be created later by a person. The
target's name is frozen in encrypted context; a target that is deleted or
replaced reads as unavailable with that name rather than pointing at newer
content.

The conclusion is required. The reason and the next action are optional; a next
action names what happens next in the editor and may name an editor who owns it.
The owner carries no authority over the decision. The title is derived by the
client from the first sentence of the conclusion until someone edits it; the
server stores whatever title is sent. A decision's round is the newest round
among its sources, recorded when the proposal is written.

## Proposal and agreement

A proposal requires a conclusion, a verb, a responsible participant and at least
one shared source from its own session. An editor selects published ideas or
groups; the server prepares the exact identities and versions available to that
editor. The responsible participant must have current project edit access.
Assigning responsibility does not grant membership or publish private material.
Only the proposal's responsible participant, with current edit access, can
accept it. Project ownership, facilitation and the session's decision-owner
assignment do not grant acceptance authority. An explicit revision can reassign
responsibility only when submitted by the current responsible participant or
the project owner.

When the proposer is also the responsible participant, the proposal can be
registered in one step. Registering writes two consecutive records, a proposal and
its acceptance by the same person; saving as a proposal writes only the first.

Each decision has one current proposal and may also have an agreement in force.
Creating the proposal writes revision 1. Every revision, acceptance, withdrawal or
supersession adds an immutable numbered record with the acting participant,
responsibility, content, sources, targets, timestamp and durable request receipt.
Records that close a proposal or an agreement copy the content they close.

Revising an accepted decision creates a new proposal and keeps the earlier
agreement in force until the revision is accepted. Accepting it moves the
agreement; earlier agreements and their sources remain in history.

## Lifecycle

The persisted statuses are `proposed`, `accepted`, `withdrawn` and `superseded`.
A proposed decision with an agreement in force has a pending revision alongside
it.

- **Withdraw.** The person who wrote the current proposal, or the project owner,
  can withdraw it. Withdrawing a revision keeps the earlier agreement in force and
  the decision stays accepted; withdrawing a proposal without one retires the
  decision as withdrawn. A withdrawn decision cannot be revised or accepted.
- **Supersede.** A proposal may name one decision of the same session that it
  replaces; that decision must have an agreement in force. When the proposal is
  accepted or registered, the replaced decision receives a closing `supersede`
  record that links to its replacement and becomes read-only. If the replaced
  decision is no longer in force at that moment, acceptance fails with
  `replaced_decision_unavailable` and nothing is written.

There is no rejection and no deletion. Retired decisions stay readable with their
history.

## Application

Application is declared per target of the agreement in force: `not_applied`
(the default when nothing has been declared), `partially_applied`, `applied` or
`no_change_needed`, with the declaring editor, a timestamp and an optional
encrypted note. A decision without affected content declares on itself. A
declaration is a statement, not a verification; it never reads or changes the
affected content. The latest declaration per target counts, and the decision
derives how many targets are still to apply.

Declarations are append-only and belong to one agreement. Accepting a revision
starts a new agreement in which every target is not applied again; the earlier
declarations remain in the history. A superseded decision keeps its application
records but accepts no new ones.

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

Current project access governs every query and command. Decisions stay readable
while a round is private, but sources belonging to that round are unavailable:
they cannot be selected for a proposal, and an existing pin on them reads as
inaccessible, so that proposal cannot be saved or accepted until the round is
revealed. Project
ownership, facilitation, decision authority and responsibility do not grant
access to other authors' private notes. Readers can inspect readable decisions;
mutations recheck current edit permission, session lifecycle and the authority
required for that action. Acceptance rechecks the proposal's current responsible
participant, not a cached session role.

## Persistence, concurrency and limits

Ideation owns the Decisions capability and `ideation_decisions`,
`ideation_decision_revisions` and `ideation_decision_applications`. External
callers use `Storyarn.Ideation`; other capabilities supply shared sources and
target names through their own facades. Decisions never edit the original notes,
group synthesis or referenced authoring tools.

Commands use the existing Project access locks, session lock and an optimistic
decision version; declarations check the agreement they were made against
instead. A UUID request identity and content fingerprint make uncertain retries
recognizable. A request cannot acquire a different meaning by reusing its key. A
command that writes several records derives a receipt for each from its key.
Retry responses are subject to current access and do not execute a second
acceptance or revise an agreement already retained in history.

Proposal and revision commands validate the responsible participant and any
next-action owner with `FOR SHARE NOWAIT`. If a concurrent membership change
holds that row, the command returns `responsible_busy` without writing. The
caller can retry after the change completes; eligibility is checked again.

A session permits at most 100 decisions, each with at most 100 records, 1–20
sources and 0–5 targets per revision, and 500 application declarations. Titles
are limited to 160 characters, conclusions and reasons to 4,000, next actions to
500, target labels to 160 and declaration notes to 1,000. Frozen source context
is capped at 256,000 encoded JSON bytes. Reaching a limit produces an explicit
failure; history and provenance are not silently pruned. Events carry
invalidation and identity information rather than creative text.

## Recovery

The sealed Ideation inventory version 10 includes the decision records, every
immutable revision and every application declaration, with their request
receipts. Inventories before version 10 carry decisions of the earlier model and
normalize to empty decision collections. The Project snapshot format and the
outer encrypted compartment format remain unchanged.

Recovery copies encrypted decision text, source and target context and
declaration notes directly from persistence. Sessions, decisions, replacement
links, rounds, source IDs and actor IDs are remapped through their existing
recovery identities; affected content follows the reference-target rules. Revision numbers and recovery UUIDs remain
stable, so the frozen source text needs no ID rewriting. A missing actor becomes
unavailable; no replacement owner or facilitator is credited with the agreement.

Validation replays each history against the lifecycle above, requires the status
and accepted version to follow from it, unique receipts, same-session sources and
actual published idea or retained group revisions, and declarations on targets of
an accepted agreement. Frozen source text must match the cited revision. Closing
records must retain the content they close. Malformed or undecryptable
inventories fail before replacement.

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
external tools. Naming a target never grants access to it, and declaring it
applied never checks it. Those workflows must consume explicit decisions through their
own authorization and provenance contracts when implemented.

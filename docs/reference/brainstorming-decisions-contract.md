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
target's name is frozen in encrypted context, as its type and ID when the name is
empty once stripped of markup; a target that is deleted or
replaced reads as unavailable with that name rather than pointing at newer
content.

The conclusion is required. The reason and the next action are optional; a next
action names what happens next in the editor and may name an editor who owns it.
While a revision waits, the decision shows the next action that revision proposes.
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
  Without a pending revision, the agreement in force is what the next step builds
  on: its responsible person holds the authority again, never the withdrawn
  revision's.
- **Supersede.** A proposal may name one decision of the same session that it
  replaces; that decision must have an agreement in force. When the proposal is
  accepted or registered, the replaced decision receives a closing `supersede`
  record that links to its replacement and becomes read-only. If the replaced
  decision is no longer in force at that moment, acceptance fails with
  `replaced_decision_unavailable` and nothing is written. A revision of the
  replacement may keep naming the decision it already superseded; nothing is
  superseded twice.

There is no rejection and no deletion. Retired decisions stay readable with their
history.

## Application

Application is declared per target of the agreement in force: `not_applied`
(the default when nothing has been declared), `partially_applied`, `applied` or
`no_change_needed`, with the declaring editor, a timestamp and an optional
encrypted note. A decision without affected content declares on itself. A
declaration is a statement, not a verification; it never reads or changes the
affected content. The latest declaration per target counts, and the decision
derives how many targets are still to apply. An editor corrects a declaration by
declaring again, back to `not_applied` if needed; the earlier one stays in the
history.

Declarations are append-only and belong to one agreement. Accepting a revision
starts a new agreement in which every target is not applied again; the earlier
declarations remain in the history. While a revision waits, the agreement in
force still counts as to apply wherever the decision is listed. A superseded decision keeps its application
records but accepts no new ones.

## Tasks

A decision links up to 20 tasks that live in an external tracker at a time. A
link is a web address (`http` or `https`, at most 2,048 characters, never with a
user name or password) and an optional title of up to 160 characters, both
encrypted at rest. Every link is `manual`: Storyarn opens it but never fetches,
reads or updates the task, holds no credentials for it and shows no remote
status. A later provider connection adds its own kind instead of changing manual
links.

Editors of an open session link, edit and unlink tasks on a proposed or accepted
decision; every reader can open them. Each change is a new record with its
actor, time and request receipt, and the latest record per link is the link, so
the decision history shows who linked, edited or unlinked which task. A
withdrawn or superseded decision keeps its tasks but accepts no changes. A
decision holds at most 200 task-link records, and every linked task keeps one in
reserve for its unlink: linking and editing stop earlier, unlinking never does.

"Prepare task" composes plain text for the reader to copy into their tracker:
the agreement in force, or the proposal before one exists, with the conclusion,
reason, affected content, next action and shared sources the reader ticks, and
links back to the decision and to the affected content. The text states where
the decision stands: agreed, agreed with a revision pending, proposed, withdrawn
or superseded by another decision. It uses only what the
reader already sees. The discussion, private notes and drafts never go in, and
nothing is sent anywhere.

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
`ideation_decision_revisions`, `ideation_decision_applications` and
`ideation_decision_task_links`. External
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
sources and 0–5 targets per revision, 500 application declarations, 20 linked
tasks at a time and 200 task-link records. Titles
are limited to 160 characters, conclusions and reasons to 4,000, next actions to
500, target labels to 160 and declaration notes to 1,000. Frozen source context
is capped at 256,000 encoded JSON bytes. Reaching a limit produces an explicit
failure; history and provenance are not silently pruned. Events carry
invalidation and identity information rather than creative text.

## Recovery

The sealed Ideation inventory version 12 includes the decision records, every
immutable revision, every application declaration and every task-link record,
with their request receipts, and the stored place of every moved decision lane
on its round. Version 11 inventories carry no lane places and normalize every
lane to its automatic place. Version 10 inventories carry no task links and
normalize to none. Inventories before version 10 carry decisions of the earlier
model and normalize to empty decision collections. The Project snapshot format and the
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

## On the board

Each round band ends in a lane that holds the decisions whose newest source round
is that band. A decision whose round no longer exists, or never had one, joins the
last band. Cards read left to right in the order of the list, retired decisions
last, and thin connectors rise to each source the reader can still see. The lane
is not a note: it has no in-place editing, colour or shape, and grows its band
like any other content. Selecting a card outlines its sources; double-click or
Enter opens it in the panel, which keeps its sources outlined while it is shown.
Resting the pointer on a note that a decision cites directly shows the compact
cards of those decisions; choosing one opens it.

The lane moves like a group frame: dragging its frame, its label or any of its
cards moves the whole lane, and a press that does not travel still selects the
card. Cards keep their order inside it. A lane that was never moved sits under
the band's lowest note or frame; a moved lane keeps its place, stored on its
round relative to the round header as `{x, y, version}`. The server rejects a
place above the round header (`y < 0`), and the board keeps the lane below the
header; the band still grows around the lane and around any note below it.
Whoever can contribute to the open session may move the lane of a round that is
not private; a private round's lane is not offered for moving. A move never
touches the session revision and every reader of the session sees it. Undo
returns the lane to where it was: to its automatic place, stored as `{version}`
alone, when it had never been moved. Every move, including a return to the
automatic place, bumps the lane's version, and each undo or redo step expects
the version its previous step wrote, so a move by anyone else in between, even
back to the same spot, ends that history. A stale move is rejected with
`stale_decision_lane`, and a retried move that already landed answers with the
lane as it is.

## Discussion

A decision's discussion is an ordinary Brainstorming comment thread anchored to
the decision (`ideation_decision`), shown inline in its detail under the
application. The panel opens the newest thread about the decision, or a composer
that starts one. The thread never takes a canvas position and never appears as a
canvas pin; cards count the messages of its open threads instead. Every project
reader can read it, like the decision itself, for as long as the session and the
decision's recovery identity survive. Resolving the thread never accepts the
decision, and accepting, withdrawing or superseding the decision never resolves
the thread. Mentions, replies and followers notify through the ordinary comment
inbox, and a `?thread=` link opens the panel on the decision.

## From the content

A Sheet, Flow or Scene finds the decisions about it: those whose proposal or
agreement names it in Affects (matched by its pinned identity, never by a
recycled ID) and every decision of the sessions that explore it. Each session is
read through its own catalog, so access and source visibility match the panel.

- **Lightbulb.** The editor's Explorations button counts, in amber, the accepted
  decisions with something still to apply on this content; its label names all
  of them (`2 decisions about Mara · 1 to apply`).
- **Explorations.** After `Linked explorations`, the dialog lists `Decisions
about {name}` with their count: still to apply here, then proposals, then what
  is applied or needs no change. Decisions still to apply here are full cards
  with their session and round inside and, for editors, `Go apply` and `Mark
applied` at the bottom right; the rest are compact rows with the session name.
  Every one opens its session on the decision.
- **Apply banner.** `Go apply` opens the content with `?decision=&session=`; the
  decision sits under the editor header for that visit, anchored to the header
  as a non-modal reka popover. `Mark applied`, `Partially` and `No change
needed` take an optional note; the confirmation offers `Undo` for five seconds,
  which states the previous application again. Nothing is applied automatically,
  and the banner only shows an accepted decision that names this content. Moving
  to other content drops it, and another person's step on any decision of the
  project refreshes the count, the list and the banner of an open editor.
- **Inbox.** Decision writes deliver, inside their transaction: `decision_to_accept`
  to the responsible person of a proposal; `decision_accepted` to its proposer and
  to everyone who started a thread about it; `decision_next_action` to the owner
  of the agreement's next action; `decision_applied` to the responsible person
  and the proposer when a target is marked applied. The actor is never told, and
  the notification stores only the session title, never decision text. Its link
  names the project and the decision; the brainstorming route resolves the
  session after rechecking access. In the inbox each one reads actor · what
  happened · the compact card · one action · time: the card is read when the
  inbox loads, with the reader's current access, and a decision they can no
  longer see leaves only the sentence, and every decision of the inbox is read
  together, one pass per session. `Open` goes to the decision; the next action's
  notification shows what was asked, and its `Go apply` opens the first content
  still to apply with its banner, only while the reader can still declare. An
  application's notification names the content its own declaration marked, never
  whatever is applied now.
  A `decision_to_accept` stays unread when opened and is marked read once the
  decision stops waiting for it: a revision, acceptance or withdrawal settles
  the earlier requests before any new one is delivered.
- **Dashboard.** Each session row summarizes `3 decisions · 1 waiting for you · 1
to apply`; the `Decisions` tab lists every decision with Status and
  Application filters and `Group by affected content`. Its cards carry their
  session and round inside; a decision still to apply offers `Go apply` and
  `Mark applied` for the content of its group, or the first one still pending in
  the plain list, to readers who can declare, through the ordinary decision
  authorization.
- **Palette.** Under `Jump to`, the first matched Sheets, Flows and Scenes bring
  the decisions that name them.

## Boundaries

Decisions do not create Drafts, materialize authoring entities, apply proposals to
Sheets, Flows or Scenes, run AI, or send work to external tools; a task link
only names work tracked elsewhere. Naming a target never grants access to it, and declaring it
applied never checks it. Those workflows must consume explicit decisions through their
own authorization and provenance contracts when implemented.

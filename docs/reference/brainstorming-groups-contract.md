# Brainstorming groups

> Scope: ENG-138
>
> Last reviewed: 2026-09-08

Groups organize contributions spatially and support an authored synthesis of
their sources. They live in the existing brainstorming canvas. This capability
does not produce decisions, generate AI content or introduce a note-history UI.

## Interaction and ownership

A group has a title, optional plain-text synthesis and references to source
ideas. Grouping keeps note positions and contents intact. Moving the frame moves
its active members by the same offset in one transaction. Removing members does
not remove their notes or the synthesis. A group with no remaining members can
keep its synthesis as a standalone canvas object.

Ideation owns the Groups capability. The root facade delegates to its capability
facade. Commands own group writes; queries return authorized projections. Ideas
continues to own note geometry and supplies a transaction-participating movement
port for the atomic group operation. A group does not acquire permission to edit
another author's note text.

## Audience and provenance

Groups use sources already shared with the session. Creating or changing a
group cannot publish a private note or another author's unpublished revision.
Groups are hidden and their writes unavailable while session private mode is
active. Read access follows current project membership; writes additionally
require editing access and an open session. Closing new contributions alone
does not disable organizing existing material.

Membership pins the source's published revision at the time it joins. Group
revision records retain the actor, title, synthesis and source references.
Removing or deleting a source does not erase its internal provenance. Current
canvas projections omit deleted notes and never include private source text.
There is no public API to browse group revision records.

## Concurrency and collaboration

Group writes use optimistic versions and durable UUID request receipts. A retry
must not apply a second movement or recreate a group. Session lifecycle and
current project authorization are checked under the existing lock order.
Group movement checks every member's placement version before updating any
position; a stale member rejects the whole movement.

Invalidations are sent after commit through the existing brainstorming session
topic. UI controls keep their pending state until the acknowledged version is
rendered, including when LiveVue patches props in place. Concurrent edits retain
local text for deliberate recovery instead of overwriting it with a server echo.

The Vite compatibility adapter for LiveVue Hex 1.2.1 keeps injected component
identity stable when the shared layout updates. Without it, a presence/header
refresh remounts the canvas at the same session/epoch and drops selection,
drafts and local undo. The adapter is checked against the upstream source hash,
applies in development, production and Vitest, and must be reviewed or removed
when upgrading LiveVue. It does not modify the installed dependency on disk.

The participant's existing ephemeral canvas history owns undo/redo. An inverse
operation must pass current authorization, group version and member placement
checks. It cannot undo another participant's later modification. Undoing group
deletion checks the matching deletion, and cannot steal sources assigned to a
different group in the meantime.

## Conservation and recovery

Groups, memberships, authored revisions and retry receipts belong to the sealed
project recovery inventory. Capture includes their encrypted content and source
references. Restoration remaps group, idea and actor identities, validates the
graph before committing and retains source publication provenance. Older
inventory versions have no groups and remain readable. See the
[recovery contract](brainstorming-recovery-contract.md).

## Validation

Release checks cover direct canvas grouping and editing, movement and keyboard
undo, a second participant receiving updates, read-only permissions, private
mode, partial visibility, competing writes, uncertain retries, and snapshot
capture/restoration with source identities remapped. Browser coverage uses
LiveVue prop diffing, matching production behavior.

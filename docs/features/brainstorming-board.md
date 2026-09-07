# Brainstorming board

Open **Brainstorming** in the project tool menu. Create a session with only a
title, then add ideas. The default starts privately; optional presets share new
ideas immediately or let each author opt into facilitator-assisted publication.
Rounds, timers, groups, conversations and AI are separate features.

## Writing and sharing

Cards and list view provide the same actions and keyboard controls. Select an
idea to open its panel. Authors can change its title, formatted text and creative
state. Changes save after a short pause; the panel reports saving, saved, errors
and conflicts. Control/Command + Enter saves immediately. A failed save keeps
the input in the mounted board. Retrying an uncertain idea request reuses its
original identity and payload, before sending any later edits.

Private ideas are visible only to their author. Publishing shares an exact
revision. Later edits remain private until the author publishes them again.
The panel states which revision other members see. A member can develop a
visible idea into a separate contribution retaining its source and authorship.
History exposes only revisions the reader is allowed to see.

Active, parked and discarded are creative states, independent of publication.
Moving an idea between them preserves its identity and history. Filters and
search cover the current page of up to 50 authorized ideas; the footer totals
cover all ideas the reader can access. Use pagination for older contributions.

## Working together

Project presence remains in the header. Content-free events refresh authorized
data when another member changes a session or idea. A fallback refresh every
20 seconds also rechecks current access. If two devices edit the same idea, the
losing input is retained. The panel compares it with the saved revision and asks
which content to use; it does not overwrite newer typing with an older response.

Facilitators and owners can review assisted publication. They see a count, not
private text. Discarded ideas are excluded unless explicitly included. Confirming
publishes the prepared revisions; new contributions do not join that selection.
If one selected revision changes, prepare a fresh selection after reviewing it.

## Session lifecycle and recovery

Session details allow the facilitator or owner to edit shared context, change
defaults, assign current project editors and archive/reopen the session. Changes
to defaults do not expand existing publication consent. Archived sessions remain
readable. Replaced sessions are listed separately after a project restore and can
be recovered as archived sessions without changing private-draft ownership.

Only the project owner can permanently delete a replaced session, using an
explicit confirmation. This removes that generation and its descendants;
independent recovery archives retain their copies until separately removed.
No generation is automatically purged by the board.

A restore or reconnection clears bindings to old entity IDs. Unsaved text is
kept separately in the mounted board for deliberate copying, never automatically
applied to restored IDs. Access loss clears private client data. Drafts are not
stored in the browser: leaving the tool or closing its tab discards text that
has not reached the server. Saved revisions and conflicting attempts are durable.

Legacy format-2 snapshots do not contain brainstorming. Restoring them is rejected
while any non-replaced session exists, including archived sessions. A project
with only replaced history can restore one without deleting that history.
Recovery limits roll back the operation and leave existing archives intact.

## Implementation and verification

Both project routes live in the existing `live_session :authenticated_app` and
use the concrete project layout. The LiveView calls public context facades;
Vue receives authorized projections only. Tests cover visibility, explicit
publication, stale configuration, retained conflicts, reconnect epochs,
coalesced invalidations, recovery, navigation and browser editing.

Durable contracts: [sessions](../reference/brainstorming-contract.md),
[ideas](../reference/brainstorming-ideas-contract.md),
[recovery](../reference/brainstorming-recovery-contract.md).

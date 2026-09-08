# Brainstorming canvas

> Last reviewed: 2026-09-08
> Scope: ENG-134 and ENG-136

Brainstorming is a project tool for developing narrative ideas together. Its main
surface is a spatial canvas inside the same ProjectLayout, SidebarFrame and
navigation used by Scenes, Flows and Sheets. Miro, FigJam and Scapple inform the
interaction; this is not a general-purpose whiteboard or a clone of any of them.

## Working on the canvas

Create a session from the sidebar and begin immediately. Double-click empty
space, use the note tool, or press N to create a note and write in place. Double-click
an existing authored note to edit that same note. Notes autosave, can be dragged
freely, colored and connected without imposing a tree. Shift-click toggles notes
in the selection; Command/Ctrl+A selects the visible notes when the canvas has
focus. These canvas shortcuts do not intercept text editing or other input fields.

Space/drag or the hand tool pans. The wheel pans; Ctrl/Command-wheel zooms around
the pointer. The zoom controls and 1 fit the notes. Arrow keys move a selected
note; Shift increases the step. The alternate reading list and scoped search use
only the caller's authorized contributions. Loading more extends the visible
range, and subsequent refreshes reauthorize the entire displayed range.

Command/Ctrl+D duplicates the selection. Command/Ctrl+C, X and V copy, cut and
paste through the native clipboard. Copies retain note content and appearance;
connections within the copied selection are remapped to the new note identities.
They do not copy authorship, publication receipts or publication metadata. New
notes belong to the acting participant and follow the session's current mode.

There is no **Develop this idea** action. Duplicating a note is presented as
duplication; any future development workflow needs a distinct, demonstrated
benefit. There is also no per-note history menu or API for browsing/restoring
historical content revisions.

## Undo and redo

Command/Ctrl+Z undoes the participant's own actions; Command/Ctrl+Shift+Z redoes
them. While editing rich text, the text editor handles its own undo/redo. Canvas
history covers completed text edits, movement, color, creative state, creation
and deletion. Connection undo belongs to ENG-165. Undoing another participant's
work is not supported.

The canvas keeps up to 50 operations in a local, ephemeral stack. It waits for
server acknowledgement before advancing an undo or redo, and the server checks
current permissions and revisions. A new action after undo clears the redo stack.
This interaction history is not a version browser or a permanent recovery log.
Session changes, synchronization resets and recovery epochs clear the local stack
so old actions cannot be replayed against a different board state.

## Facilitation and visibility

The facilitator (or project owner acting in that role) controls **private mode
for the whole session**, from the common header. Participants cannot opt an
individual note in or out. New canvas contributions follow the mode at commit;
shared-mode saves publish their exact revision in the same transaction.

In private mode, each participant sees only their own notes. The facilitator
cannot read other people's private text or previews while it is active.
Ending private mode publishes the saved heads of consenting contributions in the
same session transaction as the mode change. Discarded notes and legacy author-only
drafts are excluded; selecting a discarded contribution for publication is an
explicit action. An overlapping save either precedes that reveal or follows
shared-mode behavior. No round or timer is forced. Archiving ends the private
visibility mask without publishing drafts, leaving prior publications readable.

Authorship is retained. Editing content and marking creative state remain author
operations. Other editors can arrange or connect shared notes and duplicate
readable notes as their own contributions. Read-only members can inspect authorized content
but cannot write.

## Optional rounds

The Rounds control in the existing header lets the facilitator prepare a round
with an optional question, start it, close it and consult previous rounds.
Participants can read that context without managing the session. The canvas
remains the working surface throughout; no round or timer is required to create
notes. Only one round can be active at a time.

The round filter changes which notes are shown, independently of the active
round. It offers all rounds, notes without a round, and each loaded round.
Pagination applies to that view. Creating, duplicating or pasting while viewing
a previous round returns the view to all rounds so the new note remains visible;
new contributions belong to the currently active round, or to no round.

A note keeps the round active when writing began. If its first save arrives
after closing, its footer identifies it as a late contribution to the original
round. Closing does not publish, discard or freeze notes. Editing existing notes
preserves their provenance, and undoing an unsaved deletion restores the original
round. Switching filters retains drafts and local undo state. Existing connections
can relate readable notes across rounds.

The [round contract](../reference/brainstorming-rounds-contract.md) defines
concurrency, authorization and snapshot compatibility.

## Eliminate versus discard

**Delete note** (trash action, Delete or Backspace outside the text editor) removes
the note from all current canvas/list/search/count projections. It does not mark
the note as discarded. Unsubmitted notes are cancelled locally; in-flight creation
is reconciled before deletion. Saved notes retain a deletion marker and their
revision/provenance records solely for recovery. They cannot be edited, connected,
or newly revealed while deleted. Undo can restore the same note only for its
author, against the matching revision and deletion marker; an old undo cannot
restore a later deletion. A snapshot before deletion can recover that earlier
state; a snapshot after deletion preserves the deletion.

**Mark as discarded** is a separate creative-state action. Discarded and parked
ideas remain inspectable through the state filter and can be returned to active.
These states do not change the session's visibility mode.

## Persistence and collaboration

Text revisions use existing idempotent save receipts. Uncertain requests are
replayed unchanged before later typing is saved. Stale conflicting text is kept
for deliberate recovery; equivalent stale saves do not create a UI conflict.
Canvas position/color has its own version, so dragging does not create content
revisions. Connection endpoints are filtered for each reader; hidden/deleted
endpoints never reach another participant's props.

LiveView coalesces invalidations and rereads authorized projections. Committed
membership and ownership changes invalidate access without polling. Cursor
presence uses the authorized board without per-movement queries, is hidden in
private mode and expires locally. Reconnection or returning to a hidden tab
refreshes the board; an idle tab does not repeatedly fetch it. A project
restore or reconnect invalidates pending requests. Unsaved text can be retained
as unbound buffers, never automatically attached to restored or reused IDs.
Losing read access clears those buffers and content. Losing only editing access
preserves readable drafts and stops autosave until editing is allowed again.

Internal content revisions and save receipts remain necessary for current heads,
concurrent saves, pinned publications, retries and compatible recovery capsules.
They are not exposed as a card-history feature. Provenance already stored in older
capsules remains recoverable; no API creates new derived ideas.

The encrypted project recovery inventory includes canvas geometry, connections,
deletions, session mode, rounds and contribution provenance. Restoring remaps
connection and round IDs. Old capsules without canvas/deletion or round fields
remain readable. No image upload, AI generation, timers, grouping or cross-tool
materialization is added here.

## Follow-up product work

- [ENG-163](https://linear.app/sunset/issue/ENG-163/evaluar-recuperacion-de-versiones-anteriores-desde-la-sesion-de) evaluates historical recovery from a secondary session surface, without per-card history controls or replacing undo.
- [ENG-164](https://linear.app/sunset/issue/ENG-164/spike-definir-el-valor-y-la-experiencia-de-desarrollar-una-idea) is a product spike for developing ideas with value beyond duplication; it is not an implementation commitment.
- [ENG-165](https://linear.app/sunset/issue/ENG-165/anadir-atajos-para-conectar-notas-y-crear-notas-conectadas-en-el) covers advanced keyboard connections and creating connected notes.
- [ENG-166](https://linear.app/sunset/issue/ENG-166/permitir-cambiar-la-forma-de-las-notas-del-canvas-de-brainstorming) covers note shapes independently of their content.

## Interaction references

- [Miro private mode](https://help.miro.com/hc/en-us/articles/9794413310482-Private-mode)
- [FigJam sticky notes](https://help.figma.com/hc/en-us/articles/1500004414322-Sticky-notes-in-FigJam)
- [Scapple overview](https://www.literatureandlatte.com/scapple/overview)

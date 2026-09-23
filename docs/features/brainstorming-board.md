# Brainstorming canvas

> Last reviewed: 2026-09-15
> Scope: ENG-134, ENG-136, ENG-137, ENG-138, ENG-165, ENG-166, ENG-182, ENG-191 and the decision-recording slice of ENG-141

Brainstorming is a project tool for developing narrative ideas together. Its main
surface is a spatial canvas inside the same ProjectLayout, SidebarFrame and
navigation used by Scenes, Flows and Sheets. Miro, FigJam and Scapple inform the
interaction; this is not a general-purpose whiteboard or a clone of any of them.

## Record an agreement when the team is ready

**Decisions** opens a panel alongside the exploration. Select shared ideas or use
a group's **Propose a decision** action to start with those sources. A proposal
records a title, conclusion, reason and responsible person. Only members who can
edit the project appear in that assignment picker; the session's decision owner
is the default when still eligible.

Saving leaves a proposal. The responsible person must explicitly select
**Accept decision** to record an agreement. Project ownership or facilitating the
session does not let someone else accept it. An accepted decision can be revised;
the earlier agreement stays current and accessible until its replacement is
accepted. History retains the author, responsible person, text and source
versions for every proposal, revision and acceptance.

Sources preserve the shared version consulted at the time, including when the
author has newer private edits. A changed source is marked; **Update sources**
explicitly adopts its current shared version. Deleted, private or inaccessible
sources have their saved text hidden and must be removed or replaced before a
proposal can be saved or accepted. Recovery carries the agreement, pending
revision and history with the project without binding them to unrelated content.

Ordinary collaboration updates preserve unsaved form text. If another member
changes the proposal, the editor presents that current version before allowing
the writer to continue with their own text. Leaving a changed form requires
confirming that those unsaved changes can be discarded.

Decisions are optional and available in shared sessions, including after idea
contributions close. Archived sessions remain readable. They record agreement and
how far it has been applied; they do not create a Draft or modify production
content. Each round band ends in a lane of its decisions, and each decision
carries its own discussion in the panel.

See the [decision contract](../reference/brainstorming-decisions-contract.md) for
permissions, immutable history, recovery and bounded collection limits.

## Explore changes from existing content

Open **Explore changes** from a Sheet, Flow or Scene to begin a session with that
content as its origin. Review the current overview, choose a session title and
optionally describe the question to explore. The saved context contains the name,
description and relevant overview metadata available to the participant. It does
not copy Sheet fields, Flow nodes or Scene geometry, and the source is unchanged.

The same dialog lists linked explorations so participants can resume a session.
Editors can also search for an existing session and link the source to it. Linking
retains the session's contributions and adds the source as context. Viewers can
inspect and resume readable explorations, but cannot create or link sessions.

The brainstorming board displays its origins with controls to return to the
current content. A changed overview is identified without replacing the context
saved at linking. Deleted or inaccessible content remains an unavailable
reference, with its saved details hidden and its return control disabled. Existing reference
recovery preserves the origin and rebinds it only to the correct restored content
identity.

This entry point opens a brainstorming session. It does not create a Draft,
accept a decision or apply proposals to the source. Those are separate workflows.

## Working on the canvas

Create a session from the sidebar and begin immediately. Double-click empty
space, use the note tool, or press N to create a note and write in place. Double-click
an existing authored note to edit that same note. Notes autosave, can be dragged
freely, colored and connected without imposing a tree. Shift-click toggles notes
in the selection; Command/Ctrl+A selects the visible notes when the canvas has
focus. These canvas shortcuts do not intercept text editing or other input fields.

New notes start as compact text. The selection toolbar's **Note shape** picker
offers plain text, rectangle, ellipse and diamond.
Changing a selection applies the chosen shape to every selected note as one undo
step, preserving the viewport and writing width. Notes size to their text; author
and round details appear outside the outline on hover or selection. Text stays
editable in place and grows within the outline; connections meet
the visible boundary. Shapes carry no prescribed narrative meaning and do not
change the note's content, author, visibility or creative state. Duplicate,
copy/paste, group movement and project recovery retain each note's shape. Existing
notes keep their rectangular appearance until someone changes it.

With the select tool, drag empty canvas to select every visible note touched by
the rectangle, including notes inside groups. Shift adds to the initial selection;
Escape cancels the gesture. Dragging a group's empty interior also selects notes,
while its header still moves the group. Selection does not include unloaded or
hidden notes, and does not change group membership.

Space/drag or the hand tool pans. The wheel pans; Ctrl/Command-wheel zooms around
the pointer. The zoom controls and 1 fit the notes. Arrow keys move a selected
note; Shift increases the step. The alternate reading list and scoped search use
only the caller's authorized contributions. Loading more extends the visible
range, and subsequent refreshes reauthorize the entire displayed range.

Command/Ctrl+D duplicates the selection. Command/Ctrl+C, X and V copy, cut and
paste through the native clipboard. Copies retain note content and appearance;
connections within the copied selection are remapped to the new note identities.
They do not copy authorship, publication receipts or publication metadata. New
notes belong to the acting participant and follow the privacy of their round.

Select two or more notes and press `L` to associate the first selected note with
the others. New relations use a simple line. `Shift+L` removes only the connections
within the current selection. With zero or one selected note, `L` activates the
connection tool, which previews a line to the pointer and highlights valid targets.
Dragging one note onto another also connects them and returns the dragged note to
its original position. Escape cancels the gesture; dragging several notes still
moves the selection.

Click a connection to select it. Its compact toolbar offers a line, an arrow in
either direction, or arrows at both ends. Delete/Backspace removes the selected
connection; ordinary undo/redo restores the relation and its precise arrow style.
Reciprocal legacy relations render as one connection without losing their stored
meaning. Existing relations without style metadata retain their forward arrow.

`Alt/Option+Shift+Arrow` creates a note in that direction, connected from every
selected note, and opens it for writing. The contextual menu offers the same four
directions. The new note and its links save together after writing; cancelling an
empty note saves neither. `Cmd/Ctrl+Enter` while writing still creates an independent
note. Connections meet the visible note outlines, and new notes avoid occupied space.

There is no **Develop this idea** action. Duplicating a note is presented as
duplication; any future development workflow needs a distinct, demonstrated
benefit. There is also no per-note history menu or API for browsing/restoring
historical content revisions.

## Undo and redo

Command/Ctrl+Z undoes the participant's own actions; Command/Ctrl+Shift+Z redoes
them; Ctrl+Y also redoes on Windows/Linux. Undo/redo use shortcuts instead of dock
buttons, with a reminder in the select tool's help. While editing rich text, the text
editor handles its own undo/redo. Canvas
history covers completed text edits, movement, color, creative state, creation
and deletion, plus connecting or disconnecting notes. A selection-wide connection
change is one undo step; creating a connected note is also one step. Rapid undo/redo
shortcuts are processed in order, as in the other project tools. Undoing another participant's
work is not supported.

The canvas keeps up to 50 operations in a local, ephemeral stack. It waits for
server acknowledgement before advancing an undo or redo, and the server checks
current permissions and revisions. A new action after undo clears the redo stack.
This interaction history is not a version browser or a permanent recovery log.
Session changes, synchronization resets and recovery epochs clear the local stack
so old actions cannot be replayed against a different board state.

## Facilitation and visibility

Privacy is a setting of each round. The facilitator (or project owner acting in
that role) chooses it from the settings menu on the header of the round in
progress: **Private round** and **Reveal when time is up**. Both start off for
every new round; nothing is inherited from the previous round or the session.
Participants cannot opt an individual note in or out. New canvas contributions
follow the privacy of their round at commit; saves in a shared round publish
their exact revision in the same transaction.

The header of a private round shows a lock badge beside the question, status and
note count, which counts hidden notes too. Each participant sees their own notes
of that round; everyone else's, the facilitator included, appear as grey
placeholders that keep only position and width, with no text or author. Groups,
comments and decisions cannot use notes of a private round, and cursors are not
shared while the round in progress is private. The timer stays visible.

**Reveal** on the round header publishes the saved heads of the round's
consenting contributions in the same transaction as the change; with **Reveal
when time is up**, the timer does the same when it reaches 0:00. Discarded notes
and legacy author-only drafts are excluded; selecting a discarded contribution
for publication is an explicit action. An overlapping save either precedes that
reveal or follows shared-round behavior. A reveal is irreversible: a revealed
round cannot be made private again, and a closed round can only stop being
private. Archiving ends the visibility mask of every private round without
publishing drafts, leaving prior publications readable.

Authorship is retained. Editing content and marking creative state remain author
operations. Other editors can arrange or connect shared notes and duplicate
readable notes as their own contributions. Read-only members can inspect authorized content
but cannot write.

## Rounds

Every session starts with Round 1; while it is the only round the canvas stays
quiet about it and only shows its question, if any. **New round**, on the header
of the round in progress or in the canvas context menu, closes that round and
opens the next band below the notes in one step; the facilitator writes the
question in place on the new header. **Close round** ends the round without
opening another, for the convergence at the end: anything added afterwards is
marked as a late contribution. Only one round is in progress at a time, and
participants read the headers without managing them.

Rounds are horizontal bands of one canvas, stacked in order and as tall as their
content: a band grows as notes land below its content and pushes the later
rounds down, and a note never rises above its header. Every round is on the
canvas, so there is no round filter; the list view keeps its state filter. The
session tree lists the rounds and the "For later" leaf: `?round=` scrolls to a
band and `?view=later` opens the parked list.

A note keeps the round active when writing began. If its first save arrives
after closing, its footer identifies it as a late contribution to the original
round. Closing does not publish, discard or freeze notes. Editing existing notes
preserves their provenance, and undoing an unsaved deletion restores the original
round. Switching between the canvas and the list retains drafts and local undo state. Existing connections
can relate readable notes across rounds.

A note never moves to another round. **Bring to the active round**, in the context menu
of any readable note of an earlier round and in the For later list, makes a copy
of it in the note's own look under the lowest content of the round in progress,
linked to the original, which stays where it was.

Undo and redo preserve the current view when their notes belong to that view,
including restoring a deleted note. When a target is hidden or outside the loaded
range, the canvas loads all rounds through the previously displayed range before
acting. Failed or interrupted reads preserve the pending undo entry.

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

**For later** and **Mark as discarded** are creative-state actions the author
takes from the note toolbar or the note's context menu; **Bring back** returns a
note to active. Both states stay on the canvas in place: a note kept for later
wears a "For later" tab over its top edge and a dashed outline that follows its
shape, both in the primary colour; a discarded note wears the same tab and
outline in grey and fades behind the others with its text struck through, back
to full strength while it is being edited. The list keeps its state filter; its
For later view lists only parked notes without a copy brought ahead, each with
**Bring to the active round**, and the session tree counts them the same way. These
states do not change the round's privacy.

## Persistence and collaboration

Text revisions use existing idempotent save receipts. Uncertain requests are
replayed unchanged before later typing is saved. Stale conflicting text is kept
for deliberate recovery; equivalent stale saves do not create a UI conflict.
Canvas position/color has its own version, so dragging does not create content
revisions. Connection endpoints are filtered for each reader; hidden/deleted
endpoints never reach another participant's props.

LiveView coalesces invalidations and rereads authorized projections. Committed
membership and ownership changes invalidate access without polling. Cursor
presence uses the authorized board without per-movement queries, is hidden while
the round in progress is private and expires locally. Reconnection or returning to a hidden tab
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
deletions, round privacy, rounds and contribution provenance. Restoring remaps
connection and round IDs. Old capsules without canvas/deletion or round fields
remain readable. Group recovery is described in the
[group contract](../reference/brainstorming-groups-contract.md).

## Follow-up product work

- [ENG-163](https://linear.app/sunset/issue/ENG-163/evaluar-recuperacion-de-versiones-anteriores-desde-la-sesion-de) evaluates historical recovery from a secondary session surface, without per-card history controls or replacing undo.
- [ENG-164](https://linear.app/sunset/issue/ENG-164/spike-definir-el-valor-y-la-experiencia-de-desarrollar-una-idea) is a product spike for developing ideas with value beyond duplication; it is not an implementation commitment.

## Interaction references

- [Miro private mode](https://help.miro.com/hc/en-us/articles/9794413310482-Private-mode)
- [FigJam sticky notes](https://help.figma.com/hc/en-us/articles/1500004414322-Sticky-notes-in-FigJam)
- [Scapple overview](https://www.literatureandlatte.com/scapple/overview)

## Independent countdown

While you scroll inside a band, its header stays pinned on the chrome row,
frosted and without a shadow, and the search and references controls join that
row as plain controls on its left (their own framed panel only shows over bare
canvas), until the next band's header pushes it out; the
header keeps its screen size at any zoom, only its position scales. The canvas
never scrolls above the first header: nothing lives there. The session tree
names each round by its question ("R3 · Which ending…") and by its number until
it has one; "Close round" explains itself on hover.

The header measures its own width and never touches the question: whole, on
one line, at every width. Its two groups share a row while they fit and the
controls drop to a second 40 px row when they do not. From 1000 px down the
status badge goes, "Close round", the timer's stop and the round settings fold
into a "More actions" menu, and "Reveal" and the pause button keep only their
icons; from 800 px down the note count goes and "Private" becomes a lock; from
640 px down "New round" is an icon; below 640 px the question stands alone on
the first row, the round number opens the second, "+1 min" reads "+1" and
"New round" joins the menu. A question wider than its row pans horizontally
under an edge fade. The search and references controls lose their label below
1280 px of canvas and leave the pinned row below 1000 px, returning once no
header sits under them.

The header of the round in progress carries the shared timer. The digits are the input:
the facilitator clicks them, types the minutes and the seconds (two digits each; the
minutes move on to the seconds by themselves), from one second up to 99:59, and
presses play or Enter. Beside a running clock they can pause,
resume, add one minute or cancel; cancelling and starting again resets it at any
moment while the round is in progress. Everyone sees the same countdown, and the
line under the header fills as time passes. Reaching 0:00 is the whole message:
the digits stay at 0:00, muted, and become editable again.

Whether the round is revealed at 0:00 is the round's own setting, not a timer
option. Closing new contributions is a session action offered in the session settings panel;
it preserves edits and undo on existing notes, and a manager can reopen them.
Rounds and timers never control each other automatically. See the
[timer contract](../reference/brainstorming-timer-contract.md).

## Groups and synthesis

Select shared notes and use **Group** to give related contributions a named space
on the canvas. A frame surrounds the notes in their existing positions. Its title
and optional synthesis are editable directly on the canvas. The synthesis has its
own space beside the source notes, so writing it does not obscure their content.
Original notes retain their identity, authorship, round and connections.

Drag the group header to move its notes together. Notes remain individually
selectable and editable under their existing permissions. Membership can change
without rewriting source text. Separating the notes preserves the synthesis as a
standalone canvas object; removing a group never deletes its source notes.

Group actions participate in the participant's local undo/redo. A concurrent
change must not be overwritten by a stale undo or drag. When a state or round
filter, or the loaded range, hides group members, the frame indicates the missing notes and
offers a way to show them before moving the whole group.

Groups organize shared contributions. A group belongs to the round of its notes;
it is hidden while that round is private and cannot reveal unpublished sources. Other editors can organize shared groups and
edit their synthesis; viewers can read them. A synthesis does not accept a
decision or start a new round. Title and synthesis authorship, source references,
and group recovery are covered by the [group contract](../reference/brainstorming-groups-contract.md).

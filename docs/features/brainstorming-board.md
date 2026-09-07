# Brainstorming canvas

> Last reviewed: 2026-09-07
> Scope: ENG-134, replacement for PR #137

Brainstorming is a project tool for developing narrative ideas together. Its main
surface is a spatial canvas inside the same ProjectLayout, SidebarFrame and
navigation used by Scenes, Flows and Sheets. Miro, FigJam and Scapple inform the
interaction; this is not a general-purpose whiteboard or a clone of any of them.

## Working on the canvas

Create a session from the sidebar and begin immediately. Double-click empty
space, use the note tool, or press N to create a note and write in place. Double-click
an existing authored note to edit that same note. Notes autosave, can be dragged
freely, colored and connected without imposing a tree. Developing another
participant's idea creates an authored derivative with its exact source revision.

Space/drag or the hand tool pans. The wheel pans; Ctrl/Command-wheel zooms around
the pointer. The zoom controls and 1 fit the notes. Arrow keys move a selected
note; Shift increases the step. The alternate reading list and scoped search use
only the caller's authorized contributions. Loading more extends the visible
range, and subsequent refreshes reauthorize the entire displayed range.

## Facilitation and visibility

The facilitator (or project owner acting in that role) controls **private mode
for the whole session**, from the common header. Participants cannot opt an
individual note in or out. New canvas contributions follow the mode at commit;
shared-mode saves publish their exact revision in the same transaction.

In private mode, each participant sees only their own notes. The facilitator
cannot read other people's private text, history or previews while it is active.
Ending private mode publishes the saved heads of non-deleted contributions in the
same session transaction as the mode change. An overlapping save either precedes
that reveal or follows shared-mode behavior. No round or timer is forced.

Authorship is retained. Editing content and marking creative state remain author
operations. Other editors can arrange or connect shared notes and develop their
own derivative. Read-only members can inspect authorized content but cannot write.

## Eliminate versus discard

**Delete note** (trash action, Delete or Backspace outside the text editor) removes
the note from all current canvas/list/search/count projections. It does not mark
the note as discarded. Unsubmitted notes are cancelled locally; in-flight creation
is reconciled before deletion. Saved notes retain a deletion marker and their
revision/provenance records solely for recovery. They cannot be edited, connected,
derived or newly revealed after deletion. A snapshot before deletion can recover
that earlier state; a snapshot after deletion preserves the deletion.

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

LiveView coalesces invalidations and rereads authorized projections. Cursor
presence uses the existing collaboration transport and expires locally. A project
restore or reconnect invalidates pending requests. Unsaved text can be retained
as unbound buffers, never automatically attached to restored or reused IDs.
Losing access clears those buffers and content.

The encrypted project recovery inventory includes canvas geometry, connections,
deletions and session mode. Restoring remaps connection IDs after all ideas exist.
Old capsules without canvas/deletion fields remain readable. No image upload,
AI generation, rounds, timers, grouping or cross-tool materialization is added here.

## Interaction references

- [Miro private mode](https://help.miro.com/hc/en-us/articles/9794413310482-Private-mode)
- [FigJam sticky notes](https://help.figma.com/hc/en-us/articles/1500004414322-Sticky-notes-in-FigJam)
- [Scapple overview](https://www.literatureandlatte.com/scapple/overview)

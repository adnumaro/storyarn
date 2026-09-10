# Brainstorming ideas and publication

> Owner: Engineering
>
> Last reviewed: 2026-09-07
>
> Source of truth: `Storyarn.Ideation`, its Ideas capability, and `test/storyarn/ideation/`

ENG-132 and ENG-133 add the internal contribution and publication domain. The
board, autosave UI, local input handling, accessible list and socket presentation
belong to ENG-134. Recovery and private-content release gates from the
[session contract](brainstorming-contract.md) remain in force. This delivery adds
no navigation, route, upload, AI execution or shared export entry point.

## Canvas integration (ENG-134)

The [canvas contract](../features/brainstorming-board.md) supersedes the earlier
proposal of individual publication controls in the UI. `create_canvas_idea`
and `update_canvas_idea` apply the facilitator's current
session mode, with publication atomic with shared-mode saves. `set_private_mode`
is the manager-only operation that hides contributions or ends private work and
reveals the saved heads of consenting, non-discarded contributions. Canvas notes
record facilitator-assisted consent at creation; ending private work never broadens
legacy author-only consent. Discarded notes require an explicit publication selection.
Deleted notes and orphaned authors are also excluded from new session reveals.
Existing explicit-publication ports and stored receipts
remain for compatibility; these ports cannot reveal individual notes during
private mode.

`delete_idea` is distinct from creative state: it preserves internal recovery data and
excludes the note from ordinary authorized reads and writes. `discarded` remains
a recoverable state. Geometry has an independent version and filtered connection
endpoints; it does not create text revisions. Connecting notes preserves the last
placement version and request receipt, so a delayed move can still be retried.
Position writes default omitted width/color to the canvas defaults (280/yellow)
so notes created before canvas placement existed can be moved.

`restore_idea/6` is the bounded inverse of deleting a note, not historical revision
restoration. It accepts an idea identity, revision and deletion marker. It
reauthorizes the original author, checks that exact deletion and restores the same
idea with an incremented revision. It does not accept replacement text or an
arbitrary historical state. Stale revisions or deletion markers are rejected.

The canvas exposes Duplicate and native clipboard operations. They create new
authored notes under the current session mode, copy content and appearance, and
remap connections within the copied selection. They do not clone publication
metadata or represent a new derived-idea workflow. `derive_idea` and
`derive_canvas_idea` are no longer public APIs.

The browser owns an ephemeral, 50-operation undo/redo stack for its own canvas
actions. Undo waits for an acknowledged authorized write before advancing. The
stack is cleared at session/synchronization/recovery resets. Internal revisions
and receipts do not constitute a product history browser: there are no
`list_idea_revisions`, `list_idea_conflicts` or `get_idea_edit` APIs.

## Connection commands (ENG-165)

`update_idea_connections/4` accepts a UUID `request_key`, a `changes` list of
`{source_id, target_id, connected}` maps, and a `versions` list of `{id, version}`
maps for exactly the distinct sources. One request contains 1–100 distinct
directed edges and at most 100 sources. Both endpoints must remain readable,
live notes in the same open session. The entire batch is checked before any
write, and each source keeps its limit of 100 outgoing connections. Unrelated
and private connections are preserved. Duplicate pairs, conflicting operations
for one pair, invalid identities and mismatched version sets are rejected.

Connections have a `links_version` per source, independent of text and placement
versions. A batch advances each changed source once. Its response contains only
the edges actually changed and the acknowledged versions of all sources. The
last request key, actor-bound fingerprint and actual changes are retained per
source in an internal `links_receipt`; a retry returns the same response without
changing links or emitting another invalidation. Reusing that retained key with
different input fails with `idempotency_conflict`. A superseded source fails with
`stale_connections`, including a connect/disconnect/reconnect cycle whose visible
contents happen to match again. Even the compatibility `connect_ideas/6` port
advances this version when it changes a link. No-op requests do not advance a
version or invalidate the board, and their response contains no undoable change.

Browser undo uses the acknowledged versions and reverses only changes the
command actually made. A later link change on the same source prevents that
undo from overwriting another participant's work; movement, text editing and
changes to other sources do not interfere. Receipts are bounded to the most
recent request per source, not a permanent command history. Ordinary idea and
placement projections expose `links_version` but never the receipt.

Canvas creation optionally accepts `connection: {source_ids: [...]}` for 1–100
distinct readable sources. First persistence creates the authored note, its
content and publication, and all incoming connections in one transaction.
Invalid sources or capacity failures leave no orphan note or partial links.
The request fingerprint includes the original connection input. Replaying a
successful creation returns its existing note and never re-adds an edge that a
collaborator subsequently removed. Creating a connected note needs no expected
source link version: its new target identity is appended to the current state
under the contribution lock. Creation replies additionally carry `connected_from`
entries with each source's original `before_version` and acknowledged `version`.
One internal `creation_links_receipt`, bounded by the 100-source limit, preserves
that original acknowledgement on retries. It is absent from ordinary note
projections and has no history API. Undoing the creation uses the existing exact
delete/restore protocol; deleted endpoints disappear from connection projections,
and restored endpoints only reveal connections that still exist.

Snapshots preserve connection state and link versions, remapping endpoints with
the note identities. They exclude the ephemeral `links_receipt` and
`creation_links_receipt`; a restore never
replays an acknowledgement containing pre-restore canvas IDs. Older snapshots
without `links_version` continue with version zero.

## Ownership and locking

Ideas owns idea identities, immutable content revisions, save receipts, retained
conflicts, reveal manifests and publications. Only its commands and execution
workflows write their tables. The root facade delegates through Ideas. Queries
return authorized projections instead of exposing raw schemas to consumers.

Sessions owns current project authorization and its own lifecycle. Its internal
`lock_for_contribution/3` port participates in the Ideas command transaction:
Project/membership authorization locks precede the session lock. This serializes
contributions, settings, archive and delegation within a session; it does not
require a global writer lock. Ideas cannot import Sessions' private modules.

Contribution commands own their outer transaction. Calling one from a caller's
transaction returns `:idea_requires_outer_transaction`; this avoids publishing an
invalidation before a surrounding transaction commits or rolls back.

## Content, authorship and visibility

Cards support an optional title (160 characters) and required bounded rich text
(64,000 input bytes, at most 16 nested formatting levels). Formatting supports
paragraphs, emphasis, lists, blockquotes, code and small headings. Attributes are
removed. Images, embeds and links are not accepted through this content format.
They need explicit audience-aware asset/reference contracts before introduction.

The authenticated actor is the human author. Client fields cannot set author,
AI identity, source, current revision or publication pointers. The stored author
kind reserves AI provenance, but authorized shared AI contributions remain a
later AI integration delivery; this API cannot impersonate AI or another user.

An idea has two distinct revision pointers: its current author head and the last
published revision. An author reads the current head; other participants read the
published revision only when the session permits them to see the note. The SQL
read chooses the authorized revision before decrypting any content. Shared-mode
canvas saves advance publication atomically; private-mode saves do not. Revisions
remain internal records for those pointers and for recovery, without an API for
browsing or restoring historical note content.

Creative state (`active`, `parked`, `discarded`) is independent of publication.
Discarding does not erase content or withdraw a prior publication. Returning an
idea to active is another authored revision. On shared ideas the current creative
state is visible even while the author has unpublished text changes.

New contributions do not have a derivation API or a **Develop this idea** action.
Existing source identities and revisions remain in compatible recovery capsules;
restoration retains and remaps that provenance without granting access to private
source content. Cross-tool links and materialization remain separate work.
[ENG-164](https://linear.app/sunset/issue/ENG-164/spike-definir-el-valor-y-la-experiencia-de-desarrollar-una-idea)
evaluates whether a future development workflow adds value beyond duplication.

## Effective permission matrix

Every permission below additionally requires current project access. Read-only
project members cannot contribute, including when they authored older material.
Direct project roles override inherited workspace roles.

| Operation                                       | Author                        | Other editor | Facilitator / project owner           | Viewer   |
| ----------------------------------------------- | ----------------------------- | ------------ | ------------------------------------- | -------- |
| Read currently visible shared content           | Yes                           | Yes          | Yes                                   | Yes      |
| Read a private current draft                    | Own only                      | No           | No                                    | Own only |
| Create notes or duplicate readable content      | With editing access           | Yes          | Yes                                   | No       |
| Edit text, park, discard or return to active    | Own only, with editing access | No           | No                                    | No       |
| Delete a note or undo its matching deletion     | Own only, with editing access | No           | No                                    | No       |
| Publish an exact own revision                   | With editing access           | No           | Only their own, unless consented      | No       |
| Prepare/reveal others' consenting contributions | No special right              | No           | With editing access and prior consent | No       |

Facilitation and ownership never grant a draft-reading permission. A manager may
receive opaque identities/revision numbers of contributions that authorized
assisted publication, solely to prepare a reveal. Ordinary lists, counts and
current read surfaces still exclude those private drafts. The publication rows
in the matrix describe the retained explicit-publication ports below, not
individual canvas controls.

## Save and retry contract

Creation requires a UUID `request_key` and content. The retained explicit-
publication ports additionally require the `configuration_version` shown to the
contributor and capture publication consent. Canvas creation follows the current
session mode under the contribution lock instead of an individual consent choice.
Updates require the revision read by the author and a new UUID request key.
Atom/string parameter keys are accepted; identity is supplied by authorization.

Every successful create/update stores a durable receipt atomically with its
result. Retrying the same request returns its acknowledged content revision,
with `current_revision` indicating whether newer author edits now exist. Reusing
a key with different input returns `:idempotency_conflict`. A no-op stores its
receipt without inventing a content revision.

A stale valid update stores the losing input in an encrypted conflict receipt
and returns `{:error, {:edit_conflict, receipt}}`. It does not change the head.
The immediate response lets the caller retain the conflicting input for a new
save against the current revision. Receipts remain encrypted internal data for
idempotency and recovery; there is no API for browsing old conflicts or receipts.
Invalid input returns a changeset without a write. ENG-134 retains invalid input
locally and must not apply a late save acknowledgement over a newer local edit.

## Retained explicit-publication ports and frozen manifests

The following rules describe existing domain ports and their stored receipts.
They are not per-card publication controls in the canvas. Canvas contributions
use the session-wide mode described above.

By default a new contribution is private and author-controlled. A session may
default new contributions to shared, but the creator must submit the current
configuration version. Changing the session default never publishes old drafts.
An explicit private choice overrides a shared default.

Assisted publication requires the contributor to explicitly submit
`publication_consent: :facilitator_assisted` against a currently assisted session
configuration. Omitting consent always means author-only, even in that mode.
Consent is retained on the idea; subsequent session changes cannot broaden it.
For these ports, consent covers that idea's subsequent revisions and remains
applicable if its author disconnects or loses project membership.
Physical account deletion makes unpublished contributions ineligible for assisted
publication; it never transfers their authorship to a manager.

`prepare_idea_reveal/5` accepts a UUID request key and either explicit
idea/revision pairs or `:eligible`. The latter is available to the current
facilitator/owner and captures only assisted contributions with unpublished
changes. A manifest contains no text, titles, attachments or private snippets.
One operation supports up to 200 ideas; larger selections fail explicitly.

The operation freezes those pairs in storage. Retrying preparation returns the
same selection and excludes late arrivals. `reveal_ideas/4` reauthorizes the actor
and validates the entire frozen manifest under the session lock before writing
any publication. If a revision changed, it returns `:stale_reveal` and preserves
the prepared operation; preparing again requires a new request key. A replaced
facilitator cannot execute a pending manifest on somebody else's drafts.

Completion records each published revision once and advances public pointers in
the same transaction. Concurrent retries return the same receipt; overlapping
operations never duplicate a publication. An operation belongs to its requesting
actor and cannot be executed by guessing another actor's operation ID. Switching
back to private work never promises to make published information secret again.

## Read surfaces, events and recovery

Idea lists use descending ID cursors with limits of 1–200 (default
50). The default idea list shows active ideas; parked/discarded/all and
private/shared/all are explicit filters. Counts use the same authorized visible
set. Future search and UI props must use these views, not raw entities. They must
not index or render unpublished text from other authors.

`subscribe_ideas/3` authorizes access to the shared session and the caller's private
topic. The only event is `{:ideation_changed, session_id}` after commit. Private
edits and deletion of never-published notes notify only the author topic;
publication and shared creative-state changes
invalidate the shared topic. There are no content-bearing notifications, metrics,
AI requests, search documents or downloads in this delivery. A stale subscriber
can receive an invalidation but must pass current authorization to read data.

Titles, bodies and retained conflicting input are encrypted at rest and redacted
from Ecto inspection. This does not make operators or database/key recovery an
ordinary project-owner permission. Private attachments remain disabled.

Archive preserves ideas, internal revisions and receipts while blocking mutations.
It disables private mode atomically with the archive so prior publications can be
read, but does not publish any new draft. Reopening retains those publication
pointers; discarded and author-only drafts remain private. Project
soft deletion denies access; physical project deletion cascades all these rows.
Loss of access does not erase a draft or reassign it. Physical account deletion
nulls live actor references and preserves published attribution as unavailable;
private drafts remain unreadable through ordinary APIs. No automatic retention,
purge, private export or identity reassignment is introduced.

Canonical snapshots now capture these tables, including private conflict receipts,
through an authenticated compartment. See the [privacy and recovery contract](brainstorming-recovery-contract.md)
for author identity, retained replacement history, ZIP confidentiality and explicit
format-2/template exclusions. This slice covers the currently persisted sessions
and ideas; future entities must explicitly join that recovery contract.

[ENG-163](https://linear.app/sunset/issue/ENG-163/evaluar-recuperacion-de-versiones-anteriores-desde-la-sesion-de)
evaluates whether a secondary session-level recovery experience is useful. It
does not authorize reintroducing a per-note history menu or substitute for
interactive undo/redo.

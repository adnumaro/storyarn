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

An idea has two distinct revision pointers: its current author draft and the
last explicitly published revision. An author reads the current draft; everybody
else reads only the published revision. The SQL read chooses that revision before
decrypting any content. Later edits never silently update the public content.
Published historical revisions remain readable; unpublished history and save
conflicts remain author-only, even after another revision is published.

Creative state (`active`, `parked`, `discarded`) is independent of publication.
Discarding does not erase content or withdraw a prior publication. Restoring an
alternative is another authored revision. On shared ideas the current creative
state is visible even while the author has unpublished text changes.

Developing another person's contribution uses `derive_idea/6`: a new authored
idea retains the exact authorized source idea/revision. It neither overwrites
the source nor grants access to its unpublished revisions. Cross-tool links and
materialization belong to ENG-143 and subsequent deliveries.
Publishing a derivation does not publish its source: readers receive source
identifiers only when that exact source revision has itself been published.
The derivation's author retains the stored provenance.

## Effective permission matrix

Every permission below additionally requires current project access. Read-only
project members cannot contribute, including when they authored older material.
Direct project roles override inherited workspace roles.

| Operation                                                   | Author                        | Other editor | Facilitator / project owner           | Viewer   |
| ----------------------------------------------------------- | ----------------------------- | ------------ | ------------------------------------- | -------- |
| Read shared content and published history                   | Yes                           | Yes          | Yes                                   | Yes      |
| Read a private draft, unpublished history or saved conflict | Own only                      | No           | No                                    | Own only |
| Create or derive from a readable revision                   | With editing access           | Yes          | Yes                                   | No       |
| Edit text, park, discard or restore                         | Own only, with editing access | No           | No                                    | No       |
| Publish an exact own revision                               | With editing access           | No           | Only their own, unless consented      | No       |
| Prepare/reveal others' consenting contributions             | No special right              | No           | With editing access and prior consent | No       |

Facilitation and ownership never grant a draft-reading permission. A manager may
receive opaque identities/revision numbers of contributions that authorized
assisted publication, solely to prepare a reveal. Ordinary lists, counts and
history still exclude those private drafts.

## Save and retry contract

Creation requires a UUID `request_key`, the `configuration_version` shown to the
contributor, and content. It captures the contribution's publication consent.
Updates require the revision read by the author and a new UUID request key.
Atom/string parameter keys are accepted; identity is supplied by authorization.

Every successful create/update stores a durable receipt atomically with its
result. Retrying the same request returns its acknowledged content revision,
with `current_revision` indicating whether newer author edits now exist. Reusing
a key with different input returns `:idempotency_conflict`. A no-op stores its
receipt without inventing a content revision.

A stale valid update stores the losing input in an encrypted conflict receipt
and returns `{:error, {:edit_conflict, receipt}}`. It does not change the head.
`get_idea_edit/5` and `list_idea_conflicts/5` let the author recover that input after
reconnecting. Applying a chosen alternative is a new save against the currently
read revision; original alternatives and history remain intact. Invalid input
returns a changeset without a write. ENG-134 must retain invalid input locally
and must not apply a late save acknowledgement over a newer local edit.

## Explicit publication and frozen manifests

By default a new contribution is private and author-controlled. A session may
default new contributions to shared, but the creator must submit the current
configuration version. Changing the session default never publishes old drafts.
An explicit private choice overrides a shared default.

Assisted publication requires the contributor to explicitly submit
`publication_consent: :facilitator_assisted` against a currently assisted session
configuration. Omitting consent always means author-only, even in that mode.
Consent is retained on the idea; subsequent session changes cannot broaden it.
The UI must explain that this consent covers that idea's subsequent revisions
and remains applicable if its author disconnects or loses project membership.
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

Lists/history/conflicts use descending ID cursors with limits of 1–200 (default
50). The default idea list shows active ideas; parked/discarded/all and
private/shared/all are explicit filters. Counts use the same authorized visible
set. Future search and UI props must use these views, not raw entities. They must
not index or render unpublished text from other authors.

`subscribe_ideas/3` authorizes access to the shared session and the caller's private
topic. The only event is `{:ideation_changed, session_id}` after commit. Private
edits notify the author topic; publication and shared creative-state changes
invalidate the shared topic. There are no content-bearing notifications, metrics,
AI requests, search documents or downloads in this delivery. A stale subscriber
can receive an invalidation but must pass current authorization to read data.

Titles, bodies and retained conflicting input are encrypted at rest and redacted
from Ecto inspection. This does not make operators or database/key recovery an
ordinary project-owner permission. Private attachments remain disabled.

Archive preserves ideas, history and receipts while blocking mutations. Project
soft deletion denies access; physical project deletion cascades all these rows.
Loss of access does not erase a draft or reassign it. Physical account deletion
nulls live actor references and preserves published attribution as unavailable;
private drafts remain unreadable through ordinary APIs. No automatic retention,
purge, private export or identity reassignment is introduced.

Project snapshots do not yet include these tables. ENG-147 must integrate and
test recovery, including encrypted bytes, keys and identity mapping, before the
board accepts real user content. ENG-129 must close the remaining shared-download,
transfer and private-attachment policies. Exclusion is explicit; this foundation
does not claim complete brainstorming backup support.

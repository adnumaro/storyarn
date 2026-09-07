# Brainstorming privacy and recovery

> Owner: Engineering
>
> Last reviewed: 2026-09-07
>
> Scope: ENG-129 and the sessions/ideas slice of ENG-147

## Ownership and permissions

Ideation owns sessions, configuration, responsibilities, ideas, revisions,
publication consent, reveal operations and conflicting input. Projects owns
project identity, effective access, transfer, snapshots and their storage
lifecycle. Accounts owns account identity; its server-generated recovery UUID
is immutable through registration and profile forms and is not exposed in Vue
user props. Platform provides the existing encryption mechanism. Commercial
continues to account for snapshot bytes through the existing object manifest.

Every ordinary read first checks current project access. Every ordinary mutation
rechecks edit permission under the existing Project/membership locks, followed
by the session lock. Session responsibility is not membership and never grants
access to a project. Direct membership precedence and inherited access remain
Project policy.

| Operation                                                       | Author with current access       | Other participant              | Facilitator                                         | Project owner                                   |
| --------------------------------------------------------------- | -------------------------------- | ------------------------------ | --------------------------------------------------- | ----------------------------------------------- |
| Read session metadata and published ideas                       | Yes                              | Yes, including viewers         | Yes                                                 | Yes                                             |
| Read a private draft, unpublished revision or conflicting input | Own only                         | No                             | Own only                                            | Own only                                        |
| Create/edit an idea                                             | Edit permission; own ideas       | Own ideas with edit permission | Own ideas                                           | Own ideas                                       |
| Publish a revision                                              | Own revision                     | No                             | Exact eligible manifest with prior assisted consent | Same rule as facilitator, no extra draft access |
| Change creative state                                           | Own idea with edit permission    | No                             | Own only                                            | Own only                                        |
| Configure/archive/reopen a session                              | Only when also facilitator/owner | No                             | With edit permission                                | Yes                                             |
| Recover a replaced session                                      | Only when also facilitator/owner | No                             | With edit permission                                | Yes                                             |
| Group, decide, invoke shared AI, attach private files           | Not implemented                  | Not implemented                | Not implemented                                     | Not implemented                                 |

All managerial actions remain subject to current project edit permission. The
owner can recover or delete project data through Project lifecycle operations;
that does not permit reading another author's private content. Decision-owner
assignment reserves a responsibility; decision commands are not implemented in
this slice.

Publication is separate from creative state. An assisted-consent discarded idea
can be explicitly selected for publication. The board must not preselect such
ideas in a bulk reveal. Consent is captured against the exact configuration
version seen by the author; later settings cannot broaden it. Preparing a reveal
freezes IDs and revisions, without disclosing draft bodies to the facilitator.

## Snapshot coverage

Canonical `project.json` format **3** requires an `ideation` compartment. The
existing manifest framing and persisted snapshot/archive protocol versions do
not change. The compartment is version **1**, containing an authenticated,
encrypted JSON inventory with its own `storyarn.ideation` format identifier.
The inventory covers:

- Open, archived and previously replaced sessions, their independent
  configuration, responsibilities and complete session revision history.
- Every idea, current creative state, authorship, publication consent,
  configuration version, source idea/revision and immutable creation-request
  source identity.
- All authored revisions and successful/conflicting edit receipts.
- Prepared/completed reveal operations, exact selections/manifests, and the
  immutable publication ledger.

Ciphertext for title/body/conflicting input is copied from persistence; it is
not loaded through the ordinary decrypted-content schema. The whole inventory,
including actor bindings, is additionally encrypted and authenticated. Encrypting
only draft bodies would leave authorship metadata forgeable by an archive holder.
Neither ZIP JSON nor its manifest exposes private text or user-email mappings.
Compartment size can reveal aggregate volume; downloads do not claim to hide
that side channel.

The compartment lives in the captured project object, so the existing canonical
archive owns its exact bytes independently of current Ideation rows. ZIP is the
download/recovery representation, not an additional source of truth. The
Project capture transaction holds its exclusive Project lock; ordinary Ideation
writes participate in that boundary through Project authorization locks.

Capture reads in pages of 100 rows, with a total limit of 100,000 rows and 48 MiB
of compartment JSON. Exceeding a limit fails capture; it never silently omits
history. The existing outer project/archive limits still apply. An Ideation-owned
`ideation_recovery_captures` cache reuses ciphertext for identical canonical
inventories under the same Project lock. This preserves exact project-checksum
comparisons with randomized authenticated encryption. The cache is derived,
excluded from snapshots and unnecessary for restoring a downloaded archive.

Recovery validates the compartment version, authentication and availability of
keys for the retained encrypted content. Invalid ciphertext or unavailable keys
fail before a restore can commit. Production key custody and retaining old Vault
keys across rotation remain operational recovery requirements: **the ZIP does
not contain encryption keys** and cannot decrypt private content by itself.
Copying a ZIP to an unrelated installation does not create access to its drafts.

## Identity, restore and lifecycle

Projects calls the sealed Ideation recovery ports from its existing authorized
reconstitution transaction. The architecture ratchet restricts these ports to
exact Project capture, validation, materialization and verification callers;
ordinary Web code cannot use them as a draft-reading API.

Restore creates fresh session, idea, revision, receipt, reveal and publication
IDs. Typed foreign keys, source links, reveal selections/manifests and historical
responsibility assignments are remapped explicitly. Authored integers and text
are not rewritten. Creation receipts retain their original source identity so
retrying a derivation with its remapped source still recognizes the request.
Successful/conflicting saves remain replayable.

Captured actor IDs resolve only through authenticated account recovery UUIDs.
There is no fallback to numeric ID, email, project owner, facilitator or a
caller-supplied identity map. Renaming an account email preserves its identity;
recreating an account, even with a reused numeric ID, does not. Missing identities
become `nil`, matching live foreign-key deletion behavior. Private revisions stay
stored but inaccessible through ordinary APIs. A destination member must still be
the original author to read a draft; transferring/importing a project never
restores memberships or grants the original author new access.

Assisted publication consent is scoped to the source project captured inside the
authenticated inventory. Restoring that same project preserves it. Importing into
a different project normalizes delegation to `author_only`: the destination owner
must not gain a way to reveal/read an incoming private draft. The original author
can still publish explicitly after gaining current project access. Prepared
manager reveals do not bypass this normalization; their execution rechecks policy.
Original delegation remains recorded in the source archive; this delivery does not
add a consent-editing UI or automatically obtain renewed delegation.

Available actors are locked with `FOR KEY SHARE SKIP LOCKED`; a busy surviving
actor causes a retryable failure instead of waiting after restore/storage locks
or silently treating them as deleted. Reconstitution only writes captured state:
it does not invoke publication commands, restart timers, run AI, send messages or
resume external work. Restored prepared reveals still require an explicit new
execution against current session authority and the frozen revisions.

Replacing a project marks previous live sessions as replaced, retaining their
rows and all descendants. Ordinary reads/writes can no longer reach those session
IDs. `list_sessions(..., status: :replaced)` exposes session metadata under current
project access. `recover_session/4` requires the owner or current facilitator and
the read revision; it restores an **archived** session, without publishing content
or opening contribution automatically. The board's recovery presentation belongs
to ENG-134. Repeated restores retain additional generations; capture bounds apply
to that complete history. No automatic purge is introduced.

Project soft deletion or access revocation denies ordinary reads. Physical project
or workspace deletion follows existing cascades, including the derived capture
cache. Snapshot bytes have their own existing retention/deletion lifecycle; a
retained downloaded archive is not erased by deleting live records. Physical
account deletion leaves authors unavailable and drafts closed. Parking/discarding
an idea is a creative state, distinct from session archive, replacement or project
trash, and never triggers byte deletion.

## Compatibility and deliberate exclusions

Format-2 archives remain readable. They contain no Ideation compartment and cannot
restore brainstorming. Exact restore into a project that already contains
sessions rejects such an archive, preserving all current data instead of silently
ignoring/replacing its brainstorming state. A format-3 archive missing its
compartment, or format 2 with an unexpected compartment, is rejected.

Portable templates stay on format 2 and exclude Ideation. The template installer
rejects an Ideation compartment outside the exact snapshot-import path. Runtime
exports (Yarn/Ink and the existing tool-oriented exports) do not export
brainstorming. They are not whole-project backups.

No private attachments, shared AI outputs, rounds, groups, decisions,
brainstorming conversations, cross-tool references or external credentials exist
in this persisted slice. Their tickets must extend this contract and its
restoration tests before admitting those data. ENG-147 remains open for that
future coverage; this delivery does not claim those features or complete V1.

Private content is excluded from global search, analytics, notification payloads,
shared AI context and content-bearing broadcast events. Current events carry only
an invalidation/session ID and never authorize a subsequent read. Future private
attachments must use an author-scoped asset authorization/storage contract;
ordinary shared Project Assets are not a private-draft attachment store. Future
conversations and references must resolve the containing idea's audience before
reading a target, notifying, indexing or handing content to AI. A copied external
URL never restores an external authorization.

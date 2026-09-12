# Brainstorming privacy and recovery

> Owner: Engineering
>
> Last reviewed: 2026-09-12
>
> Scope: ENG-129, ENG-136, ENG-137, ENG-138, ENG-143 and the sessions/ideas/groups/references slice of ENG-147

## Ownership and permissions

Ideation owns sessions, configuration, responsibilities, ideas, revisions,
publication consent, reveal operations, conflicting input, groups and synthesis provenance. Projects owns
project identity, effective access, transfer, snapshots and their storage
lifecycle. Accounts owns account identity; its server-generated recovery UUID
is immutable through registration and profile forms and is not exposed in Vue
user props. Capture and nonblocking resolution of those identities enter through
the Accounts facade; Ideation does not query or lock Accounts tables directly. Platform provides the existing encryption mechanism. Commercial
continues to account for snapshot bytes through the existing object manifest.

Every ordinary read first checks current project access. Every ordinary mutation
rechecks edit permission under the existing Project/membership locks, followed
by the session lock. Session responsibility is not membership and never grants
access to a project. Direct membership precedence and inherited access remain
Project policy.

| Operation                                                       | Author with current access       | Other participant                | Facilitator                                         | Project owner                                   |
| --------------------------------------------------------------- | -------------------------------- | -------------------------------- | --------------------------------------------------- | ----------------------------------------------- |
| Read session metadata and published ideas                       | Yes                              | Yes, including viewers           | Yes                                                 | Yes                                             |
| Read a private draft, unpublished revision or conflicting input | Own only                         | No                               | Own only                                            | Own only                                        |
| Create/edit an idea                                             | Edit permission; own ideas       | Own ideas with edit permission   | Own ideas                                           | Own ideas                                       |
| Publish a revision                                              | Own revision                     | No                               | Exact eligible manifest with prior assisted consent | Same rule as facilitator, no extra draft access |
| Change creative state                                           | Own idea with edit permission    | No                               | Own only                                            | Own only                                        |
| Configure/archive/reopen a session                              | Only when also facilitator/owner | No                               | With edit permission                                | Yes                                             |
| Recover a replaced session                                      | Only when also facilitator/owner | No                               | With edit permission                                | Yes                                             |
| Permanently purge a replaced session                            | Only when also owner             | No                               | Only when also owner                                | Explicit action with current edit permission    |
| Read groups and synthesis                                       | Shared mode and current access   | Shared mode and current access   | Same rule                                           | Same rule                                       |
| Group published ideas and edit synthesis                        | Current edit access; shared mode | Current edit access; shared mode | Same rule                                           | Same rule                                       |
| Decide, invoke shared AI, attach private files                  | Not implemented                  | Not implemented                  | Not implemented                                     | Not implemented                                 |

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
The inner inventory is version **5**. Version **4** inventories normalize to no
content references or reference revisions. Version **3** inventories also normalize to no
groups, memberships or group revisions. Version **2** inventories also normalize to no
timer and open contributions. Version **1** additionally normalizes to no rounds
and unassigned, non-late contributions.
The inventory covers:

- Open, archived and previously replaced sessions, their independent
  configuration, responsibilities and complete session revision history.
- Planned, active, closed and cancelled rounds, their prompts and lifecycle timestamps.
- Shared timer state, remaining duration, deadline, actor, expiry options and
  outcome, plus the session contribution gate.
- Every idea, current creative state, authorship, publication consent,
  configuration version, source idea/revision and immutable creation-request
  source identity, immutable round membership and late-contribution flag.
- Note placement and canvas connections, including their independent link
  versions, optional plain/rectangle/ellipse/diamond shape and per-edge direction
  (`none`, `forward`, `backward`, `both`). Older inventories without shape retain
  the rectangular default; missing legacy direction metadata retains forward
  arrows. Endpoints and direction-map keys are remapped during restoration.
  Direction keys must name an actual outgoing endpoint of that source. The bounded
  `links_receipt` and `creation_links_receipt` acknowledgements are excluded from capture and stripped on
  restore because its request refers to the previous canvas identities. Missing
  link versions in older inventories mean version zero.
- All authored revisions and successful/conflicting edit receipts.
- Prepared/completed reveal operations, exact selections/manifests, and the
  immutable publication ledger.
- Groups, encrypted titles and synthesis, canvas placement, deletion markers,
  complete membership history and the published source revision pinned by each
  membership. Immutable group revisions retain their source map, actor, state and
  durable request receipt.
- Session and idea references to existing content, their exact destination
  identity, relationship, removal marker and frozen overview context. Immutable
  create/refresh/remove revisions preserve actor and idempotent request receipts.
  Reference context is shared overview metadata, not a graph snapshot or a draft.

Ciphertext for title/body/conflicting input and group title/synthesis is copied from persistence; it is
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

Recovery validates the compartment version, authentication, record identities,
internal references and availability of keys for the retained encrypted content. Invalid ciphertext or unavailable keys
fail before a restore can commit. Production key custody and retaining old Vault
keys across rotation remain operational recovery requirements: **the ZIP does
not contain encryption keys** and cannot decrypt private content by itself.
Copying a ZIP to an unrelated installation does not create access to its drafts.

## Identity, restore and lifecycle

Projects calls the sealed Ideation recovery ports from its existing authorized
reconstitution transaction. The architecture ratchet restricts these ports to
exact Project capture, validation, materialization and verification callers;
ordinary Web code cannot use them as a draft-reading API.

Each persisted session, round, timer, idea, group, membership, revision, receipt, reveal and publication carries
an immutable recovery UUID. Restore compares complete session generations using
those identities and content, independent of database IDs and replacement time.
An identical generation already present in the destination is reused; a distinct
generation receives fresh database IDs. Typed foreign keys, source links, reveal
selections/manifests and historical responsibility assignments are remapped explicitly. Authored integers and text
are not rewritten. Creation receipts retain their original source identity so
retrying a derivation with its remapped source still recognizes the request.
Successful/conflicting saves remain replayable.

Groups are inserted after ideas and their publication ledger, followed by their
memberships and revisions. Group references, membership idea IDs, revision idea
lists and source-map keys are remapped while source revision numbers remain
unchanged. A group's entire membership history and all revision receipts
participate in generation matching, so repeated recovery reuses the same
complete generation.

References are inserted after their session and optional idea, followed by their
immutable context revisions. All internal IDs and actors are remapped. Current
context must match the latest contiguous revision; malformed contexts, receipt
collisions, cross-session idea links and impossible removal states are rejected
before replacement. Removed references and formerly shared idea references remain
in recovery history; ordinary reads still check current source and target access.

Exact Project materialization supplies proven Sheet, Flow, Scene and Asset ID
receipts and the destination creation identity. Only those mappings can rebind a
content reference. An absent mapping leaves `target_id` empty and retains historical
context without a live destination; it never searches by name, shortcut or content.
Direct recovery within the same project, without replacing its content, preserves
the original destination identity. Direct cross-project recovery without mappings
detaches every target. Historic overview fields are never rewritten or refreshed.

Before sealing, capture also verifies the original destination generation through
a transaction-only Project identity port, in bounded batches. A missing row or
creation-identity mismatch normalizes only `target_id` to empty; the original
identity and every context revision remain intact. This prevents an already
unavailable reference from being rebound merely because a materialization map
contains its old numeric ID. Matching soft-deleted rows retain their identity for
undo. Reusing a session generation persists any normalized detached destinations.

Canonical localization snapshots currently omit translation row IDs, so exact
materialization cannot prove an old-to-new translation-row mapping. Localization
references therefore restore as unavailable, with their context history retained.
Matching a localization source tuple would risk attaching to a different row
generation and is intentionally not used as an identity substitute.

No comments, notifications or personal follow/read state are copied into the
reference inventory. Reconstitution neither publishes a conversation nor grants
new access to retained context.

Validation requires every group source to belong to the same session and point
to an existing published revision. Historical revision sources must also have
matching retained membership provenance. It rejects private or unpublished
sources, duplicate active memberships, malformed receipts and invalid group
versions before replacing any session. A published source later deleted remains
recoverable as a tombstone with its original publication and provenance; recovery
never republishes it. Ordinary group queries still enforce current project access
and hide groups before decryption when the restored session is private. Restoring
encrypted synthesis grants no additional draft access.

Rounds are inserted before ideas, and idea-to-round references are remapped
within the restored session. Validation rejects cross-session round references,
multiple active rounds, invalid lifecycle timestamps and impossible late-note
flags before any replacement. Round actions in session revisions carry the
stable round number and its metadata, not database IDs. Restoring an active
round restores that state without starting a timer or revealing any contribution.

Running timers restore paused with a new version and no deadline, retaining the
last persisted remaining duration. Restoring cannot trigger an old timer job or
automatically reveal notes. Explicit resume rechecks current authority and
configuration. Capture remains independent of elapsed wall-clock time, preserving
stable canonical digests. See the [timer contract](brainstorming-timer-contract.md).

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

Replacing a project marks superseded live generations as replaced, retaining
their rows and descendants. Ordinary reads/writes can no longer reach those IDs
unless an identical generation is reused as part of the restored state. `list_sessions(..., status: :replaced)` exposes session metadata under current
project access. `recover_session/4` requires the owner or current facilitator and
the read revision; it restores an **archived** session, without publishing content
or opening contribution automatically. The board's recovery presentation belongs
to ENG-134. The retention policy is **keep distinct generations until explicit
owner deletion**, including archived sessions and complete private history.
Repeated restores of the same content reuse generations; capturing and restoring
that history does not recursively multiply it. Before committing, restore checks
that the complete resulting inventory still fits the snapshot bounds, so restoring
cannot leave a previously capturable project over the limit. Exceeding a limit
rolls back with `ideation_recovery_too_large`, including in the canonical builder;
background builds record that specific failure without pointless retries.

`purge_replaced_session/4` is a permanent, explicit owner action against one
replaced session and its current revision. It rejects live/archived sessions,
non-owners and stale revisions; no restore or scheduled job invokes it. Its
session-owned descendants are deleted through foreign-key cascades. Independent
retained archives keep their captured generations and can recover a purged one.
There is no automatic age-based deletion or silent exclusion from snapshots.
The board must explain the destructive action and require explicit confirmation.
The 100,000-row/48-MiB bounds are safety limits, not measured throughput claims;
bulk insertion remains a separate performance improvement.

Project soft deletion or access revocation denies ordinary reads. Physical project
or workspace deletion follows existing cascades, including the derived capture
cache. Snapshot bytes have their own existing retention/deletion lifecycle; a
retained downloaded archive is not erased by deleting live records. Physical
account deletion leaves authors unavailable and drafts closed. Parking/discarding
an idea is a creative state, distinct from session archive, replacement or project
trash, and never triggers byte deletion.

## Compatibility and deliberate exclusions

Format-2 archives remain readable. They contain no Ideation compartment and cannot
restore brainstorming. Exact restore into a project containing a non-replaced session (open or archived)
rejects such an archive, preserving current content. When only replaced sessions
remain, format 2 is accepted and that retained history is preserved. Users do not
have to purge it merely to recover an older project snapshot. A format-3 archive missing its
compartment, or format 2 with an unexpected compartment, is rejected.

Portable templates stay on format 2 and exclude Ideation. The template installer
rejects an Ideation compartment outside the exact snapshot-import path. Runtime
exports (Yarn/Ink and the existing tool-oriented exports) do not export
brainstorming. They are not whole-project backups.

No private attachments, shared AI outputs, decisions,
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

## Migration

Accounts owns its recovery-identity migration. It adds the nullable column before
setting its UUID default and backfilling existing rows, then enforces non-null
identities and uniqueness. This avoids the full table rewrite caused by adding a
volatile default with the column. The migration remains transactional and still
requires DDL locks and a backfill; it is not a zero-downtime migration for an
unbounded production table. Ideation record identities use the same staged
column/backfill pattern in a separate migration.

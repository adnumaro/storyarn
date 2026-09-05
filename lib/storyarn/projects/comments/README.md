# Contextual project comments

Comments are a Projects-owned capability because their access and durable
lifecycle belong to one project, independently of the editor that displays them.
Supported anchors are `flow_node`, `flow_canvas` and `scene_canvas`. Adding another editor
adds an explicit source contract and resolver; it does not create another message model. Public
callers enter through `Storyarn.Projects`. The realtime collaboration module in
Platform remains technical coordination; it does not own these conversations.

## Model and permissions

- A thread records source identity, author, open/resolved state, revision and
  message count. Multiple threads can discuss the same node, Flow canvas or Scene canvas.
- Messages are immutable plain text, limited to 10,000 characters. Replies
  explicitly identify a parent message in the same thread. V1 does not edit or
  redact messages and does not introduce anonymous or AI authors.
- Mentions are explicit member IDs rather than names parsed from text. Candidates
  include direct project members and workspace members with inherited access.
- Owners and editors may create, reply, resolve, reopen and move pins; viewers may read.
  Every public operation reauthorizes effective membership, with direct project
  membership taking precedence over an inherited workspace role. Mutations lock
  the project and effective membership through the existing Access capability.
- Resolved threads must be reopened before replying. Source-unavailable threads
  remain readable but do not accept replies or state changes.
- Resolve/reopen and pin moves compare the expected revision after locking the thread. Replies
  advance that revision, so a stale resolve cannot silently close a newer reply.

## Source identity and recovery

The immutable source type, ID, containing Flow or Scene ID, creation time and label preserve
the original context. A separate nullable `flow_node_id` reference uses **ON DELETE
SET NULL**; canvas threads use the equivalent `flow_canvas_id` or `scene_canvas_id`
reference to their owning Flow or Scene.
Deleting a source never cascades into review history. If a deleted ID is
later reused, the null pointer prevents automatic rebinding, even when text,
coordinates or creation timestamps match. Source projections are read-only and
do not grant Comments permission to write Flow content.

The database requires each non-null anchor reference to equal its immutable
source ID. The follow-up identity migration validates existing rows and rejects
inconsistent data without repairing or deleting conversations. Null references
remain valid after a source is hard-deleted.

Soft deletion makes a source unavailable. Restoring the same existing node, Flow or Scene makes
it available again. Hard deletion, replacement import or snapshot reconstitution
that creates new rows does not attach old discussions to the replacement. A Flow
version restore preserving the same row identity retains its discussion. Source
absence does not mean a thread was resolved or deleted.

Review history is not authored runtime content. V1 deliberately omits threads,
messages and mentions from Flow/Scene/entity versions, canonical project snapshot
payloads, template publication and project interchange. Restoring or importing
content preserves current project conversations attached to their original
identities; it never rewinds discussions or guesses new anchors. A newly imported
project does not receive another project's review history. Existing database
backups retain the review tables; downloadable content snapshots do not promise
to recover them. Hard project deletion cascades the project's review tables.
User deletion anonymizes authors; the body and conversation remain project data.

## Spatial positions

The thread DTO exposes `position: %{x: number, y: number}` or `nil`. Node positions
are offsets relative to the node origin, so moving a node moves its pins without
rewriting the discussions. Canvas positions are absolute Flow canvas coordinates.
Both Flow coordinates must be finite numbers between -10,000,000 and 10,000,000.
Scene canvas positions are percentages of the stable logical Scene bounds; both coordinates
are required and remain between 0 and 100 so viewport resizing, pan and zoom do not move them.
Existing node threads keep `nil` positions for the editor's default placement;
new canvas threads require a position. Moving a pin changes its position and
revision, never its source identity, messages, author or discussion activity time.

The spatial-anchor migration is explicitly irreversible: removing its columns or
canvas source type would lose persisted anchors and pin positions. Schema changes
must roll forward while preserving the conversation history.

Each editor's pin-list API filters its source family before matching the container ID. This is
load-bearing because Flow and Scene IDs come from independent sequences and may be equal.
The pin-list API returns every available open thread without a pagination cutoff;
root messages, authors and source availability are fetched in batches. The ordinary
discussion list remains paginated. Node filters and node badge counts exclude canvas
threads. Canvas notification destinations have `node_id: nil`.

## Transactions, delivery and pagination

Each create/reply requires a client request ID (1–64 bytes). The key is scoped to
project and actor across create and reply operations. An advisory transaction lock
serializes retries; the stored request fingerprint rejects reuse for different
content, destination, parent, mentions or create position. Creates without a node
position preserve the original fingerprint for compatibility with existing retries.
Identical retries return the original
thread without another message, count increment, notification or signal.

Source validation, message/mention persistence, thread update and notification
delivery are atomic. A notification failure rolls back the comment. Only after
commit does the capability publish notification invalidation and
`{:flow_comments_changed, flow_id}` or `{:scene_comments_changed, scene_id}` on a
source-specific project topic. Signals contain no
message text. Subscribers must refetch through the authorized facade. Mutation
entrypoints reject an outer Ecto transaction, preventing premature publication.

Thread pages are newest-first using a descending ID cursor. A detail contains the
newest message page in chronological order; its cursor loads older messages.
The first page also includes the root message if it would otherwise be absent,
and each thread exposes its root message ID for explicit generic replies. Limits
default to 30 and cap at 100, plus that optional root. DTOs contain plain maps with ISO8601 dates,
authors, mentioned members, preview and source availability; they never expose
request fingerprints or internal persistence schemas.

Reply notifications target only the author of the explicit parent message and
the mentioned members. Mention wins if both apply; self-notifications and members
whose access has disappeared are suppressed by Platform. Other thread participants
are not implicitly subscribed.

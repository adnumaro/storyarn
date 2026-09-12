# Contextual project comments

Comments are a Projects-owned capability because their access and durable
lifecycle belong to one project, independently of the editor that displays them.
Canonical editor anchors are `flow_node`, `flow_canvas`, `scene_canvas` and `sheet_canvas`. Adding another editor
adds an explicit source contract and resolver; it does not create another message model. Public
callers enter through `Storyarn.Projects`. The realtime collaboration module in
Platform remains technical coordination; it does not own these conversations.

## Comments hub (ENG-188/189)

The hub is a cross-project collaboration view at `/comments`, reached from the
authenticated shell beside the notification bell and from workspace navigation.
Project chrome opens the same route with `project_id` preselected. Comments are
not a project tool: the tool switcher and editor sidebars keep their existing
responsibilities. The route shares `:authenticated_app` and uses the workspace
layout with a full-height list/detail region, without a project route parameter.

`Projects.list_comment_conversations(scope, opts)` queries all currently readable
Flow, Sheet, Scene and brainstorming threads, including conversations in which
the user has never participated. Project access and restricted-source audience
checks run before search, aggregation and activity-cursor pagination. This view
reads the same persisted threads as the editors; notification delivery and
notification read state do not determine which conversations appear here.

The list supports workspace, project, source tool, status, participation, mentions
and search filters. Selecting a conversation reauthorizes its project and source.
Replies, explicit parent replies, mentions and revision-checked resolve/reopen
use the existing Projects comment APIs. The hub has no thread-creation event or
composer without an accessible existing thread. A resolved thread must be
reopened before replying. Existing `?thread=` editor destinations provide the
"View in context" action; unavailable surfaces retain their conversation with
an explicit unavailable state, while inaccessible private brainstorming sources
disappear entirely.

Filters and selection live in the URL. List scroll and reply drafts are scoped
to the signed-in user in tab session storage; drafts additionally include the
project, thread and reply parent. Unconfirmed replies retain their request ID
so retrying cannot append a second message. These drafts are best-effort local
state, not authored project content or a guarantee of offline delivery.

User-scoped, identity-only conversation invalidations trigger fresh authorized
reads. Project/workspace access signals also refresh the hub, with periodic
reauthorization as a fallback. These subscriptions do not grow with the number
of documents. Reconnection reconstructs the view from its URL and persisted
data rather than treating previous props as current authorization.

## Brainstorming adapter (ENG-139)

`ideation_session`, `ideation_idea` and `ideation_group` are non-spatial discussion sources. The
existing Flow/Sheet/Scene surface ownership and optional context remain unchanged.
Session metadata is project-readable even during private contribution mode.
Idea discussions require a live, published idea in a session outside private
mode, including for the idea author and project owner. An unpublished edit is
never used as the discussion label or preview. Active group discussions share
the session audience outside private mode, independently of the current members
of the group. Group labels are identity-only; no synthesis or private member
revision is materialized. Decision anchors remain dependent on ENG-141.

Projects owns threads/messages; Ideation's public `comment_source` port owns the
source's current audience and identity. Writes lock project access, then session,
idea/group and thread. Generic detail, reply, resolution and idempotency replay also
check this audience. Hiding/deleting the source hides the entire discussion;
unlike a missing public editor context, it must not leave a readable preview.
The nullable source pointers and immutable recovery UUID prevent rebinding to
replacement rows. Archived sessions still support discussion; round/contribution
gates do not close conversations.

The panel lists the chosen session, shared idea or group's threads, supports explicit
parent replies, revision-checked resolution/reopening and `?thread=` links.
Requests bind to board epoch, session and discussion context. Invalidation
rechecks access before emitting props and clears the composer when access is
lost. Unconfirmed sends retain text/request identity in the mounted tab only;
there is no offline/localStorage or cross-reload draft guarantee.

Brainstorming comments follow the existing conversation lifecycle: they are not
copied or rewound by content snapshots, Ideation recovery capsules, templates or
imports. Database backups retain them. Replaced/deleted anchors cannot reveal
history through their replacement; restoring the same live source may make its
discussion available again, without resolving/reopening it. The same rule applies
to per-user following and read watermarks: they are live collaboration state,
not part of content snapshots. User/thread deletion cascades participation rows.
No private idea text or Drafts content is materialized by this adapter.

### Participation and notifications

Following is explicit and opt-in. Creating, replying, opening a permalink and
listing a thread do not subscribe or acknowledge it. Viewers may follow/unfollow
and mark accessible threads read, but cannot write messages. Read watermarks
advance monotonically through an explicitly supplied message of that thread;
the panel sends the highest message ID actually returned to it. A delayed
acknowledgement cannot swallow a later reply. Unread means a message from another
author exists beyond the watermark, independently of notification read state.

Mentions select effective project members. New messages persist in-app
notifications in the same transaction, with one recipient/message delivery:
mention wins over direct-parent reply, which wins over explicit following.
Actors never notify themselves. Unfollowing stops follower notices, not explicit
mentions or direct replies. There are no email deliveries or automatic follows.
Notifications contain no message text or source title. Listing, unread counts,
mark-read operations and destination resolution revalidate source audience and
recovery identity. Private/deleted/replaced sources disappear entirely, including
from counts, while canonical editor notification behavior stays unchanged.

User-facing inbox operations enter through `Storyarn.NotificationInbox`, which
composes Projects' visibility queries with Platform-owned recipient access and
read-state writes. The low-level Platform APIs hide comments without the
server-built visibility predicate. Both source checks use scalar, correlated
message lookups; this avoids PostgreSQL rewriting an `EXISTS` into a global
hashed readable-message set. The same predicate applies before list pagination,
unread aggregation and read-state mutation.

### Brainstorming conversation query contract

`Projects.list_ideation_conversations(scope, opts)` returns authorized thread DTOs
and a stable `{at, id}` activity cursor. Membership, active source and recovery
identity are filtered before pagination/preview materialization. Supported
filters are `project_id`, `workspace_id`, `session_id`, `source_type`, `status`,
`following`, `participated`, `mentioned`, `unread` and literal body `search` (200
bytes maximum). Personal flags select matching threads when true; false adds no
restriction. Limits default to 30 and cap at 100. Malformed options are rejected.
This query remains the brainstorming-specific adapter; the cross-editor hub
uses `Projects.list_comment_conversations/2` described above.

Ideation owns audience, identity and safe display-label query ports; Projects
composes them with membership and conversation state. Page previews load in
batches, followed by one final batched authorization check before serialization;
the query count stays constant as the page grows. Single/batched comment destinations
return audience-checked brainstorming session/thread links. Three independent
post-commit signals keep conversation activity, participation and inbox visibility
separate; all carry only identity, never content, and require scoped refetches:

- Shared comment creation, replies and resolution publish session discussion
  updates and `{:ideation_conversations_changed, project_id}` for Ideation consumers.
  Session renames also refresh Hub labels. These do not invalidate the bell;
  persisted notification deliveries already wake their individual recipients.
- Following and read acknowledgements publish
  `{:ideation_comment_participation_changed, project_id, session_id, thread_id}`
  only to the actor's personal topic. Other tabs belonging to that user refresh
  the affected open panel; other users and notification bells do not reload.
- Source audience changes publish `{:ideation_comment_sources_changed, project_id}`
  for visibility-aware consumers. This includes private-mode transitions, source
  deletion/restoration/replacement and a timer or archive that actually removes
  the private visibility mask. No-op changes, titles, timer controls, ordinary
  expiry, rounds, note/group positions, connections and private edits do not
  invalidate inbox visibility.

`subscribe_ideation_conversations` aggregates all three personal topics for
Ideation-only consumers. The cross-editor hub uses `subscribe_comment_conversations`,
whose identity-only invalidations also cover activity, source and participation changes.
Board panels subscribe to participation plus their session's shared
discussion topic. The notification shell subscribes only to source visibility
and ordinary notification deliveries, coalescing audience changes before an
authorized list/count read. Direct and inherited project membership is resolved
and deduplicated at publication time for shared Hub/source signals. New memberships
therefore work without reconnecting, and unrelated projects never wake the shell.

## Model and permissions

- A thread records source identity, author, open/resolved state, revision and
  message count. Multiple threads can discuss the same node, Flow canvas, Scene canvas or Sheet canvas.
- Messages are immutable plain text, limited to 10,000 characters. Replies
  explicitly identify a parent message in the same thread. V1 does not edit or
  redact messages and does not introduce anonymous or AI authors.
- Mentions are explicit member IDs rather than names parsed from text. Candidates
  include direct project members and workspace members with inherited access.
- Owners and editors may create, reply, resolve, reopen and move pins; viewers may read.
  Every public operation reauthorizes effective membership, with direct project
  membership taking precedence over an inherited workspace role. Mutations lock
  the project and effective membership through the existing Access capability.
- Resolved threads must be reopened before replying. Source-unavailable canonical editor threads
  remain readable but do not accept replies or state changes.
- Resolve/reopen and pin moves compare the expected revision after locking the thread. Replies
  advance that revision, so a stale resolve cannot silently close a newer reply.

## Source identity and recovery

The immutable source type, ID, containing Flow, Scene or Sheet ID, creation time and label preserve
the original context. A separate nullable `flow_node_id` reference uses **ON DELETE
SET NULL**; canvas threads use the equivalent `flow_canvas_id` or `scene_canvas_id`
reference to their owning Flow or Scene. Sheet threads use `sheet_canvas_id`, which points
to the exact Sheet whose surface owns the discussion.
Deleting a source never cascades into review history. If a deleted ID is
later reused, the null pointer prevents automatic rebinding, even when text,
coordinates or creation timestamps match. Source projections are read-only and
do not grant Comments permission to write Flow content.

The database requires each non-null anchor reference to equal its immutable
source ID. The follow-up identity migration validates existing rows and rejects
inconsistent data without repairing or deleting conversations. Null references
remain valid after a source is hard-deleted.

Soft deletion makes a source unavailable. Restoring the same existing node, Flow, Scene or Sheet makes
it available again. Hard deletion, replacement import or snapshot reconstitution
that creates new rows does not attach old discussions to the replacement. A Flow
version restore preserving the same row identity retains its discussion. Source
absence does not mean a thread was resolved or deleted.

Review history is not authored runtime content. V1 deliberately omits threads,
messages and mentions from Flow/Scene/Sheet/entity versions, canonical project snapshot
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
Scene canvas positions are percentages of the stable logical Scene bounds. Sheet positions
use a horizontal percentage of the Sheet surface and an absolute vertical document offset
from its top edge. This keeps comments beside the same header, row or block when content is
added farther down the Sheet. Sheet X remains between 0 and 100 and Y between 0 and
10,000,000 pixels.
Existing node threads keep `nil` positions for the editor's default placement;
new spatial threads require a position. Moving a pin changes its position and
revision, never its source identity, messages, author or discussion activity time.

Scene context remains optional: pins, zones, connections and annotations never own
threads. Their offsets use Scene percentages relative to the pin/annotation position,
the zone's minimum vertex X/Y, or a connection's starting pin (falling back to its
first waypoint, then its ending pin). Before deletion, database triggers preserve
that origin plus the offset as the thread's fallback position, clamped to the Scene
bounds. Endpoint cascades capture connection positions before either endpoint is
removed. This does not change messages, activity or revisions. Context without an
offset keeps its explicit saved position. Undo recreating an element with a new ID
leaves the old context unavailable and the same Scene conversation readable.

The spatial-anchor migration is explicitly irreversible: removing its columns or
canvas source type would lose persisted anchors and pin positions. Schema changes
must roll forward while preserving the conversation history.

Each editor's pin-list API filters its source family before matching the container ID. This is
load-bearing because Flow, Scene and Sheet IDs come from independent sequences and may be equal.
The pin-list API returns every available open thread without a pagination cutoff;
root messages, authors and source availability are fetched in batches. The ordinary
discussion list remains paginated. Node filters and node badge counts exclude canvas
threads. Flow canvas notification destinations have `node_id: nil`; Sheet destinations
identify the exact Sheet and never inherit into parent or child Sheets.

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
`{:flow_comments_changed, flow_id}`, `{:scene_comments_changed, scene_id}` or
`{:sheet_comments_changed, sheet_id}` on a
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

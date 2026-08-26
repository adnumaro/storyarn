# Platform internal organization

`Storyarn.Platform` is one supporting bounded context. Its first level is
organized by cohesive product capabilities plus explicit application and
technical areas. None of these folders is an additional bounded context.

| Area | Responsibility |
| --- | --- |
| `commercial/` | Plans, subscriptions, entitlements, limits, storage accounting, reservations, leases, and workspace-scoped commercial policy. |
| `reactions/` | Platform reaction routing, product metrics, privacy-safe taxonomy, and analytics transport contracts. |
| `notifications/` | Durable inbox state, recipient resolution, deduplication, visibility, read state, and post-commit invalidation. |
| `collaboration/` | Presence, cursors, editing locks, and realtime collaboration signals. |
| `discovery/` | Command-palette operations, global search, destinations, and optimized read-only discovery projections. |
| `onboarding/` | Product-wide tutorial progress and onboarding summaries. |
| `abuse_prevention/` | Rate-limit policy and its local or distributed enforcement adapters. |
| `delivery/` | Durable handoff to delivery workers after the producing context has decided intent and content. |
| `adapters/` | Stable technical integration points shared by Platform capabilities or explicitly exposed to application composition. |
| `kernel/` | A closed set of small, deterministic, business-neutral primitives used by several contexts. |

Platform is not an umbrella for code that merely happens to be shared. A new
module enters Platform only when its policy is genuinely product-wide or when
it implements one of the technical contracts above. Tool-specific decisions
remain with Projects, Sheets, Flows, Scenes, Localization, AI, Workspaces, or
Accounts.

## Capability roles

Each capability uses only the folders it needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | State-changing use cases, transaction boundaries, locks, and effect coordination. |
| `queries/` | Read-only persistence operations and bounded read models. |
| `entities/` | Mutable Platform-owned business state, including Ecto schemas and changesets. |
| `contracts/` | Stable value and behaviour contracts owned by the capability. |
| `rules/` | Deterministic policy, validation, normalization, and reference data decisions. |
| `data/` | Passive consumer-local SQL projections or immutable reference data; never persistence I/O. |
| `execution/` | Stateful or multi-step orchestration whose transaction or lock ordering must remain indivisible. |
| `events/` | Product facts and reaction handlers owned by the capability. |
| `adapters/` | Translation to PostgreSQL-specific operations, PubSub, OTP state, Oban, caches, or external providers. |

The roles describe responsibility, not an object-oriented layering exercise. A
large workflow is not split merely to make every function fit a diagram. In
particular, storage accounting keeps its existing transaction boundaries,
fencing, lease semantics, SQL, and lock acquisition order inside
`commercial/execution/`.

## `data/`

`data/` accepts exactly two categories.

### Consumer-owned SQL projections

A projection maps shared tables to the exact fields and associations one
Platform capability needs. It may duplicate another capability's mapping. That
duplication is deliberate: a notification query must not import Billing's
model just because both currently read the `projects` table.

For example, `Notifications.Data.ProjectRecord`,
`ProjectMembershipRecord`, `WorkspaceMembershipRecord`, and `UserRecord` are
owned by Notifications. They can evolve for inbox visibility and recipient
resolution without changing Commercial's accounting projections.

A data projection declares fields, associations, types, and narrowly scoped
changesets only. It does not call `Repo`, open a transaction, acquire a lock,
publish a signal, contact a provider, or decide product policy. Reads belong in
`queries/`; writes and invariants belong in `commands/` or an indivisible
`execution/` workflow.

Some Commercial and Discovery projections temporarily retain historical
module names containing `.Persistence.`. That namespace is a compatibility
identity used by existing associations and callers; there is no physical
`persistence/` area and it does not grant those modules broader ownership.

### Reference data

Reference data is immutable application data with no database identity,
lifecycle, external I/O, or transaction semantics. The commercial plan catalog
and product-metric taxonomy are examples.

There is intentionally no generic `persistence/` folder.

## Technical adapters

The top-level `adapters/` directory is intentionally explicit:

- `configuration/` resolves runtime feature and URL configuration.
- `email/` provides mail transport and shared email layout mechanics; the
  producing context still owns semantic intent and copy.
- `database/` contains generic provider-bound import mechanics, not domain
  models.
- `presentation/` contains HTML and color translation used at application
  boundaries.
- `release/` is operational release orchestration.
- `security/` contains encryption and token-provider adapters.
- `time/` owns access to the wall clock.

An adapter executes a technical operation. It does not silently acquire a new
transaction, alter lock ordering, invent an email or notification intent, or
decide a tool-specific business rule.

## Closed technical kernel

`kernel/` is not a replacement for `shared/`. Admission requires all of the
following:

1. The module is deterministic and has no `Repo`, process, network, provider,
   clock, or configuration access.
2. Its language is technical rather than a product-context business concept.
3. At least two contexts need exactly the same semantics; otherwise consumers
   duplicate or own the code locally.
4. A change can be reviewed as a stable shared-kernel contract.

The current kernel contains small JSON, map, string, search, HTML, and severity
normalization rules. Provider-bound encryption, time, sanitization, and token
generation remain adapters instead.

## Stable module identities

Files are grouped by responsibility without renaming identities used by Ecto,
runtime configuration, OTP registration, LiveVue, tests, or persisted Oban
jobs. Important stable entry points include:

- `Storyarn.Platform`, `Billing`, `Entitlements`,
  `ProjectStorageReservations`, and `Billing.Subscription`
- `Notifications` and `Notifications.Notification`
- `EventTracker`, `ProductMetrics`, `Analytics`, and its adapters/contracts
- `Collaboration`, `Collaboration.Presence`, and `Collaboration.Locks`
- `CommandPalette`, `GlobalSearch`, `Onboarding`, and `RateLimiter`
- `Mailer`, `Vault`, `FeatureFlags`, `Urls`, `Release`, and the established
  `Storyarn.Platform.Shared.*` technical identities
- `Storyarn.Workers.DeliverInvitationWorker`

Stable identity is a compatibility contract, not permission to call private
commands, queries, projections, execution modules, events, or adapters.

## Boundary rules

- Product contexts enter Platform business policy through `Storyarn.Platform`.
- The root facade is declarative and composes Commercial, Reactions,
  Notifications, Delivery, and Onboarding capability facades.
- Existing platform-wide application services retain exact public facets while
  their consumers are migrated deliberately; their private role folders remain
  internal.
- One capability never imports another capability's `data/`, `commands/`,
  `queries/`, `execution/`, `events/`, or `adapters/` folders.
- Workers retain their stable `Storyarn.Workers.*` identity and orchestrate
  through public facades.
- Product contexts own the facts, notification intent, email intent, and quota
  application they produce. Platform owns cross-cutting reaction, delivery,
  and commercial policy.
- `Repo` and SQL tables remain shared in this phase. Code ownership is isolated
  first so schema and database separation can happen independently later.

## Known transitional seams

- Invitation delivery still forms the inherited runtime path
  `Platform -> Delivery -> Storyarn.Workers -> Projects -> Platform`. The
  durable worker identity is preserved in this phase; new capabilities must
  not copy this dependency shape. Removing it requires a neutral job contract,
  not another cross-capability call.
- The root facade temporarily exports the stable reservation receipt/error
  types and an `Oban.Job` delivery result. These are compatibility contracts,
  not the target API for extracting Platform. They should become
  transport-neutral in the later persistence/process separation phase.

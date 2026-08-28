# Platform internal organization

`Storyarn.Platform` is one supporting bounded context. Its first level is
organized by cohesive product capabilities plus explicit application and
technical areas. None of these folders is an additional bounded context.

| Area              | Responsibility                                                                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `commercial/`     | Plans, subscriptions, entitlements, limits, storage accounting, reservations, leases, and workspace-scoped commercial policy.                                 |
| `reactions/`      | Platform reaction routing, product metrics, privacy-safe taxonomy, and analytics transport contracts.                                                         |
| `notifications/`  | Durable inbox state, recipient resolution, deduplication, visibility, read state, and post-commit invalidation.                                               |
| `collaboration/`  | Platform-owned realtime coordination: presence, cursors, editing locks, and editor signals. It is not another bounded context.                                |
| `discovery/`      | Platform-owned application/query coordination for command palette, global search, destinations, and read-only projections. It is not another bounded context. |
| `onboarding/`     | Product-wide tutorial progress and onboarding summaries.                                                                                                      |
| `delivery/`       | Durable handoff to delivery workers after the producing context has decided intent and content.                                                               |
| `object_storage/` | Provider-neutral object I/O, hashing, key locks and Local/R2 implementations. Consumer contexts retain every business storage decision.                       |
| `adapters/`       | Stable technical mechanisms such as clock, rate-limit counters, security, mail and runtime configuration.                                                     |
| `kernel/`         | A closed set of small, deterministic, business-neutral primitives used by several contexts.                                                                   |

Platform is not an umbrella for code that merely happens to be shared. A new
module enters Platform only when its policy is genuinely product-wide or when
it implements one of the technical contracts above. Tool-specific decisions
remain with Projects, Sheets, Flows, Scenes, Localization, AI, Workspaces, or
Accounts.

Rate-limit policy follows the same rule: each consumer owns its bucket names,
limits and windows. Platform owns only the ETS/Redis counter mechanism.

## Object storage ownership

`Storyarn.Platform.ObjectStorage` is a reviewed technical capability with one
public facade. It is consumed directly rather than being re-exported through
the business-oriented `Storyarn.Platform` facade. Its `adapters/`, `Hashing`
and `KeyLock` modules are private implementation details.

| Platform owns                                 | Consumer contexts own                                                                                   |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Provider selection and runtime configuration  | Key namespaces and key construction                                                                     |
| Local/R2 I/O and conditional-copy supervision | Authorization, reachability, retention and deletion decisions                                           |
| Incremental hashing and generic key locks     | Snapshots, imports, durable cleanup, ownership transfer, quota application and provider-error semantics |

Projects therefore keeps its recoverable-blob guard, multipart cleanup grammar,
compensation and reconstitution policy. Flows, Sheets and Scenes keep their own
storage adapters and deletion guards. Workspaces consumes the mechanism through
its Banner storage port. Sharing the provider does not grant one consumer the
right to interpret or delete another consumer's objects.

Admission to this capability requires provider-neutral behavior, no product
aggregate or consumer key grammar, and a stable need across multiple contexts.
Code exits back to a consumer as soon as its language includes a specific
workflow, ownership rule, lifecycle, retention rule or authorization decision.
These criteria keep Platform from becoming a generic shared-code drawer.

## Capability roles

Each capability uses only the folders it needs:

| Folder            | Responsibility                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------ |
| `commands/`       | State-changing use cases, transaction boundaries, locks, and effect coordination.                      |
| `queries/`        | Read-only persistence operations and bounded read models.                                              |
| `entities/`       | Mutable Platform-owned business state, including Ecto schemas and changesets.                          |
| `contracts/`      | Stable value and behaviour contracts owned by the capability.                                          |
| `rules/`          | Deterministic policy, validation, normalization, and reference data decisions.                         |
| `projections/`    | Passive, consumer-owned, read-only SQL mappings over shared tables.                                    |
| `reference_data/` | Immutable shipped catalogs without database identity, lifecycle, or I/O.                               |
| `execution/`      | Stateful or multi-step orchestration whose transaction or lock ordering must remain indivisible.       |
| `events/`         | Product facts and reaction handlers owned by the capability.                                           |
| `adapters/`       | Translation to PostgreSQL-specific operations, PubSub, OTP state, Oban, caches, or external providers. |

The roles describe responsibility, not an object-oriented layering exercise. A
large workflow is not split merely to make every function fit a diagram. In
particular, storage accounting keeps its existing transaction boundaries,
fencing, lease semantics, SQL, and lock acquisition order inside
`commercial/execution/`.

## Projections and reference data

The two passive roles remain explicit siblings of `adapters/`.

### Consumer-owned SQL projections

A projection maps shared tables to the exact fields and associations one
Platform capability needs. It may duplicate another capability's mapping. That
duplication is deliberate: a notification query must not import Billing's
model just because both currently read the `projects` table.

For example, `Notifications.Projections.ProjectRecord`,
`ProjectMembershipRecord`, `WorkspaceMembershipRecord`, and `UserRecord` are
owned by Notifications. They can evolve for inbox visibility and recipient
resolution without changing Commercial's accounting projections.

A projection declares fields, associations, types, and narrowly scoped
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
- `security/` contains encryption, sanitization and token-provider adapters.
- `clock.ex` owns access to the wall clock without pretending Time is a capability.
- `rate_limiter.ex` and `rate_limiter/` implement the policy-neutral counter mechanism.

Release migration orchestration lives outside Platform's business tree at
`lib/storyarn/release.ex`; its established module identity remains stable for
release scripts. Presentation-only color and severity helpers live in
`StoryarnWeb`.

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

The current kernel contains narrowly named map access, integer parsing, string,
search and HTML primitives. Formula numeric semantics, presentation severity,
canonical AI JSON and import workflows belong to their consumers rather than
to this kernel.

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
- `Storyarn.Platform.ObjectStorage`; its provider, hashing and lock modules are private
- `Mailer`, `Vault`, `FeatureFlags`, `Urls`, `Release`, and the remaining
  compatibility-safe technical identities
- `Storyarn.Workers.DeliverInvitationWorker`

Stable identity is a compatibility contract, not permission to call private
commands, queries, projections, execution modules, events, or adapters.
The few surviving `Storyarn.Platform.Shared.*` module names are compatibility
identities only: there is no `shared/` folder or open Shared layer, and new code
must use the named `Kernel` or adapter contract instead.

## Boundary rules

- Product contexts enter Platform business policy through `Storyarn.Platform`.
- Product contexts enter provider-neutral object storage only through the exact
  `Storyarn.Platform.ObjectStorage` contract and their own adapter or port.
- The root facade is declarative and composes Commercial, Reactions,
  Notifications, Delivery, and Onboarding capability facades.
- Existing platform-wide application services retain exact public facets while
  their consumers are migrated deliberately; their private role folders remain
  internal.
- One capability never imports another capability's `projections/`, `commands/`,
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

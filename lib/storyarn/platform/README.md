# Platform internal organization

`Storyarn.Platform` is one supporting bounded context for product-wide control
plane policy. Commercial policy is not part of Platform: plans, subscriptions,
entitlements, usage limits and storage-capacity accounting belong to the
independent `Storyarn.Commercial` bounded context.

Platform's first level is organized by cohesive capabilities plus explicit
application and technical areas. None of these folders is an additional bounded
context.

| Area              | Responsibility                                                                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reactions/`      | Platform reaction routing, product metrics, privacy-safe taxonomy, and analytics transport contracts.                                                         |
| `notifications/`  | Durable inbox state, recipient resolution, deduplication, visibility, read state, and post-commit invalidation.                                               |
| `onboarding/`     | Product-wide tutorial progress and onboarding summaries.                                                                                                      |
| `collaboration/`  | Platform-owned realtime coordination: presence, cursors, editing locks, and editor signals. It is not another bounded context.                                |
| `discovery/`      | Platform-owned application/query coordination for command palette, global search, destinations, and read-only projections. It is not another bounded context. |
| `object_storage/` | Provider-neutral object I/O, hashing, key locks and Local/R2 implementations. Consumer contexts retain every business storage decision.                       |
| `adapters/`       | Stable technical mechanisms such as clock, rate-limit counters, security, mail and runtime configuration.                                                     |
| `kernel/`         | A closed set of small, deterministic, business-neutral primitives used by several contexts.                                                                   |

Platform is not an umbrella for code that merely happens to be shared. A new
module enters Platform only when its policy is genuinely product-wide or when
it implements one of the technical contracts above. Tool-specific decisions
remain with Projects, Sheets, Flows, Scenes, Localization, AI, Workspaces or
Accounts; commercial decisions remain with Commercial.

Rate-limit policy follows the same rule: each consumer owns its bucket names,
limits and windows. Platform owns only the ETS/Redis counter mechanism.

## Public business facade

`Storyarn.Platform` is the public business facade for product reactions,
notifications and onboarding. Product contexts own the facts, notification
intent and email intent they produce; Platform owns the cross-cutting reaction
policy and durable notification-inbox lifecycle.

Product analytics reactions are best-effort. Notification and email delivery
must use persisted, idempotent workflows with retries rather than synchronous
callbacks added to the event tracker.

Discovery and realtime collaboration retain their exact reviewed public facets
while their callers are migrated deliberately. They do not become generally
available merely because their files live below `platform/`.

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

Commercial owns billable storage usage, capacity reservations and their lease
policy. ObjectStorage owns only the provider-neutral byte mechanism. Neither
boundary may infer the other's business policy from shared access to the same
provider or database.

Admission to ObjectStorage requires provider-neutral behavior, no product
aggregate or consumer key grammar, and a stable need across multiple contexts.
Code exits back to a consumer as soon as its language includes a specific
workflow, ownership rule, lifecycle, retention rule or authorization decision.
These criteria keep Platform from becoming a generic shared-code drawer.

## Capability roles

Each capability uses only the folders it needs:

| Folder         | Responsibility                                                                               |
| -------------- | -------------------------------------------------------------------------------------------- |
| `commands/`    | State-changing use cases, transaction boundaries, locks, and effect coordination.            |
| `queries/`     | Read-only persistence operations and bounded read models.                                    |
| `entities/`    | Mutable Platform-owned business state, including Ecto schemas and changesets.                |
| `contracts/`   | Stable value and behaviour contracts owned by the capability.                                |
| `rules/`       | Deterministic policy, validation and normalization.                                          |
| `projections/` | Passive, consumer-owned, read-only SQL mappings over shared tables.                          |
| `execution/`   | Stateful or multi-step workflows whose transaction or lock ordering must remain indivisible. |
| `events/`      | Product facts and reaction handlers owned by the capability.                                 |
| `adapters/`    | Translation to PostgreSQL, PubSub, OTP state, Oban, caches or external providers.            |

The roles describe responsibility, not mandatory hexagonal layers. A workflow
is not split merely to make every function fit a diagram.

## Projections and reference data

A projection maps shared tables to the exact fields and associations one
Platform capability needs. It may duplicate another context or capability's
mapping. That duplication is deliberate: notification recipient resolution
must not import a Commercial usage projection just because both read the
`projects` table.

For example, `Notifications.Projections.ProjectRecord`,
`ProjectMembershipRecord`, `WorkspaceMembershipRecord`, and `UserRecord` are
owned by Notifications. They can evolve for inbox visibility and recipient
resolution without changing another context's schemas.

A projection declares fields, associations and types. It does not call `Repo`,
open a transaction, acquire a lock, publish a signal, contact a provider or
decide product policy. Reads belong in `queries/`; writes and invariants belong
in `commands/` or an indivisible `execution/` workflow.

Reference data is immutable application data with no database identity,
lifecycle, external I/O or transaction semantics. The product-metric taxonomy
is the current Platform example. There is intentionally no generic
`persistence/` folder.

## Technical adapters and kernel

The top-level `adapters/` directory is intentionally explicit:

- `configuration/` resolves runtime feature and URL configuration.
- `email/` provides mail transport and shared layout mechanics; the producing
  context still owns semantic intent and copy.
- `security/` contains encryption, sanitization and token-provider adapters.
- `oban/` contains policy-neutral runtime helpers for bounded queue signalling;
  it never creates or interprets a context's jobs.
- `clock.ex` owns access to the wall clock without pretending Time is a capability.
- `rate_limiter.ex` and `rate_limiter/` implement the policy-neutral counter mechanism.

Release migration orchestration lives outside Platform's business tree at
`lib/storyarn/release.ex`; its established module identity remains stable for
release scripts. Presentation-only color and severity helpers live in
`StoryarnWeb`.

`kernel/` is not a replacement for `shared/`. Admission requires deterministic,
business-neutral semantics, no Repo/process/network/provider/clock/configuration
access and at least two consumers that need exactly the same stable contract.
The current kernel contains narrowly named map access, integer parsing, string,
search and HTML primitives.

## Stable identities and boundary rules

Stable Platform entry points include:

- `Storyarn.Platform`, `Notifications` and `Notifications.Notification`
- `EventTracker`, `ProductMetrics`, `Analytics`, and its adapters/contracts
- `Collaboration`, `Collaboration.Presence`, and `Collaboration.Locks`
- `CommandPalette`, `GlobalSearch`, `Onboarding`, and `RateLimiter`
- `Storyarn.Platform.ObjectStorage`; its provider, hashing and lock modules are private
- `Mailer`, `Vault`, `FeatureFlags`, `Urls`, `Release`, and remaining technical identities

Stable identity is a compatibility contract, not permission to call private
commands, queries, projections, execution modules, events or adapters. The few
surviving `Storyarn.Platform.Shared.*` names are compatibility identities only:
there is no open Shared layer, and new code must use a named Kernel or adapter
contract instead.

- Product contexts enter reaction, notification and onboarding policy through
  `Storyarn.Platform`.
- Product contexts enter commercial policy through `Storyarn.Commercial`, never
  through Platform.
- Product contexts enter provider-neutral object storage only through the exact
  `Storyarn.Platform.ObjectStorage` contract and their own adapter or port.
- One Platform capability never imports another capability's private role folders.
- Workers retain their stable `Storyarn.Workers.*` identity and orchestrate
  through public facades.
- `Repo` and SQL tables remain shared in this phase. Code ownership is isolated
  first so schema and database separation can happen independently later.

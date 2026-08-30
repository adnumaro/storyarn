# Bounded-context map

> Owner: Engineering
>
> Last reviewed: 2026-08-30
>
> Scope: current modular monolith over one Repo and PostgreSQL schema

This document records Storyarn's domain relationships. It complements the
executable import policy in `config/architecture_boundaries.exs`; it does not
replace it. The dependency ratchet protects code edges, while this map also
names semantic ownership, write authority and transitional relationships.

## Context relationships

| Upstream / owner                 | Downstream / consumer                                         | Contract today                                                                                                          | Status                                                           |
| -------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Accounts                         | Workspaces                                                    | Registration provisions the initial workspace through `Storyarn.Workspaces`                                             | Application workflow; atomic in the monolith                     |
| Workspaces                       | Projects                                                      | Workspace lifecycle coordinates Project-owned hard deletion through `Storyarn.Projects`                                 | Application workflow; extraction needs an idempotent coordinator |
| Workspaces and Projects          | Commercial                                                    | Commercial admission, plan limits, subscriptions and storage-capacity accounting through `Storyarn.Commercial`          | Reviewed public contract; ENG-112 complete                       |
| Flows, Sheets and Scenes         | Commercial                                                    | Tool-specific quota decisions consume commercial policy through `Storyarn.Commercial`                                   | Reviewed public contract; ENG-112 complete                       |
| Projects                         | Platform                                                      | Notifications and product reactions through `Storyarn.Platform`                                                         | Reviewed public contracts                                        |
| Flows, Sheets, Scenes            | Platform                                                      | Notifications and product reactions through `Storyarn.Platform`                                                         | Reviewed public contracts                                        |
| Flows, Sheets                    | AI                                                            | Consumer-owned context builders implement explicit AI contracts; execution enters `Storyarn.AI`                         | Reviewed public contracts                                        |
| Workspaces                       | AI                                                            | AI team/settings presentation composes the public AI facade                                                             | Reviewed Web composition                                         |
| Tools and project-wide consumers | Shared PostgreSQL                                             | Consumer-owned projections or records map the same tables independently                                                 | Accepted schema coupling; ENG-106 is later                       |
| Platform ObjectStorage           | Projects, Flows, Sheets, Scenes, Workspaces, Web and OTP root | Provider-neutral I/O, hashing and locks through one public technical facade; consumers own keys and lifecycle           | Reviewed technical contract; ENG-107 complete                    |
| Projects and Workspaces          | Owner-specific invitation workers                             | Each context encrypts and queues its own invitation payload; its worker executes through the same context's root facade | Owner-local durable workflow; ENG-109 complete                   |
| Localization                     | Project settings                                              | Source-language reads and ordinary changes enter `Storyarn.Localization`; Projects has no settings writer               | Reviewed public contract; ENG-110 complete                       |

Flows, Sheets and Scenes may not import one another's schemas, commands, parsers
or rules. Shared facts are read through consumer-local mappings. An ordinary
cross-tool mutation must enter the owning context through an exact reviewed
command adapter to its root facade and exchange a transport-neutral contract.
A matching table name or payload shape never grants write authority.

## Ordinary write ownership

The following table records intended ordinary product ownership. ENG-103
enforces that authority at source level for the sensitive tables already listed
in the architecture ratchet; it neither covers every table yet nor installs
PostgreSQL roles, runtime ACLs or separate schemas. Those physical database
boundaries remain ENG-106. ENG-110 was the first source-level table slice:
Localization is the sole ordinary writer of `project_languages`, while exact
Project exceptions are allowlisted by source and mutating function. Operation,
transaction contract, locks/preconditions and reason are mandatory review
metadata; the source analyzer does not prove those runtime guarantees.

For `project_languages`, the guard also inventories duplicated schemas, their
statically identifiable foreign consumers and direct SQL references across
`lib/storyarn`. The ENG-103 table inventories detect reviewed Repo/Ecto.Multi
forms and statically resolvable SQL. Unresolved raw SQL fails closed once a
source file has been selected as a candidate for an inventoried table;
runtime-built SQL that exposes no table marker remains outside that static
proof. Passive projections have a separate mutation ban. A future mixed foreign
consumer must be content-pinned, so any edit forces a fresh ownership review.
These are CI architecture guards, not database permissions or runtime
authorization, and they cannot prove the target of arbitrary runtime
indirection.

| Context      | Ordinary writes it owns                                                                                  | Explicit non-ordinary exceptions                                                                                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounts     | Users, authentication credentials/tokens, account profile and lifecycle                                  | Administrative or recovery operations must enter Accounts                                                                                                                                                                                                             |
| Workspaces   | Workspaces, memberships, invitations and workspace lifecycle                                             | Initial provisioning may be coordinated from registration                                                                                                                                                                                                             |
| Commercial   | Subscriptions, storage reservations and Commercial-owned accounting state                                | Usage and entitlement decisions may read consumer-local projections over tables owned by other contexts; consumers keep their own writes and invariants                                                                                                               |
| Projects     | Project identity, access, assets, templates, project import/export, snapshots and project-wide lifecycle | Tool-owned upload/restore workflows request asset-row registration through sealed adapters; exact reconstitution, repair and trash may write closed Project content records                                                                                           |
| Sheets       | Sheets, blocks, tables, galleries, formulas and variable definitions; block-sourced reference rows       | Sheet restore may run the classified additive project-wide variable-reference reconciliation until that projection is partitioned                                                                                                                                     |
| Flows        | Flows, nodes, connections, sequences, runtime state and Flow versions; Flow-node-sourced reference rows  | The Sheet audio workspace requests `audio_asset_id` changes through an exact command port; Project restore/reconstitution may materialize exact Flow records                                                                                                          |
| Scenes       | Scenes, layers, zones, pins, connections and Scene versions; Scene-sourced reference rows                | Project restore/reconstitution may materialize exact Scene records                                                                                                                                                                                                    |
| Localization | Languages, localized texts, glossary, extraction, translation runs and reviews                           | Projects retains exact classified `project_languages` and `localized_texts` writers only for template materialization, import, replacement, recovery and full-project snapshot restoration; Flow/Sheet versioning enters Localization through sealed command adapters |
| AI           | AI policy, integrations, routing, operations, audit and managed-spend state                              | Projects remains the current writer of selected AI configuration records until deliberately changed                                                                                                                                                                   |
| Platform     | Product reactions, notification inbox/delivery state and onboarding progress                             | Producers retain semantic event, notification and email intent                                                                                                                                                                                                        |

An exception must name the operation, paths, reason, transaction boundary and
locks or preconditions. A generic `records/` folder or a local Ecto schema does
not itself authorize writes.

`storage_cleanup_requests` is a deliberate shared technical handoff rather than
a domain table with competing owners. Flows, Sheets and Scenes may only append a
`storage_compensation` request through their exact adapters; Projects owns retry,
rotation, deferral and deletion of the durable cleanup lifecycle.

Flow snapshot build keeps its established Project `FOR SHARE` -> Flow
`FOR UPDATE` -> Localization advisory-lock order. It reaches the advisory-only
lock through a four-layer sealed call chain; the port assumes Project is already
locked and must not be used by ordinary Localization commands. Those commands
continue to acquire Project `FOR UPDATE` before the advisory inventory lock.

ENG-103 does not add a speculative Flow-to-Sheets creation port. No production
Flow workflow currently creates a Sheet or variable definition. If that product
behavior is introduced, Flows will request the intent through a narrow
`Storyarn.Sheets` command contract (or an explicit higher-level use case), and
Sheets will retain its validation, quota and transaction rules.

## Application coordinators

Global search, command palette, dashboards, operator Mix tasks and the OTP
composition root coordinate contexts but own no product aggregate. They may
compose public facades and purpose-built read projections. They must not become
an alternative domain API or call private context modules.

Platform is a control-plane grouping, not a catch-all for coordinators.
Discovery and realtime collaboration can remain physically under `platform/`
while the ratchet classifies them as application/technical code.

Commercial is a business bounded context, not a Platform capability. A consumer
enters through `Storyarn.Commercial`, owns the operation whose admission is being
checked, and applies the answer within its own transaction and invariants.
Commercial may duplicate read mappings for usage accounting; it does not gain
write ownership over the consumer tables those projections read.

## Extraction rule

A context is code-extractable when:

1. Its callers use a stable root facade or transport-neutral contract.
2. It imports no foreign domain internals.
3. Consumer-local projections cover its reads.
4. Its ordinary writers and privileged reconstitution/repair exceptions are
   explicit.
5. Transactions spanning contexts have an idempotent coordination plan.
6. Technical providers do not live under another domain's ownership.

Code extraction does not require PostgreSQL separation in the same change.
Database roles, schema extraction and removal of shared-table coupling remain a
later ENG-106 concern once code and source-level write ownership are stable.

## Tracked transitions

- [ENG-92](https://linear.app/sunset/issue/ENG-92/decouple-bounded-contexts-at-code-level-over-the-shared-database): code boundaries and ratchet.
- [ENG-103](https://linear.app/sunset/issue/ENG-103/separate-reads-from-writes-and-enforce-bounded-context-ownership): source-level ordinary write ownership and classified exceptions for the reviewed sensitive tables, including the Sheet/Flow paths.
- [ENG-107](https://linear.app/sunset/issue/ENG-107/extract-neutral-object-storage-infrastructure-from-projects-ownership): neutral object-store mechanism completed on 2026-08-28.
- [ENG-108](https://linear.app/sunset/issue/ENG-108/add-transactional-owner-transfer-workflows-for-workspaces-and-projects): explicit owner transfer after defensive guards.
- [ENG-109](https://linear.app/sunset/issue/ENG-109/remove-the-platform-invitation-delivery-runtime-cycle): the concrete invitation-delivery dependency cycle was removed with owner-specific queue adapters and workers; a database ingress router, routing fence and bounded queue wakeup protect its controlled forward-only cutover. See [the deployment contract](invitation-delivery-cutover.md).
- [ENG-110](https://linear.app/sunset/issue/ENG-110/make-localization-the-ordinary-writer-for-source-language-changes): Localization is the enforced ordinary `project_languages` writer; Project settings uses its public facade, and template materialization, exact Project import/reconstitution, and full-project snapshot restore/recovery remain classified exceptions in the ratchet.
- [ENG-111](https://linear.app/sunset/issue/ENG-111/reduce-projects-coordinator-hotspots-by-complete-use-case): incremental Projects hotspot reduction.
- [ENG-112](https://linear.app/sunset/issue/ENG-112/extract-commercial-from-platform-into-its-own-bounded-context): Commercial owns catalog, subscriptions, entitlements, usage and storage-capacity accounting behind `Storyarn.Commercial`; Platform no longer exposes or owns commercial policy.
- [ENG-106](https://linear.app/sunset/issue/ENG-106/remove-postgresql-coupling-between-bounded-contexts): later PostgreSQL roles/schema separation and removal of shared-table coupling.

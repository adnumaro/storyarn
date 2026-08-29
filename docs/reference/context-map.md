# Bounded-context map

> Owner: Engineering
>
> Last reviewed: 2026-08-29
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
| Projects                         | Platform                                                      | Commercial capacity, notifications and product reactions through `Storyarn.Platform`                                    | Reviewed public contracts                                        |
| Flows, Sheets, Scenes            | Platform                                                      | Commercial policy, notifications and product reactions through `Storyarn.Platform`                                      | Reviewed public contracts                                        |
| Flows, Sheets                    | AI                                                            | Consumer-owned context builders implement explicit AI contracts; execution enters `Storyarn.AI`                         | Reviewed public contracts                                        |
| Workspaces                       | AI                                                            | AI team/settings presentation composes the public AI facade                                                             | Reviewed Web composition                                         |
| Tools and project-wide consumers | Shared PostgreSQL                                             | Consumer-owned projections or records map the same tables independently                                                 | Accepted schema coupling; ENG-106 is later                       |
| Platform ObjectStorage           | Projects, Flows, Sheets, Scenes, Workspaces, Web and OTP root | Provider-neutral I/O, hashing and locks through one public technical facade; consumers own keys and lifecycle           | Reviewed technical contract; ENG-107 complete                    |
| Projects and Workspaces          | Owner-specific invitation workers                             | Each context encrypts and queues its own invitation payload; its worker executes through the same context's root facade | Owner-local durable workflow; ENG-109 complete                   |
| Project settings                 | Localization                                                  | Two ordinary source-language writers currently exist                                                                    | Deferred ownership correction; ENG-110 under ENG-103             |

No direct code relationship is allowed among Flows, Sheets and Scenes. Shared
facts are read through consumer-local mappings. A matching table name or payload
shape does not grant permission to import another tool's schema, parser or rule.

## Ordinary write ownership

The following is the intended ordinary product ownership. It is not yet fully
enforced at SQL-operation level; ENG-103 owns that enforcement.

| Context      | Ordinary writes it owns                                                                                  | Explicit non-ordinary exceptions                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Accounts     | Users, authentication credentials/tokens, account profile and lifecycle                                  | Administrative or recovery operations must enter Accounts                                           |
| Workspaces   | Workspaces, memberships, invitations and workspace lifecycle                                             | Initial provisioning may be coordinated from registration                                           |
| Projects     | Project identity, access, assets, templates, project import/export, snapshots and project-wide lifecycle | Exact reconstitution, repair and trash may write closed Project content records                     |
| Sheets       | Sheets, blocks, tables, galleries, formulas and variable definitions                                     | Current Flow-related writers/rebuilds remain tracked by ENG-103 and are not expanded                |
| Flows        | Flows, nodes, connections, sequences, runtime state and Flow versions                                    | Current Sheet/Localization side effects remain tracked by ENG-103                                   |
| Scenes       | Scenes, layers, zones, pins, connections and Scene versions                                              | Project restore/reconstitution may materialize exact Scene records                                  |
| Localization | Languages, localized texts, glossary, translation runs and reviews                                       | Project import/reconstitution and classified inventory repair only                                  |
| AI           | AI policy, integrations, routing, operations, audit and managed-spend state                              | Projects remains the current writer of selected AI configuration records until deliberately changed |
| Platform     | Catalog, subscriptions, entitlements, product reactions and notification inbox/delivery state            | Producers retain semantic event, notification and email intent                                      |

An exception must name the operation, tables, locks and reason. A generic
`records/` folder or a local Ecto schema does not itself authorize writes.

## Application coordinators

Global search, command palette, dashboards, operator Mix tasks and the OTP
composition root coordinate contexts but own no product aggregate. They may
compose public facades and purpose-built read projections. They must not become
an alternative domain API or call private context modules.

Platform is a control-plane grouping, not a catch-all for coordinators.
Discovery and realtime collaboration can remain physically under `platform/`
while the ratchet classifies them as application/technical code.

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
Database/schema extraction is a later concern once code and write ownership are
stable.

## Tracked transitions

- [ENG-92](https://linear.app/sunset/issue/ENG-92/decouple-bounded-contexts-at-code-level-over-the-shared-database): code boundaries and ratchet.
- [ENG-103](https://linear.app/sunset/issue/ENG-103/separate-reads-from-writes-and-enforce-bounded-context-ownership): ordinary write ownership, including the deferred Sheet/Flow paths.
- [ENG-107](https://linear.app/sunset/issue/ENG-107/extract-neutral-object-storage-infrastructure-from-projects-ownership): neutral object-store mechanism completed on 2026-08-28.
- [ENG-108](https://linear.app/sunset/issue/ENG-108/add-transactional-owner-transfer-workflows-for-workspaces-and-projects): explicit owner transfer after defensive guards.
- [ENG-109](https://linear.app/sunset/issue/ENG-109/remove-the-platform-invitation-delivery-runtime-cycle): the concrete invitation-delivery dependency cycle was removed with owner-specific queue adapters and workers; a database ingress router, routing fence and bounded queue wakeup protect its controlled forward-only cutover. See [the deployment contract](invitation-delivery-cutover.md).
- [ENG-110](https://linear.app/sunset/issue/ENG-110/make-localization-the-ordinary-writer-for-source-language-changes): Localization ordinary writer.
- [ENG-111](https://linear.app/sunset/issue/ENG-111/reduce-projects-coordinator-hotspots-by-complete-use-case): incremental Projects hotspot reduction.
- [ENG-106](https://linear.app/sunset/issue/ENG-106/remove-postgresql-coupling-between-bounded-contexts): later PostgreSQL separation.

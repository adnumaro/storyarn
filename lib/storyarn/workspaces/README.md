# Workspaces internal organization

`Storyarn.Workspaces` is the bounded-context facade. Its first level is organized
by business capability (`lifecycle`, `memberships`, `invitations`, `banner`), not
by a global technical layer. Each capability then uses only the responsibility
folders it actually needs.

| Folder               | Responsibility                                                                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `commands/`          | Use cases that change state or coordinate effects and transactions.                                                                        |
| `queries/`           | Read-only use cases. They may query through `Repo`, but cannot mutate or coordinate effects.                                               |
| `entities/`          | Mutable business state owned by Workspaces, including its Ecto schemas and changesets.                                                     |
| `rules/`             | Pure business decisions, validation, policies, and normalization.                                                                          |
| `projections/`       | Passive, consumer-owned, read-only SQL mappings over shared tables.                                                                        |
| `reference_data/`    | Immutable catalogs without database identity, lifecycle, or I/O.                                                                           |
| `delivery/`          | Invitation-owned application workflow for processing and rendering delivery. It is not a technical adapter.                                |
| `adapters/`          | Technical seams and translations to storage, Oban, Swoosh, or another provider. A seam may colocate its behaviour/port and implementation. |
| `events/`, `tokens/` | Narrow, named responsibilities used only where the capability needs them.                                                                  |

For example, `Invitations.Delivery.Handler` decides which invitation is still
deliverable and prepares its Workspace-owned content. The owner-local
`Invitations.Adapters.Jobs.InvitationQueue` encrypts the bearer token and
persists `DeliverWorkspaceInvitationWorker` in the invitation transaction,
while `Invitations.Adapters.Email.Mailer` translates the resulting email to
Swoosh. After commit, the job adapter wakes the owner queue best-effort so the
non-transactional Oban notifier cannot add Stager latency. The worker enters
only through `Storyarn.Workspaces`, so invitation eligibility, cancellation,
content, retry effects, and job ownership remain in one bounded context.

## Projections and reference data

These roles are siblings of `adapters/`: passive data must never contain a
technical effect merely because that effect happens to touch storage.

### Consumer-local SQL projections

These are minimal Ecto schemas over tables owned semantically by another
capability or bounded context. They let the consumer read the shared database
without importing the producer's code model.

- `Lifecycle.Projections.ProjectRecord` is Lifecycle's minimal view of the `projects`
  table. It does not depend on `Storyarn.Projects.Project`.
- `Memberships.Projections.ProjectMembershipRecord` is Memberships' view of the
  project-membership facts needed to decide Workspace access.
- Each capability has its own `UserRecord` containing only the user fields that
  capability needs. Duplication here is intentional.

The projection declares fields, associations, and types only. The query using
it belongs in `queries/` or `commands/`; ordinary writes remain with the owner.

### Reference data

Reference data is a small immutable catalog compiled with the application. It
has no database identity, lifecycle, external I/O, or transaction semantics. It
may expose pure enumeration or lookup functions.

`Lifecycle.ReferenceData.SourceLocaleCatalog` is the current example: a fixed list of
`%{code, name}` values used when choosing a Workspace's default source locale.
It is data rather than a rule because it only describes the available values.
Any decision such as accepting or rejecting a locale belongs in `rules/` or the
Workspace entity and may consume this catalog.

Reference data is consumer-owned. Workspaces may deliberately differ from a
similar catalog in Localization; if both lists must always be identical, the
data has one canonical owner and should not be duplicated here.

### What cannot live in these folders

`projections/` and `reference_data/` cannot call `Repo`, perform external I/O, build business changesets,
decide permissions, coordinate transactions or locks, emit events, enqueue
jobs, or call adapters. Code doing those things belongs in `queries/`,
`commands/`, `rules/`, `entities/`, or `adapters/` according to its role.

## Ownership invariant

A Workspace has one canonical owner represented by two facts that must agree:
`workspaces.owner_id` and exactly one direct `workspace_memberships` row with
`role = "owner"`. Both are set when the Workspace is created and never change
afterwards: Workspaces are not transferred between people, and ordinary
membership creation and role changes cannot assign the owner role.

Owner-only updates, deletion, banner changes, membership changes, and Workspace
AI-policy changes reauthorize the canonical owner after acquiring the
Workspace serialization lock, so a caller that authorized earlier is checked
again against current facts. Missing or ambiguous owner facts fail closed with
`:ownership_invariant_violation`.

## Read-only workspaces

While the owner's account is over its plan's limits (see the Commercial
README), `Memberships.Queries.ReadOnly` refuses changes with
`{:error, :read_only}`. `authorize/3` applies the allow-list in
`Memberships.Rules.ReadOnlyActions`; the owner and manage-members authorities
take the action they run and apply the same list. Reading the workspace,
deleting it, removing members and revoking pending invitations stay allowed.
Updating settings or the banner, changing roles, inviting, accepting an
invitation and creating projects are refused; creating a workspace is refused
while the account itself is over its limits.

These guarantees currently live at the application/transaction boundary. A
database-level constraint tying `owner_id` to the unique owner membership is a
separate reviewed persistence decision and is deliberately not bundled with
ENG-108.

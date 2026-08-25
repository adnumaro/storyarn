# Accounts internal organization

`Storyarn.Accounts` is the bounded-context facade. Its implementation is split
by three business capabilities: `identity`, `authentication`, and
`registration`. These are internal capabilities of Accounts, not additional
bounded contexts.

Each capability uses only the responsibility folders it needs:

| Folder | Responsibility |
| --- | --- |
| `commands/` | Use cases that change state or coordinate transactions and effects. |
| `queries/` | Read-only persistence operations. |
| `entities/` | Account-owned mutable state, schemas, and changesets. |
| `contracts/` | Stable application value contracts whose module identity is consumed outside the capability. |
| `rules/` | Pure business decisions and time-window policies. |
| `tokens/` | Token issuance and verification policy; persistence remains in commands or queries. |
| `delivery/` | Account-owned delivery intent, copy, rendering, and delivery workflow. |
| `events/` | Account-owned business facts published after successful operations. |
| `adapters/` | Technical translations to Oban, encryption, email transport, or a library protocol. |

For example, Password Reset owns the decision to queue and the content to send.
`Authentication.Adapters.Jobs.PasswordResetQueue` translates that request into
an Oban job, while `Authentication.Adapters.Email.Mailer` translates a rendered
message into the platform mail transport. Neither adapter owns authentication
or recovery policy.

## Stable module identities

The files are grouped by capability without renaming these established modules:

- `Storyarn.Accounts.User`
- `Storyarn.Accounts.UserToken`
- `Storyarn.Accounts.Scope`

They are schemas or application contracts used by existing configuration and
consumers. Their names are compatibility contracts; their file locations do not
make `identity` or `authentication` separate bounded contexts.

## Why there is no `data/`

Accounts currently reads and writes its own `users` and `users_tokens` data. It
has neither a consumer-local projection over another context's tables nor an
immutable reference catalog, so a `data/` folder would communicate a
responsibility that does not exist. If either need appears later, it must be
documented using the same projection/reference-data contract as Workspaces.

## Cross-context coordination

Public registration creates the user's default workspace in the same database
transaction through the `Storyarn.Workspaces` facade. This is an explicit
application workflow and not a technical adapter. Account business events are
published through `Storyarn.Platform`; mail layout and transport remain
technical Platform services, while Accounts owns the intent and message copy.

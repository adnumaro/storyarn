# AI Integrations

This capability owns personal provider connections, workspace assignments,
personal consent, provider/model preferences, provider-key validation and the
append-only integration audit trail.

The public boundary is `Storyarn.AI.Integrations`. Consumers should not call
the implementation modules directly. Stable persisted entities keep their
existing module identities because migrations, associations and external
configuration may refer to them.

## Structure

- `entities/` contains the capability's persisted business records.
- `commands/` contains credential and assignment mutations. Transaction and
  lock boundaries stay intact here.
- `queries/` contains read-only lookup and provider-catalog operations.
- `execution/` contains workflows that combine reads and writes because
  splitting them would cut a security or transaction boundary.
- `rules/` contains deterministic role/capability rules.
- `events/` owns the append-only integration security audit.
- `contracts/` defines the configurable provider adapter SPI.
- `adapters/` implements provider-specific key validation.
- `data/` contains consumer-owned Ecto projections of Accounts and Workspaces
  tables. They are deliberately small, read-only outside Ecto associations,
  and exist so Integrations does not depend on another context's schema module.

`data/` records do not claim ownership of the shared SQL tables. Integrations
owns writes only to `ai_integrations`, assignments, consents, preferences and
its audit table.

## Cross-capability seams

Integrations consumes AI Governance for workspace access and policy, and AI
Routing for task/model contracts. Those calls must go through the respective
capability facades once the surrounding AI migration has stabilized; direct
legacy module identities are transitional compatibility, not new public API.

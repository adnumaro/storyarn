# Slice 5.1 — Central AI Routing + Workspace Assignments

## Objective

Provide one central route-resolution boundary, a curated model-capability catalog, and an explicit assignment between each actor-owned AI connection and the workspaces where that actor chooses to use it.

This slice does not introduce automatic personal role/default selection. Every execution still starts from an explicit route choice and never changes provider, lane, or payer silently.

## Connection-to-workspace assignment

Personal credentials remain account-level, actor-owned connections. They are not copied into projects or stored once per workspace.

- A connection may be assigned to multiple workspaces without duplicating its encrypted secret.
- Assignment is the connection owner's choice and is separate from both owner-controlled member egress policy and per-capability consent.
- A workspace owner may assign their connection to any workspace they own.
- A non-owner may assign a connection only while the workspace permits member personal AI. Task permissions remain an execution-time requirement rather than granting a blanket workspace entitlement during assignment.
- Central route resolution requires an active workspace assignment before offering or accepting a personal route.
- Removing an assignment invalidates outstanding personal route references and consent eligibility for that connection/workspace without disconnecting the account-level credential.
- The integrations UI shows each connection's assigned workspaces and explains permitted, blocked, and consent-required states.

The initial UI keeps the Slice-4 limit of one active connection per provider and user. The assignment model references a connection id rather than embedding provider secrets so it can later support multiple labeled connections for the same provider. If that extension ships, at most one connection for a provider may be selected by one user in one workspace, while the same connection may still serve several workspaces.

## Central route resolution

Consumers call the `Storyarn.AI` facade for route resolution. They never call provider-specific selection helpers, inspect integration secrets, or invent a fallback.

Resolution evaluates:

1. the registered task, current workspace policy, and actor permissions;
2. the explicit Slice-2 route reference selected for this invocation;
3. connection ownership and active workspace assignment for personal BYOK;
4. provider/model capability, integration health, consent, allowance, and operational switches;
5. immutable provider, model, lane, payer, assignment source, and policy/price provenance.

The resolver returns a classified error/CTA when the selected route is unavailable. It never changes provider, lane, model, or payer silently.

Slice 5.1 preserves the existing explicit-choice flow:

- `explicit_invocation` for a user-selected personal route;
- `operator_default` for the configured Storyarn AI route.

Personal role/default assignment sources are added only in Slice 5.2.

## Model capability catalog

- Capabilities are curated and versioned per provider+model, not only per provider.
- Store structured-output support, modality, context/output limits, region constraints, deprecation, and pricing-version metadata where known.
- Key validation/model discovery returns what the account can see; Storyarn intersects that list with the curated catalog.
- Listing a model does not prove endpoint access; runtime capability errors remain explicit.
- Removed or deprecated models cannot produce new route references and require repair; there is no silent substitution.
- DeepL retains provider-level translation metadata and has no model picker. It is not a selectable personal execution route until a registered executable personal translation task exists.

## Existing code to reuse

Slice-0 provider metadata/settings UI · Slice-2 TaskRegistry, route-option and execution contracts · Slice-3 managed route and allowance · Slice-4 personal BYOK, consent and egress policy · existing settings layout/select components · gettext/i18n.

## Non-goals

- “My AI Team” roles or personal default-model preferences (Slice 5.2).
- Workspace/project-owned credentials or duplicated per-workspace secrets.
- Shared project role assignments or per-language team routing.
- Personal translation/DeepL execution tasks or adapters.
- Destructive migration of `translation_provider_configs`.
- Automatic fallback or dynamic cost/quality optimization.

## Security and lifecycle rules

- Assignment mutations require the authenticated connection owner and a current eligible workspace membership.
- No owner/admin can assign, inspect, or use another member's connection.
- Assignment queries are scoped by actor before workspace/provider filtering.
- Removing membership, disabling member personal AI, revoking/disconnecting the integration, or removing the assignment causes route resolution and execution reauthorization to fail closed.
- Assignment rows and audit metadata never contain encrypted or plaintext provider credentials.
- Concurrent assignment changes preserve at most one selected connection per actor+workspace+provider.

## Observability and error handling

- Audit assignment create/remove and model-catalog repair events without secrets.
- Preserve assignment source in route and operation provenance.
- Distinguish provider disconnected, assignment required, workspace policy denied, model unavailable/deprecated, capability mismatch, consent required/revoked, allowance unavailable, and operational disablement.

## Verification / Definition of Done

- ExUnit: actor ownership, eligible workspace assignment, owner/member policy behavior, cross-workspace isolation, concurrent uniqueness, assignment removal invalidation, catalog constraints, central route precedence, explicit route provenance, and no silent payer/provider switch.
- Vitest/LiveView: assigned-workspace controls, blocked/permitted/consent-required explanations, deprecated/unavailable state, and Storyarn-vs-personal lane disclosure.
- Browser: assign one personal connection to an owned workspace and an eligible member workspace, remove one assignment, and verify the affected personal route shows repair instead of falling back.
- User documentation explains account-level credentials, workspace assignment, workspace egress policy, and per-task consent as distinct controls.
- Frontend formatting, relevant backend/frontend suites, E2E coverage, and `mix precommit` are green.

## Delivery

Branch `codex/slice5-1-routing-assignments` from `main` → PR → merge before Slice 5.2. Keep `:ai_integrations` invite-only through browser verification.

## Inputs from previous slices

Slices 2–4 plus Slice-0 provider integrations.

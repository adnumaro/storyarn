# Slice 7.2b — Personal BYOK Lane + Public AI Documentation

**Status:** pending; blocked on merged Slice 7.2a.

## Objective

Offer the Slice-7.2a explanation task through the initiating user's personal
BYOK route as an explicit alternative to Storyarn AI, and publish the public
en/es AI documentation now that payer choice and BYOK billing are real.

This slice adds a second route to one existing task. It does not add a second
task, a second result surface, or any automatic lane substitution.

## Product decisions

- Managed and personal BYOK are explicit choices. There is no silent fallback,
  provider/model substitution, or payer change.
- Personal routes resolve only through the Slice-5.2 **General assistant**
  preference; writing-assistant, illustrator, and voice roles are never used.
- Choosing the personal route creates a separate personal operation after
  capability-scoped consent, never a mutation of the managed one.
- Every Slice-7.2a invariant is preserved: one server-selected current finding,
  bounded narrative output, deterministic facts rendered separately,
  actor-private temporary results, no apply/attach/share.

## Task contract delta

The registered task changes in exactly three fields:

- `allowed_lanes` gains `personal_byok`;
- the personal lane is enabled;
- a personal cost class is declared.

Input/output schemas, prompt, context scope, result type, TTL, destination, and
limits are unchanged, so a personal explanation and a managed explanation are
the same product with a different payer.

Task registration must succeed in a BYOK-only deployment (no managed provider
configured) and in a deployment with both lanes disabled, reporting an honest
blocked state instead of hiding the command inconsistently.

## Preflight, consent, and isolation delta

The panel additionally:

- offers **Use my own API key** only when a compatible General-assistant route
  exists for the actor in this workspace;
- opens the current BYOK data/billing disclosure when that route is chosen;
- requires capability-scoped consent, at the current policy text version,
  before creating a separate personal operation;
- displays the personal billing class instead of a fixed managed price.

Closing, declining, or failing consent creates no operation. A stale consent
version invalidates the choice and re-prompts. A personal provider error never
causes a managed retry, and a managed error never causes a personal retry.

Personal execution additionally requires an actor-owned connection, an active
workspace assignment and policy, a compatible General-assistant primary, and
current task consent.

## Documentation publication

This is the first public end-user AI task. Publish the en/es AI guide section
prepared in Slice 1 for all readers:

- remove its global docs gate from direct routes, navigation/search, sitemap,
  and `llms.txt`;
- keep in-app AI surfaces actor-gated by `:ai_integrations`;
- distinguish free deterministic analysis from optional generated explanation;
- explain exactly what finding/evidence is sent, provider/payer choice, BYOK
  billing/data processing, retention, staleness, and the lack of automatic
  mutation/fallback.

Public documentation is not an entitlement boundary.

## Existing code to reuse

Slice-4 BYOK consent · Slice-5.1 route resolver · Slice-5.2 General-assistant
preference · Slice-7.2a task, panel operation lifecycle, and palette command ·
`ContextDisclosure` · `Storyarn.Analytics` · the Slice-1 documentation shell and
docs visibility gate.

## Non-goals

- Any change to the deterministic analysis or to the explanation's output
  schema.
- Workspace-owned BYOK keys.
- Writing-assistant/media role routing.
- Multi-finding or whole-flow AI reports.
- Sharing, exporting, attaching, or persisting generated reports.
- Automatic retries or lane/provider/payer fallback.

## Observability and error handling

- Product events add consent shown, consent granted, and consent declined,
  alongside the Slice-7.2a preflight/route/execution/result events.
- Canonical usage events record the personal lane, provider/model, units,
  latency, status, versions, and low-cardinality error class; personal cost is
  reported as its billing class, never as a Storyarn price.
- Content, credentials, optional notes, prompts, and raw ids are excluded.
- Classify consent required, consent declined, consent version stale, no
  compatible personal route, unsupported model, and personal provider failure.

## Verification / Definition of Done

- ExUnit covers General-assistant role mapping and task registration in managed,
  BYOK-only, and both-disabled deployments.
- ExUnit covers personal accounting, the explicit consent-gated CTA, consent
  version staleness, actor-private results, and the absence of any silent
  fallback in either direction.
- Provider contract tests validate the same structured narrative schema and
  output limits on the personal adapters.
- Vitest/LiveView covers every consent state, personal payer disclosure, and the
  managed/personal choice surface.
- Palette behavior is verified for an actor with only a personal route, only a
  managed route, and neither.
- Browser coverage runs one personal route with deterministic fakes, including
  consent decline and stale rerun.
- Public en/es docs are reachable through direct URL, navigation/search,
  sitemap, and `llms.txt`.
- `pnpm run fmt`, `just quality-lint`, relevant full suites, E2E, and
  `mix precommit` are green.

## Delivery

Branch `codex/slice7-2b-personal-lane-docs` from `main` after Slice 7.2a
merges → one PR. The PR includes the lane extension, the consent surface, and
the public documentation publication; no report-sharing subsystem.

## Inputs from previous slices

Slices 2–6 plus merged Slices 7.1 and 7.2a. Slice 1 supplies the palette
foundation and the prepared documentation shell.

# Slice 7.2 — Optional AI Explanation

**Status:** pending; blocked on merged Slice 7.1.

## Objective

Ship the first end-user AI task: explain exactly one current deterministic
structural finding through Storyarn AI or the initiating user's personal BYOK
route, while keeping the generated narrative actor-private and visibly
separate from Storyarn's deterministic facts.

## Product decisions

- One operation explains one selected current finding. Multi-finding and
  whole-flow reports are deferred.
- Storyarn supplies the finding and typed evidence from Slice 7.1/6. The client
  cannot author either.
- The model returns bounded narrative fields, not finding ids, evidence ids,
  permissions, routes, or actions. Storyarn attaches the selected
  `finding_id`/fingerprint to the result.
- The UI always renders deterministic facts and limitations separately from the
  generated explanation.
- The result is an actor-private temporary preview. V1 has no apply, attach,
  share, or persisted-report mutation.
- Opening/rendering a result records `viewed`, never `accepted`.
- Managed and personal BYOK are explicit choices. There is no silent fallback,
  provider/model substitution, or payer change.

## Registered task contract

Add one production task, independent of whether the managed provider is
configured, so a BYOK-only deployment can still register and offer it.

The task declares:

- capability `tasks`, resolving personal preferences only through the Slice-5.2
  **General assistant**;
- project/entity data scope and current project-view permission;
- context scope `structural_finding`;
- lanes `managed` and `personal_byok`;
- versioned input/output schemas, prompt, context, rule compatibility, result
  type, and operational switch;
- hard serialized input/output and provider token limits;
- background execution with the structural-analysis panel as destination;
- actor-private result visibility and an explicit short TTL;
- no bulk or scheduled execution.

The model output schema contains only bounded narrative, for example a concise
summary, why the deterministic evidence triggers the rule, implications to
inspect, and non-mutating suggested checks. It cannot introduce another finding
or claim that Storyarn proved condition satisfiability.

Using one server-attached finding removes the unsafe requirement for
`validate_output/1` to compare model-supplied finding ids against hidden input.
Unknown/stale finding ids fail before context construction and no provider call
occurs.

## Preflight, allowance, and consent

Opening the explanation surface is a palette/panel `launch` and creates no
operation.

Before execution the panel:

1. reauthorizes the actor and reloads the selected finding by server-issued id;
2. verifies the rule version and evidence fingerprint are still current;
3. builds the Slice-6 disclosure without calling a provider;
4. resolves available managed and personal routes;
5. displays provider/model, lane, payer, fixed managed price or personal billing
   class, sent-data scope, and result retention;
6. creates an operation only after the actor explicitly chooses a valid route.

Managed availability must project the current workspace allowance read-only
during preflight. If allowance is exhausted, the managed choice is blocked
before execution. The panel may offer **Use my own API key** only when a
compatible General-assistant route exists. Choosing it opens the current BYOK
data/billing disclosure and requires capability-scoped consent before creating
a separate personal operation.

Closing, declining, or failing consent creates no operation. A personal
provider error never causes a managed retry, and a managed error never causes a
personal retry.

## Result lifecycle and staleness

The panel owns operation/result state:

- preflight, consent-required, ready, queued/running, succeeded, failed,
  unknown, and expired;
- reopening or polling uses the actor-authorized result APIs, not palette state;
- result presentation revalidates the Slice-7.1 finding fingerprint and Slice-6
  provenance;
- a stale result is clearly marked obsolete and offers an explicit rerun; it is
  never silently regenerated;
- retry/rerun creates a new explicit operation with a new idempotency key;
- generated narrative is never inserted into the flow and never treated as a
  deterministic finding.

Product outcomes are task-specific: viewing the explanation, navigating to
evidence, rerunning after staleness, dismissing the deterministic finding as a
false positive, or later changing the flow so the finding resolves. Opening the
panel alone is not usefulness or acceptance.

## Permissions and isolation

- The in-app explanation surface requires `:ai_integrations`, `:use_ai`, and
  current project/flow read access.
- Managed execution additionally requires current workspace policy, allowance,
  provider circuit breakers, and task enablement.
- Personal execution additionally requires actor-owned connection, workspace
  assignment/policy, compatible General-assistant primary, and current task
  consent.
- Route references remain short-lived and server issued.
- Results are readable only by their initiating actor.
- Raw story text, prompt, evidence content, result content, and credentials
  never enter analytics or ordinary logs.

## Command palette

- Register **Explain selected finding with AI** only when the normal flow editor
  has one selected current Slice-7.1 finding.
- It uses palette v2 `launch`, opens the structural-analysis panel, and defers
  route/cost resolution to panel preflight.
- The panel reauthorizes the selection and owns the operation lifecycle.
- The command is hidden when the product flag is off, the surface has no current
  finding, or the actor lacks base eligibility. Hidden/disabled state is not an
  authorization boundary.

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

Slice-2 TaskRegistry/operations/palette v2 · Slice-3 allowance and managed route
· Slice-4 BYOK consent · Slice-5.1 route resolver · Slice-5.2 General-assistant
preference · Slice-6 structural-finding context, limits, provenance, and locks ·
Slice-7.1 finding registry/lifecycle/panel · `ContextDisclosure` ·
`Storyarn.Analytics`.

## Non-goals

- Multi-finding or whole-flow AI reports.
- Sharing, exporting, attaching, or persisting generated reports.
- Applying or automatically fixing a finding.
- Free-form chat or autonomous criticism.
- Model-generated finding/evidence ids.
- Writing-assistant/media role routing.
- Automatic retries or lane/provider/payer fallback.

## Observability and error handling

- Canonical AI operation/usage events record task, lane, provider/model, units,
  price/cost, latency, status, versions, and low-cardinality error class.
- Product events record preflight shown, route selected, consent outcome,
  execution started, result viewed, evidence navigation, stale rerun, and
  deterministic disposition outcome.
- Content, credentials, optional notes, prompts, and raw ids are excluded.
- Classify unknown/stale finding, permission/policy denial, no route, allowance
  exhausted, consent required/declined, provider/validation/unknown failure,
  result expired, and unsupported model.

## Verification / Definition of Done

- ExUnit proves only registered current findings reach context/provider code;
  client-authored evidence, cross-project ids, stale fingerprints, and unknown
  rules fail before any provider attempt.
- ExUnit covers General-assistant role mapping, task registration in managed,
  BYOK-only, and both-disabled deployments.
- ExUnit covers managed/personal accounting, read-only allowance preflight,
  explicit consent-gated BYOK CTA, no silent fallback, actor-private results,
  TTL, polling, and stale-result rerun.
- Provider contract tests validate the exact structured narrative schema and
  output limits without model-generated ids.
- Vitest/LiveView covers every preflight/consent/operation/result state, payer
  disclosure, deterministic/generated visual separation, and flag/permission
  states.
- Palette behavior is verified for eligible editor, viewer, flag-off, stale
  selection, and no-selection cases.
- Browser coverage runs one managed route and one personal route with
  deterministic fakes, including exhausted allowance and stale rerun.
- Public en/es docs are reachable through direct URL, navigation/search,
  sitemap, and `llms.txt`.
- `pnpm run fmt`, `just quality-lint`, relevant full suites, E2E, and
  `mix precommit` are green.

## Delivery

Branch `codex/slice7-2-ai-explanation` from `main` after Slice 7.1 merges → one
PR. The PR includes the first real task, panel integration, palette command,
public docs publication, and no report-sharing subsystem.

## Inputs from previous slices

Slices 2–6 plus merged Slice 7.1. Slice 1 supplies the palette foundation and
prepared documentation shell.

# Slice 7.2a — Managed AI Explanation

**Status:** implemented on `codex/slice7-2a-managed-explanation` (2026-07-25), PR #49 —
task `Storyarn.AI.Tasks.FlowFindingExplanation`, panel lifecycle in
`StoryarnWeb.FlowLive.Handlers.ExplanationHandlers`, palette command registered
from `FlowAnalysisPanel.vue`. Owner browser verification against a real provider
pending; E2E proves the deterministic fake only.

## Objective

Ship the first end-user AI task: explain exactly one current deterministic
structural finding through Storyarn AI, while keeping the generated narrative
actor-private and visibly separate from Storyarn's deterministic facts.

The personal BYOK route for the same task, and the public documentation
launch, are Slice 7.2b.

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
- Retention is 24h, not the 30 minutes first planned. The actor is charged when
  the provider call starts and is not necessarily present when it finishes, so a
  window shorter than a human absence turns a paid narrative into a silent loss —
  the one case abandoning a surface cannot recover. Still a temporary preview:
  disclosed before the purchase, swept by `ExpireAIResultsWorker`, never persisted
  into the flow.
- Opening/rendering a result records `viewed`, never `accepted`. It is recorded
  as its own `viewed_at` stamp rather than a fourth `user_disposition` value:
  disposition holds one terminal outcome, and its `IS NULL` precondition is what
  keeps dismiss, apply and expiry-abandonment reachable.
- Managed execution is an explicit choice. There is no silent fallback,
  provider/model substitution, or payer change.

## Registered task contract

Add one production task, independent of whether the managed provider is
configured, so a deployment without a managed provider still registers the task
and reports an honest blocked state instead of hiding it inconsistently.

The task declares:

- capability `tasks`;
- project/entity data scope and current project-view permission;
- context scope `structural_finding`;
- lane `managed`;
- versioned input/output schemas, prompt, context, rule compatibility, result
  type, and operational switch;
- hard serialized input/output and provider token limits;
- background execution with the structural-analysis panel as destination;
- actor-private result visibility and an explicit short TTL;
- no bulk or scheduled execution.

The task declares no personal lane in this slice; Slice 7.2b flips that flag
and adds the personal cost class without changing any other field.

The model output schema contains only bounded narrative, for example a concise
summary, why the deterministic evidence triggers the rule, implications to
inspect, and non-mutating suggested checks. It cannot introduce another finding
or claim that Storyarn proved condition satisfiability.

Using one server-attached finding removes the unsafe requirement for
`validate_output/1` to compare model-supplied finding ids against hidden input.
Unknown/stale finding ids fail before context construction and no provider call
occurs.

### Subject identity

A structural finding is identified by a string, so it cannot be the durable
operation subject directly. The task carries the finding's server-issued
identity in its validated input and re-derives the finding from the authorized
flow on every touch: context construction, execution, and result presentation.
Currency is therefore proven, never assumed, and a changed flow surfaces as a
stale result instead of a mismatched explanation.

## Preflight and allowance

Opening the explanation surface is a palette/panel `launch` and creates no
operation.

Before execution the panel:

0. resolves which attempt to act on. A result already paid for and still inside
   its TTL is rendered directly, with no preflight and no route options: the
   surface must never ask for a purchase decision that has no cost. An operation
   still in flight is attached to, which is also how two panels on one finding
   end up watching a single paid operation. Only when no attempt has either does
   the preflight below run, and then against the lowest unspent idempotency key —
   a key is consumed permanently by the first operation that uses it, even after
   that operation stops being readable. Every attempt is considered, because they
   are not necessarily spent in order: a blocked route and an abandoned preflight
   both raise the attempt without creating anything, and stopping at that gap
   would sell a narrative the actor already holds one attempt above. Attempts are
   capped, and the cap binds the rerun too — an attempt a rerun could create but
   a reopen could never reach would be a result the actor pays for and then loses
   on close;
1. reauthorizes the actor and reloads the selected finding by server-issued id;
2. verifies the rule version and evidence fingerprint are still current;
3. builds the Slice-6 disclosure without calling a provider;
4. resolves the available managed route;
5. displays provider/model, lane, payer, fixed managed price, sent-data scope,
   and result retention;
6. creates an operation only after the actor explicitly chooses a valid route.

Managed availability must project the current workspace allowance read-only
during preflight. If allowance is exhausted, the managed choice is blocked
before execution rather than failing at settlement time.

Closing or declining creates no operation. A managed error never triggers an
automatic retry.

## Result lifecycle and staleness

The panel owns operation/result state:

- `idle`, `preflight`, `blocked`, `queued`, `running`, `detached`, `succeeded`,
  `failed`, and `expired`. Two of these were named differently while planning:
  there is no distinct `ready` (a resolved preflight IS the ready state), and
  `unknown` is an error class inside `failed` rather than a state of its own,
  because the panel offers the same affordance either way. `blocked` covers a
  route the actor may use but cannot use now, and `detached` means the panel
  stopped watching a run that is still executing — reporting that as `failed`
  would push the actor toward paying twice for work still in flight;
- reopening or polling uses the actor-authorized result APIs, not palette state;
- abandoning the surface releases an operation it BOUGHT, while releasing is
  still free — decided under the kernel's own lock rather than from a status
  read, because the worker can start a provider attempt in between. It never
  releases one it only attached to, since another panel is waiting on that run,
  and never cancels a started attempt: that bills the unit anyway and destroys
  the output. The residual is deliberate — when the buyer closes first, a panel
  still attached does lose the run;
- the release also runs from `terminate/2`, not only on close. Ownership is a
  property of the buying session — two tabs of one actor are indistinguishable in
  the database — so it cannot outlive the process holding it: a refresh or dropped
  socket would otherwise orphan the operation, leaving every later surface able
  only to attach and nobody able to release. A hard crash still skips it, which
  costs the release and not the result;
- a paid result outliving its surface is advertised where the actor will return:
  the analysis panel marks each finding it can still open an explanation for. This
  is the counterpart to releasing — an operation whose provider call already
  started is charged and kept, so the actor must be able to find it without
  remembering which card to reopen. Actor-private, expiry-aware, one indexed
  lookup while the panel is open.

**Releasing on abandon is correct because there is no notification surface yet.**
The day one exists, the default should invert: the actor asked for the explanation,
so "charge and notify" beats "cancel". Charging without telling anyone is the only
incoherent option, which is what the retention below protects against.

- result presentation revalidates the Slice-7.1 finding fingerprint. Slice-6
  provenance is NOT revalidated or displayed: `Results.provenance/1` is reached
  only from `apply/4`, which this slice never calls;
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
- The command is hidden when `:ai_integrations` is off, the surface has no
  current finding, or the actor lacks base eligibility. Hidden/disabled state is
  not an authorization boundary.

## Documentation

In-app help only. The en/es AI guides stay gated behind `:ai_integrations`;
Slice 7.2b removes that gate once payer choice and BYOK billing are real.

## Existing code to reuse

Slice-2 TaskRegistry/operations/palette v2 · Slice-3 allowance and managed route
· Slice-5.1 route resolver · Slice-6 structural-finding context, limits,
provenance, and locks · Slice-7.1 finding registry/lifecycle/panel ·
`ContextDisclosure` · `Storyarn.Analytics`.

## Non-goals

- Personal BYOK lane, consent, and personal accounting (Slice 7.2b).
- Public documentation publication (Slice 7.2b).
- Multi-finding or whole-flow AI reports.
- Sharing, exporting, attaching, or persisting generated reports.
- Applying or automatically fixing a finding.
- Free-form chat or autonomous criticism.
- Model-generated finding/evidence ids.
- Streaming responses.
- Automatic retries or lane/provider/payer fallback.

## Observability and error handling

- Canonical AI operation/usage events record task, lane, provider/model, units,
  price/cost, latency, status, versions, and low-cardinality error class.
- Product events record preflight shown, preflight blocked, route selected,
  execution started, result viewed, detached (the panel stopped watching a run
  still in flight), failed, evidence navigation, stale rerun, and deterministic
  disposition outcome. `Storyarn.Analytics`'s allowlist is the authority on the
  exact names.
- Content, credentials, optional notes, prompts, and raw ids are excluded.
- Classify unknown/stale finding, permission/policy denial, no route, allowance
  exhausted, oversize context, and provider/validation/unknown failure.
  `ExplanationHandlers.error_classes/0` is the declared set, and a test asserts
  every member has copy in both locales. Expiry is a STATE, not an error class;
  there is deliberately no "unsupported model" class — the model limit failures
  are `model_context_window_exceeded`, `model_output_limit_exceeded` and
  `model_context_limits_unavailable`.

## Verification / Definition of Done

- ExUnit proves only registered current findings reach context/provider code;
  client-authored evidence, cross-project ids, stale fingerprints, and unknown
  rules fail before any provider attempt.
- ExUnit covers task registration both with and without a configured managed
  provider.
- ExUnit covers managed accounting, read-only allowance preflight, actor-private
  results, TTL, polling, and stale-result rerun.
- Provider contract tests validate the exact structured narrative schema and
  output limits without model-generated ids.
- Vitest/LiveView covers every preflight/operation/result state, payer
  disclosure, deterministic/generated visual separation, and flag/permission
  states.
- Palette behavior is verified for eligible editor, viewer, flag-off, stale
  selection, and no-selection cases.
- Browser coverage runs one managed route with deterministic fakes, including
  exhausted allowance and stale rerun.
- `pnpm run fmt`, `just quality-lint`, relevant full suites, E2E, and
  `mix precommit` are green.

## Delivery

Branch `codex/slice7-2a-managed-explanation` from `main` after Slice 7.1
merges → one PR. The PR includes the first real task, panel integration, and
palette command; no personal lane, no consent subsystem, no public docs change.

## Inputs from previous slices

Slices 2, 3, 5.1, 6 plus merged Slice 7.1. Slice 1 supplies the palette
foundation.

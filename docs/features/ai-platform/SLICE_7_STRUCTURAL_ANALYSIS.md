# Slice 7 — Structural Analysis + Optional AI Explanation

## Objective

Ship Storyarn's differentiator in two layers: free deterministic findings backed by graph evidence, then an optional Storyarn AI or personal-BYOK explanation that may narrate only those findings.

## Stage A — Deterministic analysis

- Extend existing `Storyarn.Flows.FlowStats.detect_flow_issues/1` and `Storyarn.Flows.HealthChecker.check/1`; do not create divergent detectors.
- Initial findings: unreachable nodes, disconnected branches, dead ends, orphan hubs/references, and other rules whose semantics can be defined exactly.
- Every detector declares inputs, graph/cycle semantics, severity, evidence shape, false-positive limitations, and a stable finding id.
- Separate topological reachability from condition satisfiability. Do not label state-specific evaluation as a proof that a Boolean expression is unsatisfiable.
- “Character absent for a long stretch” is excluded until branch/cycle/span semantics are formally specified.
- Findings are reproducible and auditable, not marketed as “zero hallucination”.

Stage A is a normal deterministic product capability, not AI. It is not gated by `:ai_integrations` and consumes no allowance.

## Stage B — AI explanation/report

- Registered task consumes only finding ids/evidence plus the minimal manifest from Slice 6.
- Model output references finding ids; the UI renders deterministic facts separately from generated narrative.
- Both `managed` and `personal_byok` lanes may be offered when policy/capability allows, with price/payer visible before execution.
- Report is a private preview until explicitly shared/exported.
- Rendering means `viewed`, never `accepted`.

Useful outcomes for analysis are task-specific: marking a finding useful/false-positive, navigating to evidence, resolving it, or exporting/sharing a report. None are inferred merely from opening the panel.

## Permissions

- Viewing deterministic findings follows project read access.
- Executing an AI explanation requires `:use_ai` plus project `:view`; managed execution also requires available workspace allowance.
- Resolving/dismissing a finding requires the relevant edit permission and persists a reason/version so it does not reappear unchanged.

## Command palette

- `Analyze current flow` uses the normal non-AI descriptor and opens/runs free deterministic findings.
- `Explain selected finding with AI` appears only with a selected current finding and uses palette v2 `launch`: it opens the report panel without an operation, then shows managed/BYOK route and cost before explicit execution.
- Destination is the findings/report panel; palette closure does not own the operation lifecycle.

## Existing code to reuse

FlowStats/HealthChecker · graph traversal and reference trackers · existing flow permissions · Slice-2 operations/palette v2 · Slice-3 managed allowance · Slice-4 personal BYOK · Slice-5 central routing · Slice-6 context manifest · shared panel/shell components · `Storyarn.Analytics`.

## Non-goals

- Free-form autonomous story criticism.
- Claims beyond deterministic evidence.
- Whole-project semantic search.
- Automatic mutation of flows.
- Undefined narrative-quality scoring.

## Observability and error handling

- Detector events record rule id/version/count/severity, not story content.
- AI explanation usage follows canonical operation/usage/disposition records.
- Stale evidence invalidates the report with an explicit rerun CTA.
- Unknown finding ids or unsupported model references fail schema validation.

## Verification / Definition of Done

- ExUnit per detector: branches, cycles, deleted nodes, condition-edge cases, stable ids/evidence, persistence of dismiss/resolve state.
- ExUnit AI: only known finding ids accepted, report cannot invent unreferenced findings, stale evidence rejection, managed/personal lane accounting.
- Vitest/browser: findings panel, evidence navigation, resolve/dismiss, optional AI explanation with price/lane, viewed is not accepted.
- Palette commands verified on at least two authorized roles/surfaces.
- Publish the AI guide section prepared in Slice 1 for all readers and remove its global docs gate across direct routes, navigation/search, sitemap, and `llms.txt`; the in-app AI explanation remains actor-gated. User docs clearly distinguish deterministic analysis from AI explanation.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/structural-analysis` from `main` → one PR containing both stages. Stage A is available without `:ai_integrations`; Stage B is registered and executable only when `:ai_integrations` and its operational task/provider switches pass. Do not publish Stage A as a separate PR under this slice; split the slice contract first if both stages no longer fit one reviewable PR.

## Inputs from previous slices

Slice 1 palette foundation; Slice 2 palette/operation contract; Slices 3–4 lanes; Slice 5.1 central route resolution; Slice 5.2 personal preferences; Slice 6 context for Stage B. Stage A remains ungated at runtime, but the single-PR delivery waits for every Stage-B dependency.

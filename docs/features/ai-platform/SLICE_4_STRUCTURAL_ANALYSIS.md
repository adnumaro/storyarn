# Slice 4 — Structural Analysis Tool (the differentiator)

## Objective

First flagship AI action: **"Analyze structure" on a single flow** detecting dead branches, unreachable nodes/endings, orphan hubs, and characters absent for long stretches — via **deterministic graph algorithms**, with the LLM only writing the human-readable report. Fixed credit price, verifiable findings, palette command + report panel with per-finding navigation. **Project-wide aggregation (cross-flow findings, aggregate navigation, its own context limits and authorization path) is explicitly out of scope — backlog until the flow-level tool proves itself.**

## Problem & proposed solution

**Problem:** the highest-value narrative QA ("why can't the player reach Ending B?") is exactly what generic chat-over-prose tools hallucinate on. Loreweaver must extract structure before analyzing; we own it natively.
**Solution:** pure-Elixir detectors traverse the relational flow graph (nodes + connections + conditions). Findings are facts (node ids, paths, variable states) — zero hallucination possible in detection. `AI.execute(:structural_report)` turns findings into a narrated report (standard tier, tiny context = findings only). Each finding links to its node (focus/navigate) and carries resolve/dismiss affordances feeding acceptance telemetry.

## Architectural direction

- `Storyarn.AI.Analysis` (or `Storyarn.Flows.Analysis` — decide in chat; leaning `Flows.Analysis` since detectors are AI-free domain logic; only the report step touches AI): detector modules per finding type, each pure and independently testable without any AI.
- **Detection logic already partially exists — extend, do not duplicate**: `Storyarn.Flows.FlowStats.detect_flow_issues/1` and `Storyarn.Flows.HealthChecker.check/1` already cover disconnected/dead-end and unreachable findings. Slice 4 extends/adapts those contracts (keeping their soft-delete and reachability semantics as the single source of truth) and adds the new detectors (absence spans, orphan hubs) alongside — divergent duplicate detection logic is a bug.
- Reachability over the relational model (post flow-relational-refactor F1): entry/exit nodes, connections, condition satisfiability at the boolean-structure level (full formula evaluation only where `FormulaRuntime` already provides it — do not build a solver).
- Report UI: dock panel in the flow editor (reuse `CanvasDock`) listing findings grouped by type; clicking focuses the node via the existing selection bridge. Report text rendered from the LLM narration.
- Palette command `Analyze flow structure` (scope: flows surface) → LV event → detectors (sync) → report task (async via Oban if large) → panel update via PubSub.
- Charged once per run at a published credit price; detectors alone (no narration) could be a free tier variant — OPEN sub-decision, surface in chat.

## Existing code to reuse (do not duplicate)

`Storyarn.Flows` facade: `FlowCrud`, `NodeCrud`, `ConnectionCrud` queries · **`Flows.FlowStats.detect_flow_issues/1` + `Flows.HealthChecker.check/1`** (existing detection to extend) · per-type node modules (`flow_live/nodes/{type}/node.ex`) for node metadata · `VariableReferenceTracker` (which nodes touch which variables) · `Shared.FormulaRuntime` (condition evaluation where applicable) · `CanvasDock` + `CanvasToolbar` (panel chrome) · rete selection bridge + `nodeDataVersion` reactivity contract (focus-node from panel) · `Collaboration` PubSub (report-ready broadcast) · Slice-2 `AI.execute` + Slice-3 context (findings ARE the context — minimal) · Slice-1 palette registration API.

## Applicable conventions (MUST be surfaced in chat during implementation)

Per-type node architecture respected (no giant case statements outside node modules) · `dgettext("flows", …)` for editor strings; report i18n decision surfaced in chat · authorization: running analysis requires project membership (`with_authorization(socket, :edit_content)` or read-tier — surface the choice) · Lucide icons · panel positioning via existing dock (no raw absolute positioning) · soft-delete filters in all graph queries · detectors get exhaustive ExUnit coverage BEFORE the LLM step is wired.

## Verification / Definition of Done

- ExUnit: each detector against crafted fixture graphs (dead branch, unreachable ending, orphan hub, absence spans; negative cases) · report task registration + charging.
- Vitest: findings panel (grouping, navigation events, resolve/dismiss emits).
- Browser: run on a real flow with known defects; verify findings correct, node focus works, credits debited once, acceptance events recorded.
- `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-structural-analysis` from main → PR → merge before Slice 5 starts (shared panel/acceptance patterns). Flags: `:ai_platform` (+ `:command_palette` for the command entry).

## Inputs from previous slices

Slice 1 (palette registration), Slice 2 (`execute`, credits, metering), Slice 3 (context/token budgets — minimal here). Estimate: **10–14h**.

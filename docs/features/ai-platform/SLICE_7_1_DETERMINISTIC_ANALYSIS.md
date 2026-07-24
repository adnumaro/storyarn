# Slice 7.1 — Deterministic Structural Analysis

**Status:** pending.

## Objective

Turn Storyarn's existing flow-health checks into a free, auditable product
capability: canonical structural findings with stable identity, typed evidence,
reversible false-positive dismissal, evidence navigation, and a dedicated
analysis panel.

This slice contains no model call. It is not gated by `:ai_integrations`,
consumes no AI allowance, and remains usable when every AI provider is disabled.

## Implementation-start audit

The slice starts from useful but incomplete foundations:

- `Storyarn.Flows.HealthChecker.check/1` already detects entry, reachability,
  output, pin, and reference problems inside a serialized flow.
- `Storyarn.Flows.FlowStats.detect_flow_issues/1` already supplies project
  dashboard aggregates for missing entry, disconnected nodes, and dead ends.
- Flow serialization already ignores deleted nodes, validates connection pins,
  handles cycles with a visited set, includes in-flow jump → hub edges, and
  derives reachability/output state.
- The normal flow editor already has a health summary, a popover, and
  navigation to one node.

These paths are not yet one product contract. Dashboard queries and editor
serialization can disagree, current findings are ephemeral `code + node_id`
maps, ordering is not fully canonical, and no schema stores a dismissal.

## One canonical detector boundary

Extend and converge `FlowStats` and `HealthChecker`; do not create a third
detector:

- editor, dashboard, palette, and future AI explanation consume the same rule
  registry and finding contract;
- aggregate queries may optimize discovery, but must validate findings through
  the canonical rule semantics before presenting them;
- every rule declares its inputs, graph/cycle semantics, category, severity,
  target types, evidence shape, limitations, and version;
- output ordering is deterministic and independent of query order.

Current authoring-health checks must be categorized. Slice 7.1 exposes
`structure` and `reference_integrity` findings in the structural-analysis
panel. Editorial completeness warnings may remain in the existing health
summary but are not silently promoted to structural claims or made eligible for
Slice 7.2.

## Finding and evidence contract

Every finding exposes at least:

| Field                      | Contract                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------ |
| `finding_id`               | Versioned opaque id derived from canonical finding identity and evidence fingerprint |
| `finding_key`              | Stable identity for `rule + flow + target`, independent of localized copy            |
| `rule_id` / `rule_version` | Allowlisted rule contract and semantic version                                       |
| `category` / `severity`    | Curated product metadata, never caller supplied                                      |
| `flow_id` / target         | Authorized subject and optional node/connection/reference target                     |
| `evidence`                 | Ordered typed descriptors containing ids, never caller-authored content              |
| `evidence_fingerprint`     | Hash of the canonical rule inputs needed to reproduce this occurrence                |
| `limitations`              | Localized explanation of what the rule does not prove                                |

Evidence descriptors use the Slice-6 server loaders and supported project-owned
types (`flow`, `flow_node`, `flow_connection`, and other explicitly added
types). The client may select a current `finding_id`; it cannot supply finding
content, evidence content, rule metadata, or project ids.

Negative graph claims include the relevant canonical topology state in the
fingerprint. They do not require sending the whole graph to a future model.

## Initial rule semantics

Freeze a reviewable initial catalog before adding more rules:

- missing or multiple Entry nodes;
- unreachable nodes using valid directed connections plus supported in-flow
  virtual edges;
- isolated/disconnected nodes or branches;
- reachable non-terminal dead ends and required output pins without a valid
  connection;
- stale/missing jump, subflow, and exit references;
- invalid connection pins;
- orphan hubs: hubs with neither a valid incoming connection nor a valid
  in-flow jump target.

Reachability is topological, not symbolic condition evaluation:

- one Entry: traverse from that Entry;
- no Entry: emit the entry finding and do not claim that every node is
  unreachable;
- multiple Entries: emit the entry finding and traverse from all Entry nodes to
  avoid false unreachable claims;
- cycles are valid and traversal is cycle-safe;
- condition satisfiability and state-specific branch feasibility are not
  inferred.

“Character absent for a long stretch”, narrative-quality scoring, and any rule
without formal branch/cycle/span semantics remain out of scope.

## Analysis snapshots and lifecycle

The panel owns an explicit analysis snapshot:

- opening the panel or choosing **Rerun analysis** computes a fresh snapshot;
- a relevant flow mutation marks the open snapshot stale and offers rerun
  rather than silently merging old dispositions with new evidence;
- a finding is **resolved** when a fresh analysis no longer emits that
  occurrence. Resolve is derived, not a manual mutation;
- **Dismiss as false positive** is the only persisted manual disposition in v1;
- dismissal is project-shared, requires the relevant flow edit permission,
  records actor/time/reason, and is reversible;
- dismissal applies only to the exact
  `finding_key + rule_version + evidence_fingerprint`. A changed rule or changed
  evidence reactivates the finding;
- concurrent dismiss/restore requests are idempotent and uniqueness-constrained.

A dismissal reason code is required. An optional bounded note is project data:
it follows project authorization and never enters analytics, logs, or Slice-7.2
prompts.

## Permissions and isolation

- Viewing/rerunning analysis requires current project and flow read access.
- Dismissing/restoring requires the existing relevant content-edit permission.
- Every read and mutation derives workspace/project/flow from the authorized
  server subject, not from trusted client ids.
- Deleted/inaccessible entities cannot remain navigable evidence.
- A viewer can inspect and navigate but cannot change project-shared
  dispositions.

## Product surface

Use the existing right-panel shell in the normal flow editor:

- the toolbar health control becomes a compact summary/entry point rather than
  trying to fit the full lifecycle into its popover;
- the panel lists active and dismissed findings with category/severity filters;
- selecting a finding shows deterministic facts, limitations, and evidence;
- node evidence centers and highlights the node;
- current-flow connection evidence highlights only the referenced connection;
- cross-flow evidence uses an authorized verified route to the target flow;
- missing evidence is shown as stale and is never navigated by raw client URL.

V1 supports the normal flow editor. Compact/embedded/compare surfaces do not
duplicate the panel; they may link back to the normal editor when they have a
current authorized flow. This limitation must be explicit in UI tests and docs.

## Command palette

- Register the ordinary non-AI command **Analyze current flow** only where a
  current authorized flow subject exists.
- The command opens the analysis panel and may trigger a fresh deterministic
  snapshot.
- It never checks `:ai_integrations`, resolves a provider, consumes allowance,
  or creates an AI operation.
- Palette availability is presentation only; the panel reauthorizes the read.

## Observability

Record rule id/version, category, severity, count, duration, stale/rerun state,
navigation, and disposition outcome. Do not record story content, evidence
content, optional notes, or raw project/entity ids in analytics.

## Non-goals

- Any LLM explanation or provider call.
- Persisted “resolved” rows.
- Free-form story criticism or condition satisfiability.
- Automatic flow mutation.
- Multi-project or whole-project semantic analysis.
- Sharing/exporting an analysis report.

## Verification / Definition of Done

- ExUnit covers every initial rule across branches, cycles, deleted nodes,
  virtual jump edges, invalid pins, deterministic ordering, stable ids,
  evidence fingerprints, and explicit rule limitations.
- Editor and dashboard adapters cannot disagree about the same canonical rule.
- ExUnit covers cross-workspace/project isolation, owner/editor/viewer access,
  dismissal/restore, concurrent idempotency, rule-version/evidence reactivation,
  and stale snapshot behavior.
- Vitest/LiveView covers panel states, filters, active/dismissed findings,
  evidence navigation/highlighting, permissions, rerun, and stale state.
- Browser coverage exercises an editor and viewer, including the non-AI palette
  command.
- en/es product copy and user documentation explain deterministic findings,
  limitations, false-positive dismissal, and the absence of AI cost.
- `pnpm run fmt`, `just quality-lint`, relevant full suites, E2E, and
  `mix precommit` are green.

## Delivery

Branch `codex/slice7-1-deterministic-analysis` from current `main` → one PR →
merge before Slice 7.2. The PR must not register an AI task or remove the
invite-only AI docs gate.

If the frozen rule catalog cannot fit this PR, reduce the catalog; do not split
canonical finding/persistence semantics from the first usable panel.

## Inputs from previous slices

Slice 1 command palette · Slice 6 typed evidence/context boundary · current flow
serialization, permissions, `FlowStats`, `HealthChecker`, panel shell, and
analytics conventions.

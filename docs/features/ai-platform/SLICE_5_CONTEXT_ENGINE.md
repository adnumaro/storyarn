# Slice 5 — Context Engine v1 (Deterministic)

## Objective

A budget-bounded context builder that assembles, for any AI task, exactly the relevant slice of the project — via **explicit relations, not embeddings**: target entities → expansion through reference/graph queries → token-budgeted structured serialization. This is what makes fixed per-action credit prices financially safe.

## Problem & proposed solution

**Problem:** sending whole projects per request explodes cost and can degrade quality; fixed action prices are unsafe without bounded input. Generic RAG-over-prose rediscovers relations Storyarn already stores.
**Solution:** `Storyarn.AI.Context` pipeline: (1) task declares its scoping rule (**node / flow / sheet** — v1 scopes only; "arc" is deferred until an Arc relation exists in the model, do NOT invent one); (2) affected entities resolved; (3) expansion via the reference tables (sheet references, variable references, backlinks) and tree ancestry; (4) serialization into a compact structured format with a hard token budget (truncation strategy per entity type); (5) oversized entities fall back to lazily generated cached summaries (cheap tier, invalidated on entity update). Relations like `Scene A modifies trust` / `Choice B unlocks Scene C` are queried, never inferred.

## Architectural direction

- `Storyarn.AI.Context` submodule under the existing facade; pure read-only — never mutates project data.
- **Authorization contract**: `build_context/2` requires an authorized actor — it takes the caller's scope (user + project membership, viewer access minimum) and enforces it before resolving anything; it must be impossible to obtain another project's context by passing an arbitrary project id. The contract (enforce-inside vs. explicitly-pre-authorized caller) is stated in the module doc and covered by tests; the actor travels with the operation through any Oban worker boundary.
- Token estimation: estimate the **actual serialized payload** per entity type (conservative chars→tokens ratio on the serialized output), calibrated against provider tokenizer counts recorded by Slice-2 metering. `Shared.WordCount` is NOT a valid estimator here — it only counts dialogue/exit nodes and text/rich-text blocks and returns 0 for everything else; using it would let the hard budget be exceeded.
- Summaries: `ai_entity_summaries` table (entity_type, entity_id, summary, source_hash) with a **DB unique constraint on (entity_type, entity_id)** and an atomic get-or-create/single-flight strategy so concurrent cache misses cannot trigger two metered generations or persist duplicates; regenerate when `source_hash` mismatches; generation goes through `AI.execute` (cheap tier) so it is metered and budgeted like everything else. Concurrent-miss behavior is covered by tests.
- Serializer: share the export layer's **entity encoders** — but define a **bounded collector API** for the context scopes rather than reusing `Storyarn.Exports.DataCollector` loaders as-is: the export loaders preload whole parent entities and have no node-scoped filters, which defeats the budget. No parallel serializer implementations (project precedent: the canvas serializer is shared ×9 — extend via adapter, never duplicate); the boundary is "encoders shared, loaders purpose-built and bounded".

## Existing code to reuse (do not duplicate)

`Storyarn.Sheets.ReferenceTracker` · `Storyarn.Flows.VariableReferenceTracker` · derived reference tables (backlinks — rebuild via `References.rebuild_project_*`, never hand-insert; **scope reuse claims to the source types those rebuilds actually cover — verify coverage at implementation start**) · `Shared.TreeOperations` (ancestry/scoping) · export-layer **entity encoders** via `SerializerRegistry` (loaders purpose-built — see Architectural direction) · `Shared.HierarchicalSchema` · Slice-2 `AI.execute` for summary generation · fixtures in `test/support/fixtures/` for graph-shaped test data.

## Applicable conventions (MUST be surfaced in chat during implementation)

Facade-only exposure (`Storyarn.AI.build_context/2` via defdelegate) · read-only queries with soft-delete filters (`is_nil(deleted_at)`) ALWAYS · no new serializer if an adapter over exports suffices — justify in chat if deviation needed · preload strategy: aggressive single-query preloads for context assembly (avoid N+1, per Ecto conventions) · shared-utilities registry check before any helper.

## Observability & error handling

Context-build telemetry attached to the usage event: entities included, serialized size, truncations, **summary substitutions count** · **when summaries substitute oversized entities, the task result carries a visible indicator ("context summarized for N entities") — owner-decided: the mechanism is allowed but never silent** · scope impossible even after summaries → explicit error ("scope too large for this action"), no partial/silent context · summary generation failures are explicit task failures (metered), never skipped-and-continued.

## Verification / Definition of Done

- ExUnit: scoping per rule, expansion correctness on fixture graphs (references followed, unrelated entities excluded), token-budget truncation on serialized payloads, summary cache hit/miss + invalidation on `source_hash` change + **concurrent-miss single-flight**, soft-deleted entities excluded, **authorization: cross-project access rejected**.
- Integration: Slice-2 micro-task quality improves measurably with scoped context (assert context size bounds, not prose quality).
- No dedicated UI in this slice — verified through the Slice-2 task + a context-size debug assertion in tests. `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-context-engine` from main → PR → merge before Slices 6–8. Flag: inherits `:ai_integrations` (no new surface).

## Inputs from previous slices

Slice 2 merged (`AI.execute`, metering — summary generation must be metered; token counts for calibrating the estimator). Estimate: **10–14h**.

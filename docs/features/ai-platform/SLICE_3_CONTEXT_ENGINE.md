# Slice 3 — Context Engine v1 (Deterministic)

## Objective

A budget-bounded context builder that assembles, for any AI task, exactly the relevant slice of the project — via **explicit relations, not embeddings**: target entities → expansion through reference/graph queries → token-budgeted structured serialization. This is what makes fixed per-action credit prices financially safe.

## Problem & proposed solution

**Problem:** sending whole projects per request explodes cost and can degrade quality; fixed action prices are unsafe without bounded input. Generic RAG-over-prose rediscovers relations Storyarn already stores.
**Solution:** `Storyarn.AI.Context` pipeline: (1) task declares its scoping rule (node / flow / sheet / arc); (2) affected entities resolved; (3) expansion via the reference tables (sheet references, variable references, backlinks) and tree ancestry; (4) serialization into a compact structured format with a hard token budget (truncation strategy per entity type); (5) oversized entities fall back to lazily generated cached summaries (cheap tier, invalidated on entity update). Relations like `Scene A modifies trust` / `Choice B unlocks Scene C` are queried, never inferred.

## Architectural direction

- `Storyarn.AI.Context` submodule under the existing facade; pure read-only — never mutates project data.
- Token estimation: heuristic first (chars/words via `Shared.WordCount`), calibrated against provider tokenizer counts recorded by Slice-2 metering.
- Summaries: `ai_entity_summaries` table (entity_type, entity_id, summary, source_hash) — regenerate when `source_hash` mismatches; generation itself goes through `AI.execute` (cheap tier) so it is metered and budgeted like everything else.
- Serializer: REUSE the export data-collection layer rather than writing a parallel one — `Storyarn.Exports.DataCollector` + serializers already gather structured project data. Adapter over it; do NOT fork (project precedent: the canvas serializer is shared ×9 — extend via adapter, never duplicate).

## Existing code to reuse (do not duplicate)

`Storyarn.Sheets.ReferenceTracker` · `Storyarn.Flows.VariableReferenceTracker` · derived reference tables (backlinks — rebuild via `References.rebuild_project_*`, never hand-insert) · `Shared.TreeOperations` (ancestry/scoping) · `Storyarn.Exports.DataCollector` + `SerializerRegistry` · `Shared.WordCount` · `Shared.HierarchicalSchema` · Slice-2 `AI.execute` for summary generation · fixtures in `test/support/fixtures/` for graph-shaped test data.

## Applicable conventions (MUST be surfaced in chat during implementation)

Facade-only exposure (`Storyarn.AI.build_context/2` via defdelegate) · read-only queries with soft-delete filters (`is_nil(deleted_at)`) ALWAYS · no new serializer if an adapter over exports suffices — justify in chat if deviation needed · preload strategy: aggressive single-query preloads for context assembly (avoid N+1, per Ecto conventions) · shared-utilities registry check before any helper.

## Verification / Definition of Done

- ExUnit: scoping per rule, expansion correctness on fixture graphs (references followed, unrelated entities excluded), token-budget truncation, summary cache hit/miss + invalidation on `source_hash` change, soft-deleted entities excluded.
- Integration: Slice-2 micro-task quality improves measurably with scoped context (assert context size bounds, not prose quality).
- No dedicated UI in this slice — verified through the Slice-2 task + a context-size debug assertion in tests. `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-context-engine` from main → PR → merge before Slices 4–6. Flag: inherits `:ai_platform` (no new surface).

## Inputs from previous slices

Slice 2 merged (`AI.execute`, metering — summary generation must be metered; token counts for calibrating the estimator). Estimate: **10–14h**.

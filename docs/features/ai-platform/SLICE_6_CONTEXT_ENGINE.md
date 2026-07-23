# Slice 6 — Deterministic Context Engine v1

**Status:** implemented on `codex/slice6-context-engine`; PR in review.

## Objective

Build authorized, deterministic, task-specific context packages with hard size limits and an auditable manifest. V1 performs no hidden LLM summarization: it includes, truncates, or rejects content according to explicit task policy.

## Product decisions

- Context is assembled from Storyarn's structured graph, references, and facades; embeddings/RAG are not the default.
- Each task declares its context scope and budget. Callers cannot request “the whole project”.
- The final provider/model adapter enforces its own token/output limit in addition to a provider-neutral serialized-byte ceiling.
- Context ordering and exclusion are stable and explainable.
- Export-oriented whole-project loaders, including `Storyarn.Exports.DataCollector`, are never called by the context builder. Reuse is limited to bounded serializers/helpers that operate only on the already authorized, explicitly selected entity set.
- Project content is data, never executable instructions. Model output cannot invoke arbitrary tools.
- No cache miss may create an undisclosed second paid provider call.

## Context package contract

`build_context(current_scope, task, subject_ref)` returns:

- versioned structured payload;
- manifest of included/excluded entity ids and reasons;
- exact serialized byte size and optional tokenizer count;
- source revision/hash for every included entity;
- warnings such as truncation or stale references;
- stable context hash used by the operation.

Initial scopes:

- selected dialogue/response + speaker sheet summary fields;
- one flow/node neighborhood with explicit depth/fan-out;
- one sheet and explicitly referenced blocks/entities;
- one structural finding plus its evidence.

## Budgeting and precedence

Every task specifies maximum depth, fan-out, entity count, serialized bytes, and output allowance. Stable precedence is:

1. selected entity/content;
2. entities required to understand direct references;
3. task-specific supporting fields;
4. optional nearby context.

If required context alone exceeds the hard cap, return `:context_too_large` with a localized remediation; do not silently lower quality or drop required evidence. Optional content may be truncated only when the result discloses it through the manifest.

## Authorization and invalidation

- Context uses facades with the actor's current scope and never crosses workspace/project boundaries.
- Reauthorize before building and before applying a result.
- Result/proposal stores the context hash and relevant base revisions.
- Apply rejects stale source content rather than regenerating or applying silently.
- Soft-deleted and inaccessible entities are excluded according to their owning context rules.

## Future summaries

LLM-produced cached summaries are explicitly deferred. If later evidence requires them, they become registered operations with visible usage, provider/model/prompt versions, encrypted storage, explicit content-retention/deletion rules, and cost included in the parent task's fixed managed price. The first caller never pays a surprise surcharge for a shared cache miss.

## Existing code to reuse

`Storyarn.Flows`, `Sheets`, `Scenes`, `Screenplays`, `Localization`, and reference-tracker facades · graph traversal/health-check utilities · soft-delete scopes · bounded serialization helpers used by exports, but not `Storyarn.Exports.DataCollector` whole-project loaders · Slice-2 TaskRegistry/operations · existing authorization helpers.

## Non-goals

- Embeddings, vector database, semantic search, or broad RAG.
- Whole-project context.
- Hidden summary generation.
- Cross-workspace retrieval.
- Provider routing or pricing.

## Observability and error handling

- Record only counts, sizes, truncation flags, builder version, and hash in telemetry; never content.
- Classify unauthorized, missing, stale, oversized, and serialization failures.
- Result provenance states when optional context was truncated.

## Verification / Definition of Done

- ExUnit: deterministic ordering/hash, permission isolation, depth/fan-out/entity/byte caps, required-context rejection, optional truncation manifest, soft-delete behavior, stale revision detection, multilingual/tokenizer edge cases, and a large-project regression proving only the selected bounded entity set is loaded and `DataCollector` is never invoked.
- Property tests for budget invariants and stable serialization where practical.
- No provider call can occur when context construction fails.
- User-visible context disclosure component tested for truncation/warnings.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-context-engine-v1` from `main` → PR → merge before contextual generation tools. Flag applies only to AI-consuming surfaces; the builder itself is internal infrastructure.

## Inputs from previous slices

Slice 2 TaskRegistry/operation versions. Slices 3–5 provide managed/personal route metadata but do not control context contents.

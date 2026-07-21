# Slice 8 — Text → Storyarn Structure (import with diff preview)

## Objective

"Convert this text into Storyarn nodes/sheets": paste or select free text → the AI proposes a structured plan (characters as sheets, dialogue as flow nodes, choices as branches) → the user reviews a **diff preview** → applies transactionally. Loreweaver's core trick, but landing into deterministic, human-approved structure.

## Problem & proposed solution

**Problem:** onboarding friction — writers arrive with docs/scripts, and manual structuring is the highest-effort step of adoption. It is also the riskiest AI mutation: bulk creation across multiple entity types.
**Solution:** `AI.execute(:text_to_structure)` with a **strict structured-output schema** (entities + relations, validated server-side before anything is shown). The proposal is rendered as a creation plan (tree of would-be entities with diffs where they touch existing ones, e.g. matching an existing character by shortcut). Apply runs in one `Ecto.Multi` through the existing context facades; a project snapshot is taken before apply for one-click rollback.

## Architectural direction

- Output schema validated with existing changesets BEFORE preview: proposed names run through `Shortcuts` generators / `NameNormalizer`; collisions resolved or flagged in the preview, never silently.
- Two-phase like template import: create entities with nil cross-refs, then remap references (project precedent: never insert raw cross-entity FKs from external payloads — the snapshot-materialization lesson).
- Apply via facades only: `Sheets.create_sheet/2`, `Flows.create_flow/2`, node creation through `Flows` — zero direct Repo writes from the AI layer.
- Rollback: a project snapshot pre-apply **through the `Storyarn.Versioning` facade — `Versioning.create_project_snapshot/3` and `Versioning.restore_project_snapshot/3`** (`SnapshotBuilder` is an internal module with no project-snapshot API of its own; going through the facade keeps snapshot metadata and the restore-policy gates). "Undo import" restores that snapshot.
- Preview UI: reuse `AiProposalPanel` pattern from Slice 7, extended to tree-shaped proposals; per-item include/exclude checkboxes.
- Premium-tier task (large context, structured reasoning); price reflects it. Scope gating for Free tier (limits on input size), never quality degradation.

## Existing code to reuse (do not duplicate)

`Storyarn.Imports` parsers + idempotency patterns (reference for text→entities pipelines) · `Shared.NameNormalizer`, `Storyarn.Shortcuts`, `Shared.ShortcutHelpers` · `Shared.ImportHelpers` · context facades (`Sheets`, `Flows`) + their changesets · `Storyarn.Versioning` facade (`create_project_snapshot/3` / `restore_project_snapshot/3`) · `Ecto.Multi` patterns from existing CRUD · Slice-7 `AiProposalPanel` + acceptance telemetry · Slice-5 context (for matching against EXISTING entities) · `Billing.Limits` pattern for input-size caps.

## Applicable conventions (MUST be surfaced in chat during implementation)

Facades only, never submodules from web/AI layers · two-phase cross-ref remap (no raw FK inserts from generated payloads) · shortcut/slug generation exclusively via `Shortcuts`/`NameNormalizer` (duplicating them is a bug) · authorization `:edit_content` on apply · soft-delete-aware collision checks · all user-facing text i18n en/es · `validate_shortcut` from `Shared.Validations` on every proposed shortcut · surface in chat any place where the AI schema wants a field our changesets do not accept — adjust the schema, not the changeset.

## Verification / Definition of Done

- ExUnit: schema validation (malformed AI output rejected before preview), collision handling, two-phase remap correctness, Multi atomicity (partial failure = zero writes), snapshot-rollback path, input-size caps.
- Vitest: tree proposal preview, include/exclude, apply/dismiss emits.
- Browser: paste a real scene script → review → apply → verify entities, references, undo-import; acceptance telemetry.
- `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-text-to-structure` from main → PR → merge before Slice 11 pricing reads its telemetry. Flag: `:ai_integrations` (the single AI flag; the palette itself is unflagged).

## Inputs from previous slices

Slices 1, 2, 5 + Slice 7's proposal UX and acceptance schema. Estimate: **12–16h**.

# Slice 10 — Text → Storyarn Structure

## Objective

Convert bounded source text into a typed proposal of Storyarn entities/relationships, preview a dependency-aware diff, and apply it atomically through one authorized import facade. AI never writes directly and rollback never restores a stale whole-project snapshot over collaborators.

## Product flow

1. User supplies bounded text and selects the intended target/project scope.
2. UI shows lane, managed price or BYOK payer, input limits, and data scope.
3. AI returns a versioned intermediate schema with temporary ids only.
4. Structural schema parsing must succeed before preview.
5. Domain validation runs per item; invalid items are visible and block Apply unless their complete dependency component is excluded.
6. User reviews entities, collisions, references, include/exclude effects, and warnings.
7. Apply reauthorizes, checks project base revision, and executes a single transaction-aware facade command.

Generation requires both `:use_ai` and project `:edit_content`; preview never weakens the permission required for the eventual mutation.

## Proposal schema and limits

- Explicit caps for input bytes, entity count, relationship count, tree depth, fan-out, and output bytes.
- Temporary ids are remapped in two phases; model-generated database ids/foreign keys are forbidden.
- Existing-entity matches are suggestions with confidence/evidence and require confirmation; never merge silently.
- Names, shortcuts, field types, variables, and relationships use existing changesets/normalizers.
- Include/exclude is dependency-aware: excluding a parent either excludes dependants or blocks Apply with an explanation.

## Apply and rollback

- Introduce one facade entry point that builds the complete `Ecto.Multi`; existing CRUD functions are reused only through transaction-composable APIs.
- Apply requires `:edit_content`, current project membership, and unchanged base project revision/hash.
- Store an operation manifest of created/updated entities and prior values sufficient for a targeted inverse operation.
- Undo uses that manifest and its own revision guard. Do not restore an entire project snapshot over later collaborator changes.
- If a safe inverse is impossible because subsequent edits conflict, show an explicit manual-resolution state.
- Any apply failure writes zero domain changes; external side effects use durable compensation.

## Lanes and visibility

- Task may allow managed and personal BYOK with explicit choice; no silent switch.
- Personal BYOK resolves through the Slice-5.2 General assistant primary
  (`tasks`); Writing and media role preferences are not eligible.
- Managed price is fixed for a declared input/output size band. Oversize is rejected before reservation.
- If the managed allowance reservation fails because the allowance is
  exhausted, no provider attempt or operation starts. A compatible personal
  General-assistant route may be offered through an explicit **Use my own API
  key** CTA; selecting it shows BYOK data/billing disclosure, requires current
  task consent, and creates a separate personal operation. It never changes
  lane or payer automatically.
- BYOK shows provider billing and still obeys caps/rate limits.
- Proposal remains private until applied or deliberately shared.
- A valid generated proposal has `execution_status = succeeded`. Applying any non-empty valid subset sets `user_disposition = accepted`; discard-all sets `user_disposition = dismissed`; per-item choices are product events, not competing terminal outcomes.

## Command palette

`Convert text to Storyarn structure…` is a palette v2 `launch` command available only in an editable project. It routes to the dedicated import/proposal surface and creates no operation until text, target scope, lane, route, limits, and cost are confirmed. The palette never holds source text, proposal content, or transaction state.

## Existing code to reuse

Import parsers and two-phase remapping patterns · `Storyarn.Shortcuts`, name/validation/import helpers · Sheets/Flows/Scenes/Screenplays facades and changesets · Ecto.Multi and Versioning snapshot/revision patterns · Slice-2 operations/palette v2 · Slices 3–6 routing/context · Slice-8 proposal/diff patterns.

The targeted inverse manifest and guarded inverse executor are **new infrastructure owned by this slice**. They are intentionally narrower than project snapshots and must not be presented as an existing reusable project-wide undo primitive.

## Non-goals

- Arbitrary autonomous project construction.
- Whole-project overwrite or blind snapshot restore.
- Silent existing-entity merges.
- Partial writes after a failed transaction.
- Unlimited source/output size.

## Observability and error handling

- Record counts, size bands, lane/provider/model, validation categories, included/excluded counts, apply duration, and outcome without source/generated content.
- Distinguish malformed schema, domain-invalid item, dependency conflict, collision, stale project, permission, and transaction failure.
- Unknown/invalid model fields are rejected; changesets are not widened merely to accept generated output.

## Verification / Definition of Done

- ExUnit: caps, schema parsing, per-item validation, dependency selection,
  collisions, General-assistant route mapping, two-phase remap, single-Multi
  atomicity, revision guard, inverse manifest/undo, conflicting later edits, no
  cross-project ids, and no automatic managed-to-personal fallback.
- Vitest: tree diff, warnings, dependency include/exclude, lane/cost disclosure,
  explicit allowance-exhausted → BYOK consent flow, and
  apply/discard/stale states.
- Browser: generate a small scene proposal, review, apply, edit a created entity, and prove unsafe undo is blocked rather than overwriting the edit.
- User docs explain review, cost/provider, matching, apply, and undo limits.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-text-to-structure` from `main` → PR. Flag: `:ai_integrations` plus operational task switch.

## Inputs from previous slices

Slices 2–6 and Slice 8 proposal UX; existing import/versioning/facade contracts.

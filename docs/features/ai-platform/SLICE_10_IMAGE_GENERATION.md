# Slice 10 — Image Generation into Sheet Galleries (BYOK-only)

## Objective

Generate images (character portraits, concept art) directly into sheet **gallery blocks** — the owner-decided first landing spot — using the user's own key, restricted to providers with the capability (OpenAI, Google of the current six). Preview-then-save flow feeding acceptance telemetry; images stored through the existing Assets pipeline.

## Problem & proposed solution

**Problem:** visual reference assets are high-friction for narrative teams, but image inference is expensive and only some providers offer it — the internal credits lane is unviable for it (cost profile + capability), per the lane routing policy.
**Solution:** an image-capability extension of the provider abstraction, exposed only where the user has a capable key connected. From a gallery block: "Generate image" → prompt composed from the sheet's context (name, description, relevant blocks via Slice 3) + user's free-text direction → BYOK call → preview (not yet stored) → on accept, the image uploads through the `Storyarn.Assets` Storage facade into the gallery block (acceptance event); discard deletes nothing persistent.

## Architectural direction

- Uses the **capabilities model introduced in Slice 3**; `InferenceProvider` gains `generate_image/2` implemented ONLY for OpenAI and Google adapters. UI availability derives from connected-provider capabilities — a capability-specific CTA ("requires OpenAI or Google connected") otherwise. Provider selection: Illustrator assignment (Slice 4), else the user-marked default AI (if image-capable), else the CTA — no auto-pick.
- Lane: `byok_only` through Slice 3 (consent + provenance + no credit debit). Metering records the call with `lane` and image metadata (dimensions/count — never the image content in metering).
- Storage: preview is ephemeral (temp URL/data); persistence ONLY on accept, and **accept means creating a real `Asset` record, not just uploading bytes: `Storyarn.Assets.upload_binary_and_create_asset/4` (atomic upload+record lifecycle) followed by `Sheets.add_gallery_image/2`, with rollback compensation if the gallery link fails after the asset was created** — a direct `Storage` upload would leave orphaned objects the gallery cannot reference. The gallery block references the created asset like any manually uploaded one.
- Provider usage policies surfaced in the UI (link to the provider's content policy; generation errors from safety filters mapped to a clear message).

## Existing code to reuse (do not duplicate)

`Storyarn.Assets` facade + `Storage` (R2/local) + `ImageProcessor` · gallery block components (sheets) + `BlockComponents` · Slice-3 BYOK lane + consent + badges · Slice-4 `provider_for/2` (Illustrator assignment) · Slice-5 context (sheet scope) · Slice-7/9 acceptance-event schema · upload plumbing patterns (multipart/attach events) · `FeatureFlags` · gettext/i18n infra.

## Applicable conventions (MUST be surfaced in chat during implementation)

Storage ONLY through the `Assets`/`Storage` facade (deletion-safety checks live there — project rule) · authorization: `:edit_content` on generate/save events · i18n en/es · Lucide icons · block architecture respected (gallery block owns the UI entry; no bespoke panels) · metering stores counts/cost only, never image content · component registry check before new components.

## Observability & error handling

Generation telemetry (count, dimensions, latency — never image content) · safety-filter rejections map to an explicit, human message (provider policy linked) — no re-prompting or silent retry · asset-creation/link failure = compensation (no orphaned storage) + explicit error; the preview is never lost on failure · accept/discard to PostHog (acceptance signal) · user docs: image generation into galleries documented in the flag-hidden AI docs.

## Verification / Definition of Done

- ExUnit: capability gating (non-capable providers rejected), `byok_only` enforcement, accept path creates the `Asset` record via `upload_binary_and_create_asset/4` + links the block via `add_gallery_image/2` (rollback compensation on link failure — no orphaned storage objects), discard persists nothing, safety-filter errors mapped.
- Vitest: gallery generate flow (prompt input, preview, accept/discard), capability CTA state.
- Browser: real OpenAI or Google key — generate a portrait into a character sheet gallery, verify asset in storage and provenance badge.
- Lint fix as last command before push · `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-image-generation` from main → PR. Flag: `:ai_integrations` (the single AI flag).

## Inputs from previous slices

Slices 3, 4, 5 merged. Estimate: **10–14h**.

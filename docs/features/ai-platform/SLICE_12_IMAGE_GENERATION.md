# Slice 12 — Image Generation into Sheet Galleries

## Objective

Generate one private image preview from a sheet gallery block using a capable personal BYOK model, then persist it through the Assets pipeline only after explicit acceptance.

## V0 scope

- One image per operation.
- Personal BYOK only; explicit provider/model selection through the Illustrator preference or invocation UI.
- Gallery blocks are the only destination.
- Prompt combines bounded, disclosed sheet fields from Slice 6 with the user's explicit direction.
- Private temporary preview with accept/dismiss/regenerate.
- Accepted preview becomes a real Asset linked through the existing gallery mutation path.

## Modality and capability contract

- Add a modality-specific `ImageProvider.generate/2`; do not overload text or speech behaviours.
- Capability is curated/versioned per provider+model and validated at runtime; a connected key or model listing alone is insufficient.
- No first-capable auto-pick and no Storyarn AI fallback.
- Safety/capability/permission 403s do not revoke an otherwise valid key.

## Temporary media boundary

- Provider URLs are fetched server-side only through strict scheme/host resolution policy, timeouts, redirect limits, private-network denial, byte/dimension caps, and streaming limits.
- Base64 responses are decoded under equivalent size caps server-side and never sent through LiveView.
- Validate magic bytes/MIME, dimensions, decompression limits, and remove unsafe metadata/EXIF before preview/persistence.
- Store preview privately with authorized URL and 24-hour TTL; dismiss/expiry cleans it durably.
- Metering contains metadata only, never prompt/image content.

## Accept contract

- Reauthorize project/gallery edit permission and verify the source/context revision.
- Create the permanent Asset through `Storyarn.Assets.upload_binary_and_create_asset/4`.
- Link it through the Sheets gallery facade.
- Record AI provenance: operation, actor, lane, provider/model, dimensions, source/config hashes.
- Compensate the Asset/storage object if gallery linking fails; concurrent accept creates at most one link/asset.
- A valid generated preview has `execution_status = succeeded`. Accept sets `user_disposition = accepted`; discard sets `user_disposition = dismissed`; preview rendering is not acceptance.

## Command palette and UI

The primary affordance lives in the gallery block. A contextual `Generate gallery image…` command uses palette v2 `launch` to open the same preview flow without creating an operation. The surface requires the current gallery, `:use_ai` plus `:edit_content`, egress policy, consent, and image-capable personal route, then shows provider billing/data scope and confirms direction/model before generation.

## Existing code to reuse

`Storyarn.Assets`/Storage/ImageProcessor/StorageCompensation · gallery block and Sheets facades · Slice-2 operations/palette v2 · Slice-4 BYOK/consent · Slice-5 capability/preferences · Slice-6 context · existing upload/player/dialog patterns.

## Non-goals

- Managed Storyarn AI allowance for images.
- Multi-image batches, editing/inpainting, persistent prompt history, arbitrary asset destinations, or automatic save.
- Treating provider URLs/content as trusted.

## Observability and error handling

- Record dimensions/bytes, provider/model, latency, safety classification, cleanup/compensation, and disposition without prompt/image content.
- Provider safety rejection, capability denial, hostile/invalid media, storage, stale source, and gallery-link failure are distinct localized states.
- No automatic re-prompt or retry.

## Verification / Definition of Done

- ExUnit: model capability gating, BYOK/no-ledger, consent/policy, SSRF/private-network/redirect/size/MIME/dimension/EXIF defenses, temporary expiry, accept Asset+gallery+provenance, concurrent accept, compensation and stale source.
- Vitest: gallery generation, disclosure, loading/preview, accept/dismiss/regenerate, classified errors and palette availability.
- Browser with real allowlisted provider: generate and accept one portrait, verify permanent Asset and cleanup of discarded preview.
- User docs cover provider cost, policies, temporary preview, and persistence.
- `just quality-lint` and full relevant suites green.

## Delivery

Branch `feat/ai-image-generation` from `main` → PR. Roll out behind `:ai_integrations` plus task/provider switches.

## Inputs from previous slices

Slices 2, 4, 5, and 6 plus Assets/gallery contracts. Scratch-VO temporary-media primitives should be reused if Slice 9 lands first.

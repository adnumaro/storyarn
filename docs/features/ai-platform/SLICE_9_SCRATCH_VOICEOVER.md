# Slice 9 — Multilingual AI Scratch Voice-Over

## Objective

Generate an AI audition for one translated dialogue/response, let the user listen, and only on explicit acceptance attach it as localized voice-over with status `recorded`. Position this as scratch VO for prototyping, pacing, and localization QA — not professional dubbing or actor replacement.

## V0 scope

- One active `LocalizedText` target-locale row per operation.
- `vo_eligible == true`, non-empty translated text, valid source, and both `:use_ai` and project `:edit_content` permission.
- V0 requires `vo_asset_id == nil` and `vo_status in ["none", "needed"]`. It never replaces a recorded/approved/stale retained voice-over; the user must remove the existing VO through the normal audited workflow first.
- Target locales only; source-language `data["audio_asset_id"]` asymmetry remains out of scope.
- Initial implementation target: an OpenAI `/v1/audio/speech` adapter for the
  reviewed [`tts-1`](https://developers.openai.com/api/docs/models/tts-1) and
  [`tts-1-hd`](https://developers.openai.com/api/docs/models/tts-1-hd) entries
  using the actor's personal BYOK connection. The UI presents the speed/quality
  trade-off and never substitutes one for the other silently.
- Curated catalog voices only; explicit provider/model/voice selection.
- MP3-normalized private preview with play, accept, dismiss, and explicit regenerate.
- Main surface: localization editor; contextual palette command `Generate scratch voice-over` uses palette v2 `launch` and creates no operation until its provider/model/voice preflight is confirmed.
- Accepted audio becomes a real Asset, `LocalizedText.vo_asset_id` is updated, and `vo_status` becomes `recorded`, never `approved`.

## Task and provider contracts

Register `:scratch_voiceover` with capability `:speech`, lane `personal_byok` only, exact-entity context, one-line/character caps, temporary-audio output, async execution, and no scheduled/bulk execution.

Slice 5.2 already exposes reviewed speech entries as selectable preferences
whose `implementation_status` is `configuration_only`. Promote each exact
provider/model entry implemented here to `implementation_status = executable`
and advertise it in provider metadata only after the speech adapter and that
entry's runtime contract pass integration tests. Other speech entries, including
Google
[`gemini-3.1-flash-tts-preview`](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-tts-preview),
remain configuration-only until their own adapter is implemented. Add a
versioned, adapter-owned catalog of supported voice ids, locales, and output
formats; `GET /models` is neither a voice catalog nor proof that the account can
call speech.

OpenAI is an implementation target, not an assumption. Before real-provider work starts, the owner must approve a current provider review covering target-language quality, voice/catalog stability, API access, output formats, regional processing, data retention/training terms, acceptable-use/disclosure requirements, and account eligibility. If the review fails, stop this slice and select a different initial provider explicitly; do not substitute one at runtime.

Do not put binary audio through the text inference behaviour. Add `Storyarn.AI.SpeechProvider.synthesize/2` with:

- normalized request: speakable text, locale, model, voice, output format, allowlisted instructions;
- result: audio binary/stream, MIME, optional duration, character usage, sanitized provider request id;
- classified errors for credential, capability, locale/model/voice, rate limit, safety, timeout, invalid audio, and provider failure.

Capability is validated at provider **and model/voice/locale** level. A model listing alone does not prove speech access.

Ship a deterministic fake speech adapter and a small valid MP3 fixture before enabling the real adapter. Contract tests must exercise both successful audio and malformed/non-audio responses without requiring a paid API call.

## Speakable text

Create a pure localized-text renderer that:

- converts supported markup to the exact displayed spoken text;
- preserves meaningful punctuation and normalizes whitespace;
- excludes speaker name, stage directions, and unrelated context;
- rejects ambiguous runtime placeholders rather than inventing pronunciation;
- returns warnings, character count, and deterministic input hash.

The confirmation UI shows exactly this rendered text. Slice-6 context and other project content are not used.

## Preview and persistence

- Temporary storage is private, project/operation-scoped, served by authorized signed URL/endpoint, and expires after 24 hours.
- Never send base64 audio through LiveView or keep large binaries in assigns.
- Validate magic bytes, MIME, and size before exposing the preview.
- Dismiss/expiry deletes temporary media through durable cleanup/compensation.
- Accept reauthorizes, locks the generation, reloads the localized text, compares source/input/revision hashes, rechecks that no VO asset now exists, and rejects stale audio or a concurrent human/recorded VO.
- Accept materializes the preview through `Storyarn.Assets.upload_binary_and_create_asset/4`, links `vo_asset_id`, sets `recorded`, records provenance, and compensates storage/asset on link failure.
- Concurrent accepts create at most one accepted Asset.
- Valid audio completes with `execution_status = succeeded`. Accept sets `user_disposition = accepted`; explicit dismiss or regenerate sets `user_disposition = dismissed` (regenerate reason: `regenerated`); expiry without a decision sets `user_disposition = abandoned`. Technical failure never receives a human disposition.

Provenance includes AI origin, operation id, actor, lane, provider, model, voice id, locale, input/configuration hashes, and generation time — never text, prompt, or key.

## UX and consent

Before generate, show locale, exact spoken text, character count, draft warning, provider/model/voice, `{Provider} · your key`, external-billing notice, and that an accepted asset becomes shared project data.

Consent is capability-scoped to speech and the workspace must allow personal BYOK. No fallback to Storyarn AI or another personal provider.

## Export contract

- Preserve current export semantics: `recorded` may appear in preview exports; release requires human `approved`.
- Translation edits continue to mark VO stale/needed, preventing release of outdated audio.
- Verify existing Unity and Storyarn JSON behavior; new exporter support is non-scope.

## Existing code to reuse

`Storyarn.Localization.LocalizedText`, `SourceContract`, `TextCrud`, `ExportPolicy`, and reports · `Storyarn.Assets.upload_binary_and_create_asset/4`, BlobStore/StorageCompensation · existing audio/player and localization UI · Unity/Storyarn serializers · Slice-2 operations/palette v2 · Slice-4 BYOK/consent · Slice-5 capability catalog.

## Non-goals

- Batch generation, persistent casting, pronunciation dictionaries, SSML, source-language generation, table reads, timings/visemes/lip-sync, professional mastering, new exporters, managed Storyarn AI allowance, custom/voice cloning, or automatic approval/regeneration.

## Observability and error handling

- Store character count, duration/bytes, provider/model/voice, lane, latency, classified status, and product disposition — never spoken text/audio in metering.
- Regenerate dismisses the previous preview with reason and starts a new operation.
- Preview rendered is `viewed`, not `accepted`.
- Monitor invalid-audio responses, cleanup backlog, storage compensation, stale-at-accept, and cost per accepted minute when reliable pricing exists.

## Verification / Definition of Done

- Unit: speakable renderer, placeholders, hashes, catalog validation, audio signature/MIME/size, filename, transitions.
- ExUnit: project/permission/eligibility checks, existing `vo_asset_id` and recorded/approved VO blocked at generate and accept, no approval downgrade, explicit provider/no fallback, speech consent, zero allowance-ledger writes, narrow 401/403 handling, idempotency, private preview/expiry, accept Asset+VO+provenance, concurrent accept, stale rejection, compensation/cascade, content-free telemetry.
- Vitest/LiveView: dialog disclosures, provider/voice selection, async restore, player, accept/dismiss/regenerate, errors, palette availability, forged-id rejection.
- Browser with an allowlisted real OpenAI beta key after the provider-review gate: generate Spanish target VO, accept, verify preview export, confirm release exclusion until human approval, edit translation and verify stale/needed behavior.
- `mix precommit`, JS tests, E2E fake-provider flow, and full quality gate green.

## Delivery

Branch `feat/ai-scratch-voiceover` from `main` → PR. Roll out fake provider → approved OpenAI adapter → staff dogfood → allowlisted beta. Gate with `:ai_integrations` plus operational task/provider switches. No real-provider code is enabled until the provider-review gate above is recorded.

## Inputs from previous slices

Slices 0–5.2 and existing Localization/Assets/export contracts. Dialogue proposal UX may inspire the audio preview but is not a hard dependency. Context Engine is explicitly not used.

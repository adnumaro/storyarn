# Slice 0 — BYOK Provider Integrations + Feature-Flag Foundation

**Status: merged (PR #28).** Documented retroactively; this doc is the reference for what later slices inherit.

## Objective

Users connect their own AI provider accounts via API key (BYOK) in Account Settings, with keys encrypted at rest, validated before persisting, auditable, and revocable — all behind a per-user feature flag. Provide the provider abstraction and feature-flag infrastructure every later slice builds on.

## Problem & proposed solution

**Problem:** "user-paid AI" originally meant OAuth (Linear-style), but Slice-0 research found no viable consumer OAuth path for third-party inference across the three major providers evaluated in 2026. The source review and citations shipped in `docs/features/ai-integrations/PROVIDERS.md` with PR #28.
**Solution:** BYOK for **seven providers** — six LLM providers (Anthropic, OpenAI, Google/AI-Studio, Kimi/Moonshot, Mistral, DeepSeek) plus DeepL (translation-only, see scope addition below) — with a Linear-quality card grid, validate-before-persist, Cloak encryption, append-only audit, and `fun_with_flags` for gradual rollout.
**Scope addition shipped in PR #28:** a seventh card — **DeepL** (`metadata` with capability `[:translation]`, `validate_key/1` against `/v2/usage`, free/pro endpoint handling). Only the adapter + card live here; replacing shared localization configuration with a personal credential is explicitly deferred by the rewritten platform plan.

## Architectural direction (as shipped)

- `Storyarn.AI` facade → `IntegrationCrud` / `Providers` registry / `Provider` behaviour (`metadata/0`, `validate_key/1`) / shared `KeyValidation` HTTP plumbing (Req, test-injectable via `req_options` app env) / `Audit` (whitelist-sanitized metadata, `actor_id` snapshot, DB trigger append-only) / `Runtime.with_personal_integration/3` (key checkout: decrypted key in closure, `last_used_at`, auto-revoke on `:unauthorized`, telemetry span `[:ai, :integration, :call]`).
- Deliberately **no completions API**: the first real consumer (Slice 2) defines that shape.
- `Storyarn.FeatureFlags` wrapper + `FunWithFlags.Actor` impl for `User` (`"user:{id}"`), Ecto persistence, PubSub cache-bust.
- Revocation = conditional `UPDATE … WHERE revoked_at IS NULL` (idempotent under concurrency, exactly one audit row).
- Vue: `IntegrationsPage` grid + `ConnectKeyDialog` + sequence tokens guarding stale LiveView replies.

## Existing code reused (registry check honored)

`Storyarn.Shared.EncryptedBinary` (Cloak) · `Shared.TimeHelpers` · `Storyarn.RateLimiter` (added `check_ai_integration_connect/1` bucket) · `SettingsLayout` + settings LV patterns · `ConfirmDialog.vue` · `PasswordInput.vue` · shadcn `ui/dialog`, `ui/button`, `ui/label` · Req (already a dep) + `Req.Test` for stubs · gettext/i18n infra.

## Conventions applied (surfaced during implementation)

Facade + `defdelegate` (no direct submodule calls from web) · CRUD module template · changesets per operation · `dgettext("integrations", …)` + `locales/{en,es}/integrations.json` · Lucide icons only · no browser-native dialogs · authorization: settings LV scoped to `current_scope.user`, all queries user-scoped · LiveVue nested props stay snake_case on the wire · `data-live-link-exempt` for external hrefs · migrations verified against dev DB via `information_schema` after in-place edits.

## Observability & error handling (as shipped)

Telemetry span `[:ai, :integration, :call]` · append-only audit trail (connect/disconnect/validation_failed/auto_revoked) · validation errors classified (`:invalid_key | :network_error | :rate_limited | :provider_error | {:unexpected_status, n}`) → i18n error states in the connect dialog · `retry: false` on validation calls (no automatic retries) · no fallbacks anywhere: a failed validation is an explicit rejected connect.

## Verification (done)

65 ExUnit (adapters w/ Req.Test, CRUD, LiveView, Runtime, audit trigger) · 615 Vitest (incl. dialog-race tests) · `just quality-lint` green · cubic review: 9/9 issues fixed, threads resolved. Browser verification covered the integrations grid; the shipped surface now contains seven providers including DeepL.

## Delivery

- Branch `feat/ai-integrations` → **PR #28 merged**. Flag `:ai_integrations` (disabled by default).
- Remaining security/polish debt — especially sudo mode for credential mutations, E2E, and explanatory copy — must close before broad Slice-4 BYOK rollout.

## Hand-off to later slices

Slice 2 consumes the facade, feature flag, audit/telemetry, and testing conventions while keeping connectable providers separate from inference providers. Slice 4 consumes `Runtime.with_personal_integration/3` for actor-owned personal BYOK. Slice 5 keeps the personal Translator role hidden until an executable personal translation task exists; the legacy shared localization configuration is not removed.

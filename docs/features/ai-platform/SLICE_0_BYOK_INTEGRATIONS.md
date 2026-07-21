# Slice 0 — BYOK Provider Integrations + Feature-Flag Foundation

**Status: implemented — merge pending (PR #28, `feat/ai-integrations`).** Documented retroactively; this doc is the reference for what later slices inherit. Nothing described here exists on `main` until PR #28 merges.

## Objective

Users connect their own AI provider accounts via API key (BYOK) in Account Settings, with keys encrypted at rest, validated before persisting, auditable, and revocable — all behind a per-user feature flag. Provide the provider abstraction and feature-flag infrastructure every later slice builds on.

## Problem & proposed solution

**Problem:** "user-paid AI" originally meant OAuth (Linear-style), but Slice-0 research proved all three major providers closed consumer OAuth for third-party inference in 2026 (Anthropic ToS Feb-2026 + backend blocks; OpenAI partnership-only; Google Vertex-only with heavy friction). Full citations: `docs/features/ai-integrations/PROVIDERS.md` — **ships with PR #28, not on `main` until merge**; until then read it in the PR diff.
**Solution:** BYOK for six providers (Anthropic, OpenAI, Google/AI-Studio, Kimi/Moonshot, Mistral, DeepSeek) with a Linear-quality card grid, validate-before-persist, Cloak encryption, append-only audit, and `fun_with_flags` for gradual rollout.

## Architectural direction (as shipped)

- `Storyarn.AI` facade → `IntegrationCrud` / `Providers` registry / `Provider` behaviour (`metadata/0`, `validate_key/1`) / shared `KeyValidation` HTTP plumbing (Req, test-injectable via `req_options` app env) / `Audit` (whitelist-sanitized metadata, `actor_id` snapshot, DB trigger append-only) / `Runtime.with_integration/3` (key checkout: decrypted key in closure, `last_used_at`, auto-revoke on `:unauthorized`, telemetry span `[:ai, :integration, :call]`).
- Deliberately **no completions API**: the first real consumer (Slice 2) defines that shape.
- `Storyarn.FeatureFlags` wrapper + `FunWithFlags.Actor` impl for `User` (`"user:{id}"`), Ecto persistence, PubSub cache-bust.
- Revocation = conditional `UPDATE … WHERE revoked_at IS NULL` (idempotent under concurrency, exactly one audit row).
- Vue: `IntegrationsPage` grid + `ConnectKeyDialog` + sequence tokens guarding stale LiveView replies.

## Existing code reused (registry check honored)

`Storyarn.Shared.EncryptedBinary` (Cloak) · `Shared.TimeHelpers` · `Storyarn.RateLimiter` (added `check_ai_integration_connect/1` bucket) · `SettingsLayout` + settings LV patterns · `ConfirmDialog.vue` · `PasswordInput.vue` · shadcn `ui/dialog`, `ui/button`, `ui/label` · Req (already a dep) + `Req.Test` for stubs · gettext/i18n infra.

## Conventions applied (surfaced during implementation)

Facade + `defdelegate` (no direct submodule calls from web) · CRUD module template · changesets per operation · `dgettext("integrations", …)` + `locales/{en,es}/integrations.json` · Lucide icons only · no browser-native dialogs · authorization: settings LV scoped to `current_scope.user`, all queries user-scoped · LiveVue nested props stay snake_case on the wire · `data-live-link-exempt` for external hrefs · migrations verified against dev DB via `information_schema` after in-place edits.

## Verification (done)

65 ExUnit (adapters w/ Req.Test, CRUD, LiveView, Runtime, audit trigger) · 615 Vitest (incl. dialog-race tests) · `just quality-lint` green · cubic review: 9/9 issues fixed, threads resolved. Browser-verified by owner (6-card grid).

## Delivery

- Branch `feat/ai-integrations` → **PR #28** against main. Flag `:ai_integrations` (disabled by default).
- **Slice 6 of the original mini-plan is still pending** (sudo mode, visual polish, copy review, E2E Playwright, "Why an API key?" note) — folded into this platform plan as polish debt, to schedule after Slice 2.

## Hand-off to later slices

Slice 2 consumes: `Providers` registry (internal provider = one more adapter), `Runtime.with_integration/3` (BYOK lane), `Audit`, `FeatureFlags`, telemetry event naming, Req.Test config pattern. **PR #28 must be merged before Slice 2 starts.**

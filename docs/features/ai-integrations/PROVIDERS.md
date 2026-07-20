# AI Integrations — Provider Reference

Internal reference for the AI Integrations feature. Covers the six providers targeted for v1 and the authentication decisions behind them.

## Model: BYOK (Bring Your Own Key)

All v1 providers use **user-supplied API keys**, not OAuth. This is the deliberate outcome of Slice 0 research (2026-07-20).

### Why not OAuth

We investigated OAuth for the three consumer platforms most users would expect (Anthropic, OpenAI, Google). All three ruled it out for third-party SaaS in 2026:

| Provider         | OAuth status                                                                                                                                                                                                                                                                                                                                                                                             | Source                                                                                                                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Anthropic Claude | Consumer OAuth banned for third-party apps (Feb 2026 ToS update). No public client registration. Approved partners (OpenClaw, Conductor, Zed) are a closed group with no application form.                                                                                                                                                                                                               | `code.claude.com/docs/en/authentication`, `platform.claude.com/docs/en/manage-claude/authentication`, coverage in The Register, VentureBeat, Gigazine (Feb–Jun 2026)                         |
| OpenAI           | Codex OAuth uses OpenAI-owned `client_id` hardcoded in `openai/codex`; no self-service registration. "Sign in with ChatGPT" is identity-only preview, does not grant API scopes. Third parties using the Codex flow (Cline, OpenClaw) did so via undisclosed partnerships.                                                                                                                               | `openai/codex` Rust source (`codex-rs/login/`), `developers.openai.com/codex/auth`, community.openai.com discussions                                                                         |
| Google Gemini    | Technically possible via Vertex AI + `cloud-platform` scope + `X-Goog-User-Project` header, but requires: (1) user owns a GCP project with billing enabled and Vertex AI API activated (high bar), (2) Google verification of our OAuth client (sensitive scope, 10 business days official, 2–12 weeks reported), (3) fragile per-call billing plumbing. AI Studio consumer keys are the pragmatic path. | `ai.google.dev/gemini-api/docs/oauth`, `cloud.google.com/vertex-ai/docs/authentication`, `developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification` |

The industry pattern in 2026 is BYOK for third-party wrappers. Cursor, Continue, Aider, Zed, and most narrative-focused tooling follow the same model.

### When we might revisit OAuth

- **Google Vertex AI OAuth**: worthwhile if we onboard an enterprise customer already operating on GCP. Deferred to backlog.
- **Anthropic partner OAuth**: if Anthropic opens a public program (unlikely near-term) or we get partner status.
- **"Sign in with ChatGPT" (API scopes)**: if OpenAI ships the API-access variant out of preview.

## Provider reference

Each provider entry documents what Slice 1–4 adapters need. Where a value is marked `VERIFY`, confirm during that provider's adapter work — Slice 0 research covered high-level viability, not every endpoint detail.

### Anthropic Claude

- **Get key**: https://platform.claude.com/settings/keys
- **Key format**: `sk-ant-api03-...` (Console keys). Distinct from `sk-ant-oat01-*` OAuth tokens (rejected by API since Feb 2026).
- **Base URL**: `https://api.anthropic.com`
- **Auth header**: `x-api-key: <KEY>`
- **Required additional headers**: `anthropic-version: 2023-06-01` (may bump — VERIFY latest recommended value at implementation time)
- **Validation endpoint** (cheap, non-billing): `GET /v1/models` → 200 with model list on valid key, 401 on invalid.
- **Account info endpoint**: none public. Display strategy: masked key (`sk-ant-...abcd` using `key_last_four` column).
- **Billing model**: pay-as-you-go on Console account, separate from Pro/Max subscription.
- **User docs to link from Connect dialog**: https://docs.claude.com/en/api/getting-started

### OpenAI

- **Get key**: https://platform.openai.com/api-keys (user must first create a project if none exists)
- **Key format**: `sk-...` or `sk-proj-...` (project-scoped keys).
- **Base URL**: `https://api.openai.com`
- **Auth header**: `Authorization: Bearer <KEY>`
- **Validation endpoint**: `GET /v1/models` → 200 with model list on valid key, 401 on invalid.
- **Account info endpoint**: `GET /v1/organization` (VERIFY availability + shape at implementation time). Fallback: masked key.
- **Billing model**: pay-as-you-go on OpenAI Platform, separate from ChatGPT Plus/Pro subscription.
- **User docs to link**: https://platform.openai.com/docs/api-reference/authentication

### Google Gemini (via AI Studio)

- **Get key**: https://aistudio.google.com/apikey
- **Key format**: `AIza...` (standard Google API key)
- **Base URL**: `https://generativelanguage.googleapis.com`
- **Auth**: `x-goog-api-key: <KEY>` header. Google also accepts `?key=<KEY>` as query param, but the header keeps the key out of URLs (proxy/access logs) — decided in Slice 3.
- **Validation endpoint**: `GET /v1beta/models` → 200 with model list on valid key, **400** (`API_KEY_INVALID`) or 403 on invalid. Note: 400, not 401 — the adapter overrides the shared classification for this.
- **Account info endpoint**: none. Display strategy: masked key.
- **Billing model**: free tier available; paid via Google Cloud billing account attached to the AI Studio project.
- **User docs to link**: https://ai.google.dev/gemini-api/docs/api-key
- **Note**: This is the AI Studio path, NOT Vertex AI. Vertex OAuth remains in backlog.

### Kimi (Moonshot)

- **Get key**: https://platform.moonshot.ai/console/api-keys
- **Key format**: `sk-...` (OpenAI-style)
- **Base URL**: `https://api.moonshot.ai` (VERIFY — some docs use `api.moonshot.cn` for China region; likely need region selection)
- **Auth header**: `Authorization: Bearer <KEY>`
- **Validation endpoint**: `GET /v1/models` (OpenAI-compatible)
- **Account info endpoint**: none confirmed. Masked key.
- **Notes**: Fully OpenAI-compatible API. Cheapest path in Slice 4 — reuse OpenAI adapter shape.
- **User docs to link**: https://platform.moonshot.ai/docs

### Mistral

- **Get key**: https://console.mistral.ai/api-keys
- **Key format**: opaque token
- **Base URL**: `https://api.mistral.ai`
- **Auth header**: `Authorization: Bearer <KEY>`
- **Validation endpoint**: `GET /v1/models`
- **Account info endpoint**: none confirmed. Masked key.
- **User docs to link**: https://docs.mistral.ai/getting-started/quickstart/

### DeepSeek

- **Get key**: https://platform.deepseek.com/api_keys
- **Key format**: `sk-...` (OpenAI-style)
- **Base URL**: `https://api.deepseek.com`
- **Auth header**: `Authorization: Bearer <KEY>`
- **Validation endpoint**: `GET /models` (note: no `/v1` prefix on some routes — VERIFY)
- **Account info endpoint**: `GET /user/balance` returns remaining balance in USD (useful for UX later, not for v1 validation).
- **Notes**: OpenAI-compatible.
- **User docs to link**: https://api-docs.deepseek.com/

## Common security requirements (all providers)

- **Storage**: `api_key_encrypted` column via `Storyarn.Shared.EncryptedBinary` (Cloak).
- **Never in logs**: implement `Inspect` protocol on `AI.Integration` schema that redacts `api_key_encrypted`. Do not log the struct raw anywhere.
- **Display**: only ever show `key_last_four` (last 4 chars of the plaintext key, captured at connect time and stored non-encrypted for display).
- **Validation before persist**: on Connect, do a validation call to the provider's `models` endpoint. If it fails, reject with a clear error. Never store an unvalidated key.
- **Revocation detection**: when the runtime API (Slice 5) receives 401/403 from a provider, mark the integration `revoked_at = now()` and surface a "Reconnect" prompt in the UI.
- **Rate limit on Connect**: 3 attempts / minute / user (Hammer or `:ets` counter) to avoid brute-force attempts against pasted-key validation.
- **Audit trail**: every connect / disconnect / validation-failure / auto-revoke event → `ai_integration_audits` row (no key material stored in the audit).

## Non-goals for v1

- No usage metering / cost estimation (defer until we have a real consumer in Slice 5+).
- No key rotation reminders.
- No multi-key-per-provider (one active integration per user per provider).
- No workspace-shared keys.
- No Vertex AI OAuth (backlog).

## References — full research transcripts

Slice 0 spawned three research agents; their full reports (with citations) are captured in the conversation history where this feature was designed. Key primary sources:

- Anthropic: `code.claude.com/docs/en/authentication`, `platform.claude.com/docs/en/manage-claude/authentication`, `github.com/anthropics/claude-code`
- OpenAI: `developers.openai.com/codex/auth`, `github.com/openai/codex/tree/main/codex-rs/login`, `platform.openai.com/docs/api-reference/authentication`
- Google: `ai.google.dev/gemini-api/docs/api-key`, `ai.google.dev/gemini-api/docs/oauth`, `cloud.google.com/vertex-ai/docs/authentication`

Manual verification recommended before shipping:

1. Anthropic Consumer Terms clause on OAuth (`anthropic.com/legal/consumer-terms`) — WebFetch was denied to the research agent; wording was cross-referenced from 6+ secondary reports.
2. Latest `anthropic-version` header value.
3. Kimi region (`.ai` vs `.cn`) — user-selectable or default one region.
4. DeepSeek base URL prefix conventions (`/v1` vs no prefix).

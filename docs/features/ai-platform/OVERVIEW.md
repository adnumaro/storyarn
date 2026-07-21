# AI Platform — Overview & Slice Plan

Storyarn's AI strategy: **credits-included default AI + BYOK escape hatch + multi-model router**, exploited through **structured narrative data** — not a generic chat.

> The differentiator is not the AI. It is that Storyarn already knows what other tools need AI to guess. The engine knows; the LLM writes.

## Strategic pillars

1. **Storyarn pays and abstracts the API by default.** Users think in actions ("find dead branches"), never in tokens/keys. Each plan includes a monthly credit pool (resets, does not accumulate) with published per-action prices.
2. **BYOK stays as the advanced lane** (shipped in Slice 0 / PR #28): power users, studios with provider agreements, privacy-sensitive teams.
3. **Never unlimited AI.** Budget gates before/during/after every call. Credits carry a 2.5–4× safety multiplier over provider cost; target AI variable cost ≤ 10–20% of a plan's net revenue.
4. **Deterministic engine first, LLM second.** Graph queries, reference tracking, and validations resolve everything they can; the LLM narrates, generates, and reasons only where structure cannot. This is both the cost model and the moat.
5. **Tools, not chat.** Concrete actions with fixed credit prices, bounded context, structured output — surfaced through a global command palette.
6. **Multi-model router from day 1** (cheap / standard / premium quality tiers), starting with ONE managed open-weight provider **behind a region-aware contract** (US/Asia expansion swaps providers per zone via config, never via code — owner requirement). Self-hosting is gated by volume metrics (break-even ≈ 1.5–2B tokens/month).

## Competitive positioning (Loreweaver, researched 2026-07-21)

loreweaver.ink (Architect + Director, ex-AAA team, pre-launch): AI **extracts** structure from prose; opaque pay-as-you-go AI, no BYOK, undisclosed models; Director charges 1% gross revenue >€100K. Our counters: structure is **native and deterministic** (no lossy extraction), transparent published pricing, no revenue share ever, BYOK available. Do NOT copy their consumer arm's context-window-as-paywall pattern: tiers gate task scope and volume, never silently degrade quality of the same task.

## Slice index

| #   | Slice                                                         | Doc                              | Depends on                                 | Status                                                          |
| --- | ------------------------------------------------------------- | -------------------------------- | ------------------------------------------ | --------------------------------------------------------------- |
| 0   | BYOK provider integrations + flag foundation (+DeepL adapter) | `SLICE_0_BYOK_INTEGRATIONS.md`   | —                                          | implemented — **merge pending (PR #28, +DeepL adapter to add)** |
| 1   | Command palette foundation (no AI)                            | `SLICE_1_COMMAND_PALETTE.md`     | —                                          | pending                                                         |
| 2   | AI Service core + internal provider + credits                 | `SLICE_2_AI_SERVICE_CORE.md`     | 0 **merged**                               | pending                                                         |
| 3   | BYOK lane through the AI Service + limit fallback UX          | `SLICE_3_BYOK_LANE.md`           | 0, 2                                       | pending                                                         |
| 4   | "My AI Team" — role assignments (+DeepL unification 2nd half) | `SLICE_4_AI_TEAM.md`             | 0, 3                                       | pending                                                         |
| 5   | Context engine v1 (deterministic)                             | `SLICE_5_CONTEXT_ENGINE.md`      | 2                                          | pending                                                         |
| 6   | Structural analysis tool (the differentiator)                 | `SLICE_6_STRUCTURAL_ANALYSIS.md` | 1, 2, 5                                    | pending                                                         |
| 7   | Dialogue tools (rewrite/variants + proposal UX)               | `SLICE_7_DIALOGUE_TOOLS.md`      | 1, 2, 5, 6 (proposal/acceptance precedent) | pending                                                         |
| 8   | Text → Storyarn structure (import with diff preview)          | `SLICE_8_TEXT_TO_STRUCTURE.md`   | 1, 2, 5, 7 (proposal UX)                   | pending                                                         |
| 9   | Tiptap writing suggestions (manual, BYOK-only)                | `SLICE_9_TIPTAP_SUGGESTIONS.md`  | 3, 4, 5 (+7 acceptance schema)             | pending                                                         |
| 10  | Image generation into sheet galleries (BYOK-only)             | `SLICE_10_IMAGE_GENERATION.md`   | 3, 4, 5                                    | pending                                                         |
| 11  | Pricing, tiers & credit purchase (data-driven)                | `SLICE_11_PRICING_TIERS.md`      | 2 + telemetry from 6–10                    | pending                                                         |

**Ordering rationale (owner-decided 2026-07-21):** credit limits become real in Slice 2, the fallback to the user's own key arrives in Slice 3, and the "which AI serves which role" decision surface (Slice 4) lands immediately after — so by the time users can hit a limit, the full decide-and-continue path exists. The DeepL _adapter_ rides PR #28 (trivial, same shape as the other six adapters); the complex half of its unification (localization consumption switch + legacy `translation_provider_configs` removal) is Slice 4's second half, so the resolution switch happens once (legacy → assignments), never twice.

**Hard precondition:** Slice 0's implementation lives in PR #28 and is NOT on `main` yet. No slice that lists 0 as a dependency may start before PR #28 is merged. Module/API references in slice docs describe main + PR #28 combined; re-verify against `main` at each slice's implementation start.

Backlog (explicitly NOT sliced yet): embeddings/semantic search where graph queries fall short · workspace-shared key pools (Studio) · self-hosted open-weight models · per-language Translator routing (schema-ready in Slice 4; UI deferred) · BYOK Analyst role (premium-quality runs on the user's key) · Storyarn MCP server (separate feature, separate plan).

## Workflow contract (applies to every slice)

1. **One branch per slice, cut from `main`**, one PR per slice. A slice is reviewed and **merged into main before the next slice starts**. If a slice depends on a previous one, it builds on the merged state.
2. **Every AI surface ships behind THE single AI flag `:ai_integrations`** (owner-decided 2026-07-21), disabled by default (`FunWithFlags`, per-user actor targeting available) — one flag governs the platform lane and the user lane alike. **Exception: the command palette ships unflagged** (no AI in it; AI commands it lists are individually flag-gated).
3. **Definition of Done for every slice**: ExUnit + Vitest tests green · `just quality-lint` fully green (beware: the recipe backgrounds `pnpm arch` — check its output explicitly) · browser verification of the user-facing path · PR opened with the slice doc linked.
4. **Conventions must be surfaced in chat during implementation**: the implementer states in conversation which project conventions apply and how they are being respected (facade pattern, shared helpers, Gettext domains, authorization on mutating events, component registry, icon policy, dialog policy…). Each slice doc lists its applicable conventions; the chat exposure is how the owner audits compliance. Convention sources: `CLAUDE.md`, `AGENTS.md`, `docs/conventions/*.md`.
5. **No code duplication**: every slice doc lists the existing files and global helpers to reuse. Search `docs/conventions/shared-utilities.md` before writing ANY helper.
6. **User documentation ships with the surface**: every user-facing slice updates the platform guide (user docs) in the same PR. AI-related docs pages are prepared but stay **hidden behind `:ai_integrations`** until GA (the docs-surface gating mechanism is verified during Slice 1).

## Observability & error-handling contract (applies to every slice)

- **Telemetry**: AI executions emit under the `[:ai, …]` namespace (span start/stop/exception); product events (palette usage, tool acceptance, CTA clicks) go to PostHog. Each slice doc lists its specific events.
- **Errors are explicit, classified, and user-visible**: failures map to classified atoms → i18n messages → explicit UI states. No silent rescues, no swallowed errors, no automatic retries beyond what a slice explicitly specifies.
- **NO FALLBACKS BY DEFAULT (owner rule, 2026-07-21, verbatim: "NADA DE FALLBACKS")**: on failure or missing configuration the system surfaces an explicit error + CTA. A fallback exists ONLY where the owner explicitly decided it — approved ones live in the Decisions log. Implementers (human or AI) MUST surface any new fallback, product, or legacy-handling decision to the owner BEFORE writing it.

## Economics guardrails (from planning discussion, 2026-07-21)

- Credit unit: internal Storyarn unit computed from real provider cost — never expose tokens. Published per-action prices must stay stable; the safety multiplier absorbs provider price drift.
- Monthly reset, no indefinite accumulation.
- Telemetry from day 1 answers: cost per feature, per user, per model; margin-negative users; % of MRR spent on inference; **acceptance rate** (share of AI outputs the user inserts/uses) as the north-star metric.
- Fixed per-action pricing is only financially safe because the context engine bounds input size. Context engine (Slice 5) precedes the broad tool catalog (Slices 6–8).

## Lane routing policy (owner-decided 2026-07-21)

Which lane serves each AI action — **always transparent to the user**:

1. **Internal lane (credits) is the default** for all task-based tools (Slices 6–8 and future catalog).
2. **At the credit limit**: the user is informed with a banner offering BOTH exits — buy credits (once Slice 11 ships) and continue on their own connected key. **Fallback to BYOK requires explicit first-time opt-in per provider** ("continue with your X account — billed to your account"), persisted as a toggle in the integrations settings page; after consent, switching is automatic.
3. **Provenance is always visible**: every AI result carries a lane badge ("Storyarn AI" vs "Your {provider} account"); `ai_usage_events` records a `lane` field. BYOK-lane calls debit NO credits (still metered for counts/latency; cost belongs to the user's provider bill).
4. **BYOK-only features** (never on credits — cost profile or capability makes the internal lane unviable):
   - **Tiptap writing suggestions** — manual trigger only (shortcut/button, owner-decided; continuous auto-suggest is the most expensive per-user pattern and stays out of v1). Users without a connected key see a connect CTA.
   - **Image generation** — only providers with the capability (OpenAI, Google of the current six); lands in sheet **gallery blocks** first (owner-decided). Users without a capable key see a capability-specific connect CTA.
5. **Capabilities vs assignments ("My AI Team", owner-decided 2026-07-21)**: providers declare immutable **capabilities** in metadata (DeepL `[:translation]`; Anthropic/Mistral/Kimi/DeepSeek `[:translation, :suggestions, :tasks]`; OpenAI/Google add `:images`); the user makes **assignments** per role slot (Translator / Writing assistant / Illustrator / Analyst) constrained by capabilities, in a "My AI Team" section INSIDE the integrations page (no third settings surface). **Provider required, model optional** — the model dropdown comes from the same `GET /models` call that validates the key; unpinned = our recommended default per provider. Analyst v1 is internal-lane only. Assignments schema carries a nullable `language` column so per-language Translator routing can land later with zero migration.

## Decisions log (all resolved by the owner, 2026-07-21)

| Decision                                     | Outcome                                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Managed provider for the internal lane       | **Together.ai** for v1 (EU region, no-retention) — **behind a region-aware contract**: US/Asia expansion swaps providers per zone via config + adapter, zero consumer changes                                                                                                                                                                    |
| Feature flags                                | **ONE flag for all AI**: `:ai_integrations` governs platform lane and user lane alike. **The command palette ships unflagged** (no AI in it; AI commands it lists are gated)                                                                                                                                                                     |
| Palette scope (Slice 1)                      | **Full Storyarn control center** — normal commands from day one, AI actions register later as more commands                                                                                                                                                                                                                                      |
| Free-tier "limited context" semantics        | **Scope gating only** (task scope/volume/input size) — never silently degrade the quality of the same task                                                                                                                                                                                                                                       |
| Credit-ledger owner scope                    | **Workspace** — grants flow from the workspace's Billing plan; members share the pool; per-member attribution via `ai_usage_events`                                                                                                                                                                                                              |
| Live DeepL config rows (Slice 4 migration)   | **Drop + in-app/email notice + reconnect** (~2 real users on the platform; migration-by-copy ruled out — it could hand user A's key to user B)                                                                                                                                                                                                   |
| Structural detectors pricing (Slice 6)       | **Detectors FREE always** (deterministic narrative linting, ~zero marginal cost, max differentiation); only the LLM-narrated report costs credits                                                                                                                                                                                                |
| User-marked **default AI** (fallback target) | In My AI Team the user marks ONE provider as default, with an explicit hint ("this is the model used when you hit the platform AI limit"). The at-limit opt-in modal doubles as default designation. Unassigned roles resolve to the default if capable — otherwise **explicit error + CTA**. The "first capable connected" auto-pick is REMOVED |
| Assigned provider disconnected               | Use the user's default (if healthy) **with a visible notice + link to the broken assignment**; if the default is also unavailable → explicit error, no degradation                                                                                                                                                                               |
| Oversized context entities (Slice 5)         | Summarized via cached summaries **with a visible indicator in the result** ("context summarized for N entities") — never silently                                                                                                                                                                                                                |
| User documentation                           | Palette documented in the platform guide during Slice 1 + AI docs skeleton prepared flag-hidden; every user-facing slice updates user docs in its own PR                                                                                                                                                                                         |

Implementation-time choices (resolved in chat during each slice per the workflow contract): analysis module placement (`Flows.Analysis` vs `AI.Analysis`), gettext domain for AI strings, purchased-credit expiry policy (Slice 11 Stage A memo).

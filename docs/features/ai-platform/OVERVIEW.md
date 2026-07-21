# AI Platform — Overview & Slice Plan

Storyarn's AI strategy: **credits-included default AI + BYOK escape hatch + multi-model router**, exploited through **structured narrative data** — not a generic chat.

> The differentiator is not the AI. It is that Storyarn already knows what other tools need AI to guess. The engine knows; the LLM writes.

## Strategic pillars

1. **Storyarn pays and abstracts the API by default.** Users think in actions ("find dead branches"), never in tokens/keys. Each plan includes a monthly credit pool (resets, does not accumulate) with published per-action prices.
2. **BYOK stays as the advanced lane** (shipped in Slice 0 / PR #28): power users, studios with provider agreements, privacy-sensitive teams.
3. **Never unlimited AI.** Budget gates before/during/after every call. Credits carry a 2.5–4× safety multiplier over provider cost; target AI variable cost ≤ 10–20% of a plan's net revenue.
4. **Deterministic engine first, LLM second.** Graph queries, reference tracking, and validations resolve everything they can; the LLM narrates, generates, and reasons only where structure cannot. This is both the cost model and the moat.
5. **Tools, not chat.** Concrete actions with fixed credit prices, bounded context, structured output — surfaced through a global command palette.
6. **Multi-model router from day 1** (cheap / standard / premium quality tiers), starting with ONE managed open-weight provider. Self-hosting is gated by volume metrics (break-even ≈ 1.5–2B tokens/month).

## Competitive positioning (Loreweaver, researched 2026-07-21)

loreweaver.ink (Architect + Director, ex-AAA team, pre-launch): AI **extracts** structure from prose; opaque pay-as-you-go AI, no BYOK, undisclosed models; Director charges 1% gross revenue >€100K. Our counters: structure is **native and deterministic** (no lossy extraction), transparent published pricing, no revenue share ever, BYOK available. Do NOT copy their consumer arm's context-window-as-paywall pattern: tiers gate task scope and volume, never silently degrade quality of the same task.

## Slice index

| # | Slice | Doc | Depends on | Status |
|---|---|---|---|---|
| 0 | BYOK provider integrations + feature-flag foundation | `SLICE_0_BYOK_INTEGRATIONS.md` | — | **DONE** (PR #28) |
| 1 | Command palette foundation (no AI) | `SLICE_1_COMMAND_PALETTE.md` | — | pending |
| 2 | AI Service core + internal provider + credits | `SLICE_2_AI_SERVICE_CORE.md` | 0 | pending |
| 3 | Context engine v1 (deterministic) | `SLICE_3_CONTEXT_ENGINE.md` | 2 | pending |
| 4 | Structural analysis tool (the differentiator) | `SLICE_4_STRUCTURAL_ANALYSIS.md` | 1, 2, 3 | pending |
| 5 | Dialogue tools (rewrite/variants + proposal UX) | `SLICE_5_DIALOGUE_TOOLS.md` | 1, 2, 3 | pending |
| 6 | Text → Storyarn structure (import with diff preview) | `SLICE_6_TEXT_TO_STRUCTURE.md` | 1, 2, 3, 5 (proposal UX) | pending |
| 7 | Pricing, tiers & credit purchase (data-driven) | `SLICE_7_PRICING_TIERS.md` | 2 + telemetry from 4–6 | pending |

Backlog (explicitly NOT sliced yet): embeddings/semantic search where graph queries fall short · BYOK routed through the AI Service (user key for premium tiers) · workspace-shared key pools (Studio) · self-hosted open-weight models · Storyarn MCP server (separate feature, separate plan).

## Workflow contract (applies to every slice)

1. **One branch per slice, cut from `main`**, one PR per slice. A slice is reviewed and **merged into main before the next slice starts**. If a slice depends on a previous one, it builds on the merged state.
2. **Everything ships behind a feature flag**, disabled by default (`FunWithFlags`, per-user actor targeting available). Flag assignments are listed per slice; see Open decisions.
3. **Definition of Done for every slice**: ExUnit + Vitest tests green · `just quality-lint` fully green (beware: the recipe backgrounds `pnpm arch` — check its output explicitly) · browser verification of the user-facing path · PR opened with the slice doc linked.
4. **Conventions must be surfaced in chat during implementation**: the implementer states in conversation which project conventions apply and how they are being respected (facade pattern, shared helpers, Gettext domains, authorization on mutating events, component registry, icon policy, dialog policy…). Each slice doc lists its applicable conventions; the chat exposure is how the owner audits compliance. Convention sources: `CLAUDE.md`, `AGENTS.md`, `docs/conventions/*.md`.
5. **No code duplication**: every slice doc lists the existing files and global helpers to reuse. Search `docs/conventions/shared-utilities.md` before writing ANY helper.

## Economics guardrails (from planning discussion, 2026-07-21)

- Credit unit: internal Storyarn unit computed from real provider cost — never expose tokens. Published per-action prices must stay stable; the safety multiplier absorbs provider price drift.
- Monthly reset, no indefinite accumulation.
- Telemetry from day 1 answers: cost per feature, per user, per model; margin-negative users; % of MRR spent on inference; **acceptance rate** (share of AI outputs the user inserts/uses) as the north-star metric.
- Fixed per-action pricing is only financially safe because the context engine bounds input size. Context engine (Slice 3) precedes the broad tool catalog.

## Open decisions (owner input needed — do not lock in code)

| Decision | Options | Recommendation |
|---|---|---|
| Managed open-weight provider for the internal lane | Together.ai (EU region, no-retention default) / Cloudflare Workers AI (cheapest, global edge) / DeepInfra | Together.ai if EU data residency matters, else Cloudflare |
| Flag naming | Reuse `:ai_integrations` for everything / umbrella `:ai_platform` for slices 2+ / separate `:command_palette` for slice 1 | Separate `:command_palette` (palette has non-AI value, can GA earlier) + `:ai_platform` for 2+ |
| Palette scope in Slice 1 | AI-only launcher / full Storyarn control center | Full control center (single interface to learn; AI lands later as more commands) |
| Free-tier "limited context" semantics | Scope gating (per-scene vs whole-project analysis) / window capping | Scope gating only — never silently degrade the same task |

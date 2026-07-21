# Slice 4 — "My AI Team": Role Assignments per Capability (+ DeepL unification)

## Objective

A "My AI Team" section INSIDE the integrations page where the user assigns connected providers to role slots — **Translator, Writing assistant, Illustrator, Analyst** — constrained by each provider's capabilities. Provider required, model optional (owner-decided); assignments drive provider resolution for localization and the later Slices 9–10. Includes the LLM-translation path (Translator can point at Claude/GPT/etc. instead of DeepL) **and completes the DeepL unification started in Slice 0**: localization consumes the per-user DeepL integration through the Translator assignment and the legacy per-project config is removed. Positioned right after the BYOK lane so the "which AI do I use at the limit" decision surface exists as soon as limits are reachable.

## Problem & proposed solution

**Problem:** with 7 providers and 4 usage classes, "which AI does what" becomes an implicit, confusing rule set; users cannot express preferences like "Claude for translations instead of DeepL".
**Solution:** an explicit roster. Each role slot shows a dropdown of eligible providers (connected ∩ capable); optional model pin populated from the same `GET /models` response that validated the key (unpinned = our recommended default per provider). Consumers resolve `provider_for(user, role)` through one function; unassigned roles fall back to Slice 3's "first capable connected" rule (Analyst v1 always resolves to the internal lane). The team metaphor doubles as the differentiator narrative for game devs.

## Architectural direction

- Data: `ai_role_assignments` (user_id, role, provider, model nullable, **language nullable — column ships now, per-language Translator routing UI is backlog with zero future migration**). Unique per (user, role, language) with language NULL as the default row.
- Resolution: `Storyarn.AI.provider_for(user, role)` via the facade; consumed by `BatchTranslator` (Translator) now and Slices 9 (Writing assistant) / 10 (Illustrator) when they land. Assignments validated against capabilities at write time AND resolution time (a revoked/disconnected provider degrades to the fallback rule with a UI hint, never a crash).
- **DeepL unification (second half — adapter shipped in Slice 0)**: `BatchTranslator` resolves credentials through the Translator assignment; the legacy `translation_provider_configs` schema/CRUD and its project-settings UI are removed. **Owner decision surfaced in chat before the migration**: live beta rows — copy each project key to the project owner's user integration + notify, vs. drop and ask users to reconnect. Localization settings keeps a read-only pointer ("managed in AI Integrations").
- **LLM translation**: a `BatchTranslator` provider implementation that routes through `AI.execute` on the BYOK lane (`byok_only` for v1 — translation volume on credits is a Slice 11 pricing question, not assumed). DeepL remains the recommended Translator default when connected.
- Model pinning: models fetched at connect/validation time and cached on the integration row (refresh on revalidate); the dropdown never blocks on a live provider call.
- UI: a section under the cards grid in the integrations page (no third settings surface — owner-decided); each slot: role icon, eligible-provider dropdown, optional model select, capability-aware empty state ("connect a provider with translation capability").

## Existing code to reuse (do not duplicate)

Slice 0 integrations page + `IntegrationCrud` + DeepL adapter (PR #28) · Slice 3 capabilities metadata + lane resolution + consent/badges · `BatchTranslator` abstraction + legacy `translation_provider_configs` code (to port, then delete) · `Storyarn.Localization` translation flows · shadcn `ui/select`/combobox components (registry check — no new dropdown primitives) · `FeatureFlags` · gettext/i18n infra · `Shared.Validations` patterns for changeset checks.

## Applicable conventions (MUST be surfaced in chat during implementation)

Facade-only resolution API · authorization: assignments are own-scope mutations on the settings LV · capability constraints enforced server-side (UI hiding is not enough — project auth rule applied to data validity) · i18n en/es for roles/empty states (role names are product vocabulary — owner reviews copy) · Lucide icons per role · no `<select>` daisy patterns — use the existing combobox/join-button conventions · migration verify on dev DB.

## Verification / Definition of Done

- ExUnit: assignment changesets (capability mismatch rejected, unique per role+language), `provider_for/2` resolution matrix (assigned / unassigned fallback / disconnected degradation), LLM-translation provider through the BYOK lane (no credit debit), model-pin persistence and cache refresh, legacy-config migration per the decided strategy + removal leaves no dead references (`mix compile --warning-as-errors`).
- Vitest: team section (eligible filtering per role, model dropdown states, empty states), assignment flow emits.
- Browser: assign Claude as Translator with DeepL also connected → run a batch translation on Claude; unassign → falls back; badge shows the executing provider.
- Lint fix as last command before push · `just quality-lint` green + full suites.

## Delivery

Branch `feat/ai-team-assignments` from main → PR → merge before Slice 5+. Flags: `:ai_platform` (+ `:ai_integrations` surfaces).

## Inputs from previous slices

Slices 0 and 3 merged. Slices 9–10 consume `provider_for/2` when they land. Estimate: **12–16h** (includes the DeepL consumption switch + legacy removal).

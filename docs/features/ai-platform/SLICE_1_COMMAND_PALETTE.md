# Slice 1 — Command Palette Foundation (no AI)

## Objective

A global command palette (`Meta+K` on macOS, `Ctrl+K` on Windows/Linux — both bindings tested) that is **Storyarn's control center**: context-aware commands per editor surface (flows, sheets, scenes, localization, dashboards), fuzzy search, keyboard-first. Ships useful with zero AI; later slices register AI actions as just more commands.

## Problem & proposed solution

**Problem:** (a) feature discoverability — capabilities buried in per-surface toolbars/menus; (b) the AI tool catalog (Slices 6–8) needs a home that is not an open chat; (c) several distinct editor surfaces make users re-learn UI per tool.
**Solution:** one palette, one interaction model. VSCode/Raycast pattern: typed prefix filters commands; free text falls through to (later) AI actions. Commands declare surface scope, so the palette only offers what applies where you are.

## Architectural direction

- **Client-side command registry** with an explicit registration owner per declared surface: editor modules under `assets/app/modules/{flows,sheets,scenes,localization}` register their own commands; dashboard/workspace surfaces (which live under `assets/app/live/…`, not `modules/`) register from their page components. Each command: id, i18n label key, icon, scope, handler. No hardcoded global list; a surface without a registration owner is NOT declared in the objective.
- Handlers are either pure-client (toggle panel, focus node) or LiveView events via `useLive().pushEvent` — reusing each surface's EXISTING event handlers; the palette never introduces new mutation paths.
- Navigation commands use the LiveVue navigation contract (`data-phx-link` / `LiveLink`) — never raw `window.location`.
- Global `Meta+K` (macOS) / `Ctrl+K` (Windows/Linux) listener with guard against input/contenteditable focus (respect `@keydown.stop` conventions from dnd work). Both platform bindings covered by tests.
- **No feature flag (owner-decided 2026-07-21): the palette ships directly** — it has no AI and the owner wants it GA from day one. AI commands registered by later slices are individually gated by the single AI flag (`:ai_integrations`): with the flag off, the palette simply never lists them.

## Existing code to reuse (do not duplicate)

- **`assets/app/components/ui/command/`** — shadcn-vue Command (cmdk port) already in the repo. KNOWN PITFALL from project experience: `CommandItem` outside `CommandGroup` throws silently and can corrupt state — always group.
- `assets/app/components/ui/dialog/` for the overlay · `@shared/composables/useLive` · `LiveLink` (`components/navigation/`) · `LucideIcon` manual icon map (add icons by hand — no `import *`) · `<.kbd>`/kbd styling for shortcut hints · i18n `locales/{en,es}/` (new `palette.json`) · `Storyarn.FeatureFlags` + the `SettingsLayout`→`Layout.vue` flag-prop pattern from Slice 0 for flag exposure.
- Elixir: no new context needed. Router/LV changes only if a server-driven command list becomes necessary (avoid in v1 — keep the registry client-side).

## Applicable conventions (MUST be surfaced in chat during implementation)

TypeScript strict, no `any`, destructured prop defaults · emits over callback props · component registry check before creating anything (`docs/conventions/component-registry.md`) · Lucide-only icons · no browser-native dialogs · i18n `$t()` with `{param}` interpolation, en/es both · a11y: focus trap, aria-activedescendant, escape handling via reka events (`@escape-key-down`, not `@update:open`) · vitest tests in `assets/app/test/` · LiveVue: wrap `<.vue>` in id'd div where mounted.

## User documentation (deliverable of this slice)

- **Platform guide page for the palette** (user docs system, `Storyarn.Docs`): what it is, how to open it per platform (Meta+K / Ctrl+K), command scopes per surface. Ships visible with the slice.
- **AI docs skeleton prepared but hidden behind `:ai_integrations`**: the guide section where AI actions will be documented exists from this slice, gated by the flag. **This slice DEFINES AND TESTS one flag-aware visibility path — not just "verifies" it — covering every exposure surface: direct URLs (404 when off), guide navigation/search/prev-next indexes, `/sitemap.xml`, and `/llms.txt`** (docs render for unauthenticated visitors, so gating is by global flag state, not per-user). Tests assert the AI pages are unreachable through ALL of those surfaces with the flag off.

## Observability & error handling

PostHog events with their EXACT allowlisted property keys — `palette_opened` (`surface`), `palette_command_executed` (`command_id`, `surface`), `palette_search_no_results` (`surface`, `query_length` only — the raw query string NEVER leaves the client) — **registered through the repository's analytics boundary (`Storyarn.Analytics` allowlist): this slice adds the event names AND those property keys to the allowlist, with tests proving each event is emitted with exactly its sanitized payload (unregistered events/properties are silently dropped; no search content in telemetry)** · command handler failures surface as an explicit toast/flash with an i18n message — never silent, never retried automatically · no fallbacks: an unavailable command simply does not appear (scope filtering), it never swaps in a different action.

## Verification / Definition of Done

- Vitest: registry (scope filtering, registration, flag-gated commands hidden when the AI flag is off), palette component (open/close, search, group rendering, keyboard nav), stale-state guards.
- Browser: open palette on ≥2 different surfaces, verify scoped commands differ, run a navigation command and a panel-toggle command.
- `just quality-lint` green (check `pnpm arch` output explicitly) + full test suites.

## Delivery

Branch `feat/command-palette` from main → PR → review → merge before Slice 2 UI work lands on it. Ships unflagged (owner-decided).

## Inputs from previous slices

None (parallel-safe with Slice 2's backend). Estimate: **10–14h**.

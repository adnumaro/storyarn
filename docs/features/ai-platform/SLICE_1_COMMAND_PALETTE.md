# Slice 1 — Command Palette Foundation (no AI)

**Status: foundation + universal navigation SHIPPED on `feat/command-palette` (PR #30); F2 creation / F3 deletion PENDING — see "Implementation status & handoff" below before resuming.**

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

PostHog events with their EXACT allowlisted property keys — `"palette opened"` (`surface`), `"palette command executed"` (`command_id`, `surface`), `"palette search no results"` (`surface`, `query_length` only — the raw query string NEVER leaves the client) — names follow the repository's existing space-separated event convention (`"onboarding tutorial interacted"`), not `snake_case`; the client pushes `palette_*` LiveView events that a global hook maps to these names — **registered through the repository's analytics boundary (`Storyarn.Analytics` allowlist): this slice adds the event names AND those property keys to the allowlist, with tests proving each event is emitted with exactly its sanitized payload (unregistered events/properties are silently dropped; no search content in telemetry)** · command handler failures surface as an explicit toast/flash with an i18n message — never silent, never retried automatically · no fallbacks: an unavailable command simply does not appear (scope filtering), it never swaps in a different action.

## Verification / Definition of Done

- Vitest: registry (scope filtering, registration, flag-gated commands hidden when the AI flag is off), palette component (open/close, search, group rendering, keyboard nav), stale-state guards.
- Browser: open palette on ≥2 different surfaces, verify scoped commands differ, run a navigation command and a panel-toggle command.
- `just quality-lint` green (check `pnpm arch` output explicitly) + full test suites.

## Delivery

Branch `feat/command-palette` from main → PR → review → merge before Slice 2 UI work lands on it. Ships unflagged (owner-decided).

## Inputs from previous slices

None (parallel-safe with Slice 2's backend). Estimate: **10–14h**.

## Implementation status & handoff (2026-07-21, PR #30)

### Shipped

- **F1 — universal navigation (owner-directed rework)**: the original "client-side registry only" scope was rejected as useless on the workspace dashboard ("NO ME VALE"); the owner mandated full deterministic navigation — **projects + settings + entities, executable from anywhere**. Shipped as:
  - `Storyarn.GlobalSearch` (facade + `Destinations`): authorized destination search composing the EXISTING membership-scoped queries (`Workspaces.list_workspaces/1`, `Projects.list_projects_for_workspace/2`) — authorization is never re-derived; entity ILIKE searches (`Sheets/Flows/Scenes.search_*_in_projects/3`, name+shortcut, sanitized, soft-delete-filtered, per-type limits, min 2 chars by `String.length`) only run against the pre-authorized project-id set. Cross-user isolation is test-enforced at context AND hook level.
  - `StoryarnWeb.Live.Hooks.Palette` in the `:authenticated_app` `live_session`: `palette_nav` replies `{token, groups}` (workspaces / projects / `project_settings` / role-gated `workspace_settings` via `can?(role, :manage_workspace)` / entities) with verified-route URLs; analytics events allowlist-validated server-side (finite `@known_surfaces`, `command_id` matching `^[a-z0-9._-]{1,100}$` — hostile clients cannot persist story text).
  - Client (`components/command-palette/` + `shared/command-palette/`): registry with lifetime-scoped registrations (mount/unmount IS the surface scoping), debounced `palette_nav` with stale-token invalidation on each keystroke, entity `shortcut` in an `sr-only` span so cmdk's textContent filter matches shortcut hits, failing `run()` keeps the palette open with a localized `role="alert"` (no client toast API exists in the repo) and only successful runs emit the executed event.
- **Static commands**: project tool navigation (`layout.tools.*`) + the 8 project-settings sections (`project_settings.nav.items.*`) + account commands (shared `accountCommands.ts` builder on BOTH layouts, `settings.nav.items.*`) + flows minimap toggle/fit (`flows.minimap.*`) + scenes fit (`scenes.canvas.fit_view`) + workspace sidebar toggle (registered ONLY below the desktop breakpoint where it can execute — the dashboard sidebar is force-open on desktop — with stateful `layout.main_sidebar.show/hide_panel` labels).
- **Naming rule (owner, verbatim): "Todo concepto tiene que tener el mismo nombre da igual donde esté situado"** — every palette label reuses the concept's EXISTING i18n key; inventing parallel labels broke search ("profile" found nothing). New keys only for genuinely new concepts, in the owning domain's locale file.
- Analytics/docs/gating from the original scope: shipped as specified above (three allowlisted events, docs facade flag-gating over all four exposure surfaces, palette guide page en/es).
- Corrections to this doc's original reuse list: `<.kbd>` and the `LucideIcon` map do NOT exist on main (use `CommandShortcut` + direct `lucide-vue-next` imports); "keep the registry client-side" was superseded by the server-driven navigation source; "AI Integrations" is deliberately NOT listed in the palette until it can check the flag (a listed-but-erroring command violates only-list-what-executes).

### Pending — F2 creation commands (est. 3–5h)

Create project / flow / sheet / scene (empty) from the palette. All creation events EXIST: `set_new_project_modal_open` + `create_project` on `WorkspaceLive.Show`; `create_sheet`/`create_flow`/`create_scene` (+ child variants) on the sheets/flow/scene **sidebar LiveViews**.

- **Open design decision (the only real one — surface to owner before coding):** the palette talks to the MAIN LV, but entity-creation handlers live on the NESTED sidebar LVs. Options: (a) the global `Palette` hook handles `palette_create_*` events calling the same context facades with `with_authorization` (new entry point, same mutation path/facades), or (b) PubSub delegation to the sidebar LV. Lean (a) — simpler, testable, authorization explicit.
- Create-project from the workspace dashboard = trigger the existing modal (`set_new_project_modal_open`); from inside a project = navigate to the workspace dashboard with the modal open (needs a param or post-nav event).
- Creating an entity from OUTSIDE its project needs a project-picker step in the palette (multi-step state) — or v1 restricts entity creation to the current project (cheaper; surface the choice).
- Respect permissions at registration where checkable (`can_edit`), always server-side on execution.

### Pending — F3 deletion commands (est. 2–3h)

Delete the selected/current entity with permissions + confirmation. Events EXIST on the sidebar LVs (`set_pending_delete_*` + `confirm_delete_*`); reuse `ConfirmDialog.vue` (never browser-native). Same bridge decision as F2 applies. Only list the command where it can execute (`can_edit`, entity context present).

### Also pending

- Browser verification of F1 by the owner (palette on ≥2 surfaces; "kael"-style entity jump; workspace-settings gating as member vs owner).
- Sheets/localization surface-specific VIEW commands: none yet (no cheap client-side actions without new plumbing) — the registry mechanism is proven; they register when they have palette-worthy actions.

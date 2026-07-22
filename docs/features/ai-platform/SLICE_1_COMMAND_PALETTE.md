# Slice 1 — Command Palette Foundation (no AI)

**Status: IN REVIEW. F1 foundation + universal navigation MERGED (PR #30); F2 creation + F3 deletion in review (PR #31, `feat/palette-entity-commands`), owner browser verification pending — see "Implementation status & handoff" below.**

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

### Shipped — F2 creation + F3 deletion (2026-07-21, follow-up PR on `feat/palette-entity-commands`)

Owner-resolved design (all decided in chat before coding):

- **Bridge = (a) global hook → facades**: `Hooks.Palette` gained `palette_create_targets` / `palette_create` / `palette_delete_search` / `palette_delete`. Authorization is domain-composed (`GlobalSearch.editable_project/2`, `deletable_entity/4` re-validate every client-sent id against the editable-project set built from the existing membership queries + `Projects.effective_role/2`, new public delegate). Mutations run through the SAME facades the sidebars call (`Sheets/Flows/Scenes.create_*`/`delete_*`, name `dgettext("<domain>", "Untitled")`), and broadcast the same shell-topic messages (`{:tree_changed, key}` + `{:entities_deleted, type, ids}` via `ProjectChromeHelpers.shell_topic/1`) — plain broadcast, not `broadcast_from`, so the LV serving the palette navigates away when its own open entity is deleted (existing `Show` handlers do this).
- **Entity creation with project picker from ANYWHERE** (owner chose picker over current-project-only): palette got multi-step state (`root → create-pick-project`, client-side cmdk filtering over the full editable set); create replies `{url}` → `liveNavigate`. Zero editable projects shows an explicit empty state.
- **Project creation ONLY on the workspace dashboard** (owner reverted the `?new_project=1` idea): `WorkspaceDashboard.vue` registers `create.project` mirroring the header button's EXACT visibility predicate (`canCreate && canCreateProject && newProjectForm` — role + plan capacity + form availability) and triggers the existing modal event.
- **Deletion = any entity by search, entirely INSIDE the palette (owner, verbatim: "NUNCA SALE DEL PALETTE")**: `root → delete-pick-entity → delete-confirm` with inline destructive confirm reusing `<type>s.tree.delete_title/description/delete`; success returns to the refreshed listing; Escape/Backspace-on-empty walks one step back (the dialog only closes from root). Delete search browses recents on empty query — `search_*_in_projects/3` empty-query contract changed from "no results" to "recent first" (destructive pickers must browse before typing).
- Analytics: new static ids `create.project|sheet|flow|scene`, `delete.sheet|flow|scene` added to `@static_command_ids` (mandatory for tracking). Server error codes (`unauthorized`, `limit_reached`, `not_found`, `create_failed`, `delete_failed`) map to explicit client messages; `limit_reached`/`unauthorized` have specific texts.
- Riders: `flows/scenes.tree.delete_description` keys added (en/es) and the hardcoded English literals in `FlowTree.vue`/`SceneTree.vue` confirm dialogs replaced with `$t` (pre-existing i18n drift).

**Deletion broadcast contract (cubic rounds 1–2, 2026-07-22)**: the legacy type-blind `{:entity_deleted, id}` was replaced everywhere by `{:entities_deleted, :sheet | :flow | :scene, ids}` carrying the FULL committed cascade set. The ids are reported by the deletion itself — `Sheets.delete_sheet_subtree/1` / `Flows.delete_flow_subtree/1` / `Scenes.delete_scene_subtree/1` return `{:ok, %{entity, deleted_ids}}` collected UNDER the delete's own locks (`SoftDelete.soft_delete_children/4` now returns the ids it cascades) — so the broadcast can never desync from a concurrent tree change, open editors of the entity OR any cascade-deleted descendant navigate away, and same-numeric-id collisions across types no longer misfire. Both emitters (sidebar `TreeSidebarActions` path and the palette hook) and all six Show/Index consumers use the typed shape.

### Also pending

- Browser verification of F1 by the owner (palette on ≥2 surfaces; "kael"-style entity jump; workspace-settings gating as member vs owner) — plus F2/F3: picker create from the dashboard, in-palette delete of the currently open entity.
- Sheets/localization surface-specific VIEW commands: none yet (no cheap client-side actions without new plumbing) — the registry mechanism is proven; they register when they have palette-worthy actions.

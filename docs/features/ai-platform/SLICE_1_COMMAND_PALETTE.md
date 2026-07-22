# Slice 1 — Command Palette Foundation (no AI)

**Status: MERGED baseline. F1 foundation + universal navigation shipped in PR #30; F2 creation + F3 deletion shipped in PR #31. The 2026-07-22 post-merge audit produced a hardening follow-up covering real-browser keyboard behavior, async execution, idempotency, authorization and authenticated settings coverage.**

## Objective

A global command palette (`Meta+K` on macOS, `Ctrl+K` on Windows/Linux — both bindings tested) that is **Storyarn's control center**: context-aware commands per editor surface (flows, sheets, scenes, localization, dashboards), keyboard-first search. Ships useful with zero AI; later slices register typed AI actions as commands.

## Problem & proposed solution

**Problem:** (a) feature discoverability — capabilities buried in per-surface toolbars/menus; (b) the later AI tool catalog (Slices 7–12) needs a home that is not an open chat; (c) several distinct editor surfaces make users re-learn UI per tool.
**Solution:** one palette, one interaction model. Typed input filters registered commands and authorized destinations. AI is never an automatic free-text fallback: Slice 2 adds an explicit async descriptor that maps only to allowlisted tasks. Commands declare surface scope, so the palette offers only what applies where the user is.

## Architectural direction

- **Hybrid registry and authorized server sources:** surface-owned client commands register for their component lifetime; global navigation/create/delete results come from `StoryarnWeb.Live.Hooks.Palette` and `Storyarn.GlobalSearch`, scoped to the current authenticated actor. A surface without a local owner exposes only the global commands it can execute.
- Handlers are either pure-client (toggle panel, focus node) or LiveView events through the palette hook. Mutations reuse the same domain facades and broadcasts as existing UI; the palette never introduces a second mutation path.
- Navigation commands use the LiveVue navigation contract (`data-phx-link` / `LiveLink`) — never raw `window.location`.
- Global `Meta+K` (macOS) / `Ctrl+K` (Windows/Linux) listener. Editable contexts use a per-binding policy: the shortcut does not open over an editor or another dialog, but it does close the palette while its own search input has focus.
- **No feature flag (owner-decided 2026-07-21): the palette ships directly** — it has no AI and the owner wants it GA from day one. AI commands registered by later slices are individually gated by the single AI flag (`:ai_integrations`): with the flag off, the palette simply never lists them.

## Existing code to reuse (do not duplicate)

- `assets/app/components/command-palette/` and `assets/app/shared/command-palette/` — shipped palette and lifetime-scoped registry.
- `assets/app/components/ui/command/` — shadcn-vue Command; keep every `CommandItem` inside a `CommandGroup` and use `CommandShortcut` for key hints.
- `@shared/composables/useLive` · `LiveLink` (`components/navigation/`) · direct named `lucide-vue-next` imports (no wildcard import or nonexistent icon map) · existing owning-domain i18n keys whenever the concept already exists.
- Elixir: `StoryarnWeb.Live.Hooks.Palette`, `Storyarn.GlobalSearch`, current project/workspace authorization, domain facades, and shell broadcasts. Extend these boundaries rather than introducing an unauthenticated or client-trusted command list.

## Applicable conventions (MUST be surfaced in chat during implementation)

TypeScript strict, no `any`, destructured prop defaults · emits over callback props · component registry check before creating anything (`docs/conventions/component-registry.md`) · Lucide-only icons · no browser-native dialogs · i18n `$t()` with `{param}` interpolation, en/es both · a11y: focus trap, aria-activedescendant, escape handling via reka events (`@escape-key-down`, not `@update:open`) · vitest tests in `assets/app/test/` · LiveVue: wrap `<.vue>` in id'd div where mounted.

## User documentation (deliverable of this slice)

- **Platform guide page for the palette** (user docs system, `Storyarn.Docs`): what it is, how to open it per platform (Meta+K / Ctrl+K), command scopes per surface. Ships visible with the slice.
- **AI docs skeleton prepared but not published yet**: public docs cannot use the actor-targeted `:ai_integrations` entitlement because unauthenticated readers have no actor. During invite-only infrastructure beta, AI surfaces provide inline help. Slice 7 publishes the AI guide section for everyone when the first user-facing AI tool ships; the product surface remains actor-gated. Documentation is not a security boundary, and no second product feature flag is introduced merely to hide it.

## Observability & error handling

PostHog events with their EXACT allowlisted property keys — `"palette opened"` (`surface`), `"palette command executed"` (`command_id`, `surface`), `"palette search no results"` (`surface`, `query_length` only) — names follow the repository's existing space-separated event convention (`"onboarding tutorial interacted"`), not `snake_case`; authorized destination search sends the query to the Storyarn server, but **the query is never persisted or included in analytics/log metadata**; the client pushes `palette_*` LiveView events that a global hook maps to these names — **registered through the repository's analytics boundary (`Storyarn.Analytics` allowlist): this slice adds the event names AND those property keys to the allowlist, with tests proving each event is emitted with exactly its sanitized payload (unregistered events/properties are silently dropped; no search content in telemetry)** · command handler failures remain in the palette as a localized `role="alert"` state — never silent, never retried automatically · no fallbacks: an unavailable command simply does not appear, it never swaps in a different action.

## Verification / Definition of Done

- Vitest: registry (scope filtering, registration, flag-gated commands hidden when the AI flag is off), palette component (open/close, search, group rendering, keyboard nav), stale-state guards.
- Browser: open palette on ≥2 different surfaces, verify scoped commands differ, run a navigation command and a panel-toggle command.
- `just quality-lint` green (check `pnpm arch` output explicitly) + full test suites.

## Delivery

Branch `feat/command-palette` from main → PR → review → merge before Slice 2 UI work lands on it. Ships unflagged (owner-decided).

## Inputs from previous slices

None (parallel-safe with Slice 2's backend). Estimate: **10–14h**.

## AI hand-off (normative)

The hardened registry supports typed navigation and Promise-aware local actions, reactive visibility/enabled predicates, actor-resolved flag propagation, pending/error states and session-idempotent palette mutations. This is sufficient for deterministic non-AI commands, but it is still not the AI execution contract. Slice 2 must add the discriminated `launch | execute` AI task descriptor, server-resolved cost/preflight and declarative result routing before an AI command registers.

## Implementation status & handoff (2026-07-21, PR #30)

### Shipped

- **F1 — universal navigation (owner-directed rework)**: the original "client-side registry only" scope was rejected as useless on the workspace dashboard ("NO ME VALE"); the owner mandated full deterministic navigation — **projects + settings + entities, executable from anywhere**. Shipped as:
  - `Storyarn.GlobalSearch` (facade + `Destinations`): authorized destination search composing the EXISTING membership-scoped queries (`Workspaces.list_workspaces/1`, `Projects.list_projects_for_workspace/2`) — authorization is never re-derived; entity ILIKE searches (`Sheets/Flows/Scenes.search_*_in_projects/3`, name+shortcut, sanitized, soft-delete-filtered, per-type limits, min 2 chars by `String.length`) only run against the pre-authorized project-id set. Cross-user isolation is test-enforced at context AND hook level.
  - `StoryarnWeb.Live.Hooks.Palette` in the `:authenticated_app` `live_session`: `palette_nav` replies `{token, groups}` (workspaces / projects / `project_settings` / role-gated `workspace_settings` via `can?(role, :manage_workspace)` / entities) with verified-route URLs; analytics events allowlist-validated server-side (finite `@known_surfaces`, `command_id` matching `^[a-z0-9._-]{1,100}$` — hostile clients cannot persist story text).
  - Client (`components/command-palette/` + `shared/command-palette/`): registry with lifetime-scoped registrations (mount/unmount IS the surface scoping), debounced `palette_nav` with stale-token invalidation on each keystroke, entity `shortcut` in an `sr-only` span so cmdk's textContent filter matches shortcut hits, failing `run()` keeps the palette open with a localized `role="alert"` (no client toast API exists in the repo) and only successful runs emit the executed event.
- **Static commands**: project tool navigation (`layout.tools.*`) + the 8 project-settings sections (`project_settings.nav.items.*`) + account commands (shared `accountCommands.ts` builder on BOTH layouts, `settings.nav.items.*`) + flows minimap toggle/fit (`flows.minimap.*`) + scenes fit (`scenes.canvas.fit_view`) + workspace sidebar toggle (registered ONLY below the desktop breakpoint where it can execute — the dashboard sidebar is force-open on desktop — with stateful `layout.main_sidebar.show/hide_panel` labels).
- **Naming rule (owner, verbatim): "Todo concepto tiene que tener el mismo nombre da igual donde esté situado"** — every palette label reuses the concept's EXISTING i18n key; inventing parallel labels broke search ("profile" found nothing). New keys only for genuinely new concepts, in the owning domain's locale file.
- Analytics and the en/es palette guide shipped. The AI guide skeleton also shipped behind the existing **global** docs visibility path across direct URLs, navigation/search, sitemap, and `llms.txt`; it remains globally hidden during infrastructure beta. This rewrite supersedes that mechanism as the eventual product policy: Slice 7 removes the docs gate and publishes the guides publicly, while the in-app AI surfaces remain actor-gated.
- Shipped conventions: key hints use `CommandShortcut`, icons use direct named `lucide-vue-next` imports, and the registry combines local commands with server-authorized navigation. “AI Integrations” remains absent until availability can check its flag; a listed-but-erroring command violates only-list-what-executes.

### Shipped — F2 creation + F3 deletion (2026-07-21, PR #31)

Owner-resolved design (all decided in chat before coding):

- **Bridge = (a) global hook → facades**: `Hooks.Palette` gained `palette_create_targets` / `palette_create` / `palette_delete_search` / `palette_delete`. Authorization is domain-composed (`GlobalSearch.editable_project/2`, `deletable_entity/4` re-validate every client-sent id against the editable-project set built from the existing membership queries + `Projects.effective_role/2`, new public delegate). Mutations run through the SAME facades the sidebars call (`Sheets/Flows/Scenes.create_*`/`delete_*`, name `dgettext("<domain>", "Untitled")`), and broadcast the same shell-topic messages (`{:tree_changed, key}` + `{:entities_deleted, type, ids}` via `ProjectChromeHelpers.shell_topic/1`) — plain broadcast, not `broadcast_from`, so the LV serving the palette navigates away when its own open entity is deleted (existing `Show` handlers do this).
- **Entity creation with project picker from ANYWHERE** (owner chose picker over current-project-only): palette got multi-step state (`root → create-pick-project`, client-side cmdk filtering over the full editable set); create replies `{url}` → `liveNavigate`. Zero editable projects shows an explicit empty state.
- **Project creation ONLY on the workspace dashboard** (owner reverted the `?new_project=1` idea): `WorkspaceDashboard.vue` registers `create.project` mirroring the header button's EXACT visibility predicate (`canCreate && canCreateProject && newProjectForm` — role + plan capacity + form availability) and triggers the existing modal event.
- **Deletion = any entity by search, entirely INSIDE the palette (owner, verbatim: "NUNCA SALE DEL PALETTE")**: `root → delete-pick-entity → delete-confirm` with inline destructive confirm reusing `<type>s.tree.delete_title/description/delete`; success returns to the refreshed listing; Escape/Backspace-on-empty walks one step back (the dialog only closes from root). Delete search browses recents on empty query — `search_*_in_projects/3` empty-query contract changed from "no results" to "recent first" (destructive pickers must browse before typing).
- Analytics: new static ids `create.project|sheet|flow|scene`, `delete.sheet|flow|scene` added to `@static_command_ids` (mandatory for tracking). Server error codes (`unauthorized`, `limit_reached`, `not_found`, `create_failed`, `delete_failed`) map to explicit client messages; `limit_reached`/`unauthorized` have specific texts.
- Riders: `flows/scenes.tree.delete_description` keys added (en/es) and the hardcoded English literals in `FlowTree.vue`/`SceneTree.vue` confirm dialogs replaced with `$t` (pre-existing i18n drift).

**Deletion broadcast contract (cubic rounds 1–2, 2026-07-22)**: the legacy type-blind `{:entity_deleted, id}` was replaced everywhere by `{:entities_deleted, :sheet | :flow | :scene, ids}` carrying the FULL committed cascade set. The ids are reported by the deletion itself — `Sheets.delete_sheet_subtree/1` / `Flows.delete_flow_subtree/1` / `Scenes.delete_scene_subtree/1` return `{:ok, %{entity, deleted_ids}}` collected UNDER the delete's own locks (`SoftDelete.soft_delete_children/4` now returns the ids it cascades) — so the broadcast can never desync from a concurrent tree change, open editors of the entity OR any cascade-deleted descendant navigate away, and same-numeric-id collisions across types no longer misfire. Both emitters (sidebar `TreeSidebarActions` path and the palette hook) and all six Show/Index consumers use the typed shape.

### Post-merge audit hardening (2026-07-22)

- Real Reka Escape handling now walks one step back, each step restores input focus, and a second shortcut closes from the palette input. The palette refuses to stack over onboarding or another open dialog.
- Pending mutations cannot be dismissed. Create/delete requests carry a bounded operation id cached by the LiveView session, retries reuse it, and every accepted result is reconciled.
- Navigation analytics are sent before LiveView teardown. Remote loading, transport failure and settled-empty states are distinct; no-results telemetry waits for the server result.
- Project settings require `:manage_project` in both static and server-driven commands. Project-derived workspace access disappears when its granting project is soft-deleted. Malformed `palette_*` events fail closed instead of reaching the host LiveView.
- The public LiveVue palette boundary now mounts in workspace, project and settings layouts, owns global account commands, and resolves the `:ai_integrations` flag for the current actor.
- Explicit create/delete error messages, workspace-qualified duplicate-name context, trimmed client/server filtering and query-suppressed Ecto logging close the remaining UX/privacy gaps.

### Product expansion intentionally deferred

- Hierarchical creation (for example, creating a sheet inside another sheet), complete project listings for sheets/flows/scenes and other advanced command families belong to the next command-catalog increment.
- Sheets/localization surface-specific view commands register when their owning surfaces expose palette-worthy actions.

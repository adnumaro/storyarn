# Scenes Migration to ProjectShell

**Branch**: `feat/live-vue-sheets`
**Date drafted**: 2026-04-16
**Order in roadmap**: Step C (after A=dashboard/assets, B=settings; before D=flows)
**Sibling reference plans**: `docs/plans/project_shell_pivot.md` (sheets), `docs/plans/localization_migration.md` (localization)

## Summary

Migrate three LVs in `lib/storyarn_web/live/scene_live/` to the ProjectShell pattern that sheets and localization already use:

- `SceneLive.Index` → into `:project_scope`, render `<ProjectShell>` with `SceneSidebarLive` as `sidebar_module`. Mount broadcasts `{:active_scene, nil}` to clear the sticky sidebar's selection.
- `SceneLive.Show` → into `:project_scope`, render `<ProjectShell>`, sticky sidebar carries the scenes tree + layers panel + tree mutations. Toolbar/SearchPanel/SceneActions render inline in the `:top_bar_extras_left` and `:top_bar_extras_right` slots. Restoration banner forwarded as a top-level attr. Canvas mode requires a small `ProjectShell` extension (no top padding, full-bleed `<main>`) since it's the first canvas page to migrate.
- `SceneLive.ExplorationLive` → **stays out** of `:project_scope`. It already uses `layout: false`, has zero PubSub, no presence, no chrome — perfectly analogous to `FlowLive.PlayerLive`. Leaving it in `:require_authenticated_user` is intentional and symmetrical.
- `CompareLive.Scene` → **stays out** for now. Scene compare uses `Layouts.compare`, not the project chrome; a dedicated decision later applies to all three Compare LVs together.

The sticky sidebar (`SceneSidebarLive`) is the trickiest piece: scenes has a **two-tab tree panel** (Layers + Scenes), where Layers is per-scene state. The Layers tab needs to know the active scene id (and its layers + active_layer_id + edit_mode) to render. We have two viable shapes for this — see "Open question 1" below.

## Risk assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Canvas mode (full-bleed, no top padding) breaks if ProjectShell's `<main>` keeps `pt-[76px]` | High | Add a `canvas_mode` attr to `ProjectShell.project_shell`, mirror the `Layouts.app:235` cond. Land that in step 1 BEFORE wiring scenes. |
| Layers tab needs per-scene state and `Show` owns scene state, but the sidebar is sticky and persists across navigation. PubSub bridge required. | High | Mirror `{:active_sheet, id}` pattern but expand: `{:scene_payload_changed, %{layers, active_layer_id, edit_mode}}`. |
| Scene-scope presence (`{:scene, scene.id}`) writes `:online_users` for the scene; project-scope presence (`{:project, id}`) also writes `:online_users`. Race: whichever fires last wins. | Medium | Confirmed identical pattern in sheets and it ships. Verify in browser. Could split later. |
| LiveVue race when nested LV mounts mid-Vue-mount (`reference_livevue_nested_lv_race.md`). Show.ex has many Vue components in the page LV (Canvas, Toolbar, SearchPanel, Actions, Dock, Legend, Settings, Properties, VersionHistory). | Medium | The pattern says: page LV may host Vue freely as long as nested children are inside `ProjectShell` with `phx-update="ignore"` for reactive props. Sidebar live_render is at top of page; PresenceLive is invisible. Should be safe but watch dev console. |
| Tree handler events fire from `SceneTree.vue` and `SceneLayerList.vue`. After migration, **scene-tree mutations** must move to `SceneSidebarLive`, but **layer mutations** are open question 1. Event names overlap (`create_*`, `set_pending_delete_*`). | Medium | Tree events: `create_scene`, `create_child_scene`, `set_pending_delete_scene`, `confirm_delete_scene`, `move_to_parent`. Layer events: `create_layer`, `set_active_layer`, `toggle_layer_visibility`, `update_layer_fog`, `start_rename_layer`, `rename_layer`, `set_pending_delete_layer`, `confirm_delete_layer`, `delete_layer`. Two completely disjoint vocabularies — easy split. |
| `move_to_parent` is shared between Show and the new sidebar (Show currently handles it for the scene tree). After migration only the sidebar handles it. | Low | Tree mutations move with the tree → sidebar. |
| `create_child_scene_from_zone` is fired from inside the Canvas (zone context menu), not from the sidebar tree | Low | Stays in Show — it's not a sidebar event. |
| `tree_panel_tab` (Layers/Scenes) currently lives in Show. After migration it belongs to the sidebar (sticky) so it persists across navigation. | Low | Move to sidebar with PubSub forwarding from Show for `hasLayers` / `hasScene`. |
| Highlight / `push_event("focus_element", ...)` from URL `?highlight=` requires `handle_params` access. | Low | Stays in Show — `handle_params` is allowed at route level. |
| `/scenes/new` route uses `SceneLive.Index :new`. Quick scan shows no `live_action`-driven branch in Index — the route may be a no-op dead-end or trigger something via params not yet inspected. | Medium | Investigate during step 0; either drop the route or carry it forward unchanged. |
| Background drag-drop (`phx-drop-target`) crosses a Vue/canvas boundary | Low | Untouched by migration; leave in Show. |
| Tests are pre-broken (PhoenixVite manifest mismatch from handoff) | Pre-existing | Will not block this migration; rely on browser verification + `mix compile --warnings-as-errors` + `mix format`. |

## What's currently true (snapshot)

### Routes (router.ex:172-184)

```elixir
live "/workspaces/:workspace_slug/projects/:project_slug/scenes",      SceneLive.Index, :index
live "/workspaces/:workspace_slug/projects/:project_slug/scenes/new",  SceneLive.Index, :new
live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id",  SceneLive.Show,  :show
live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/explore",
     SceneLive.ExplorationLive, :explore
live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/compare/:version_number",
     CompareLive.Scene, :compare
```

All five live in `live_session :require_authenticated_user`. The `:explore` and `:compare` routes intentionally do not get the project chrome (compact layout / immersive player).

### `SceneLive.Index` (`lib/storyarn_web/live/scene_live/index.ex`, 379 lines)

- Uses `Layouts.app` with `has_tree=true`, `tree_panel_open=true`, `tree_panel_pinned=false`, `show_pin=false`, `tree_props={scenesTree, canEdit, workspaceSlug, projectSlug, hasLayers: false}`.
- `mount/3` (line 83): manually loads project via `Projects.get_project_by_slugs`. Subscribes to `Collaboration.subscribe_dashboard(project.id)`. Loads `scenes_tree` via `Scenes.list_scenes_tree`. Async loads dashboard rows.
- `handle_params/3` (line 127): no-op.
- `handle_event` clauses (line 215-322): `tree_panel_*`, `sort_scenes`, `page_scenes`, `set_pending_delete_scene` / `set_pending_delete`, `confirm_delete_scene` / `confirm_delete`, `delete_scene` / `delete`, `create_scene`, `create_child_scene`, `move_to_parent`. Both legacy and current names exist.
- Imports `TreePanelHandlers` (line 18) and uses `focus_layout_defaults()` (line 95).
- Uses `DashboardHandlers` macro (line 7).

### `SceneLive.Show` (`lib/storyarn_web/live/scene_live/show.ex`, 2047 lines)

- Renders three modes: compact-with-no-scene (line 51), compact-with-scene (line 59 → `render_compact`), full (line 63 → `Layouts.app`).
- `Layouts.app` slots used:
  - `:top_bar_extra` (line 93-112): renders `SceneToolbar` (scene name, shortcut) AND `SearchPanel` (search query/filter/results) when `@scene` is loaded.
  - `:top_bar_extra_right` (line 113-122): `SceneActions` (edit_mode toggle, export, settings open).
- `mount/3` (line 351): manually loads project. Subscribes to `Collaboration.subscribe_restoration(project.id)` only. **Does not** subscribe to `subscribe_changes`, `subscribe_presence`, or `subscribe_locks` at mount — those happen per-scene in `setup_scene_collab/2` once a scene is loaded (line 491-510). Calls `focus_layout_defaults()` (line 367), seeds 40+ assigns including `:online_users = []`, `:tree_panel_tab = "scenes"`.
- `handle_params/3` (line 430): reads `?layout=compact`, calls `load_scene/2` if scene_id changed, handles `?highlight=` deep links (`focus_element` push_event).
- `load_scene/2` (line 469): teardown previous collab, fetch scene, call `setup_scene_collab` (which calls `Collab.setup({:scene, scene.id}, ...)` with `cursors: true, locks: true, changes: true`), then `assign_scene_state`, then async `:load_sidebar_data` for tree-with-elements + project_scenes/sheets/flows/variables.
- 60+ `handle_event` clauses (lines 691-1700). Tree mutations at 1660-1700, layer mutations at 1233-1281, tree_panel/tree_tab at 695-697.
- `handle_info` (1707-1875): async result, cross-LV selection, restoration, presence, cursors, locks, remote_change, refresh_locks.
- `terminate/2` (1878): teardown scene collab.

### `SceneLive.ExplorationLive` (`lib/storyarn_web/live/scene_live/exploration_live.ex`, 1812 lines)

Confirmed properties:
- Renders inside `<div id="exploration-root" class="w-full h-screen">` with `<.flash_group>` — does NOT render `<Layouts.app>` or `<ProjectShell>`.
- `mount/3` returns `{:ok, socket, layout: false}` (line 186).
- Zero `Collaboration.subscribe_*` calls. Zero `Phoenix.PubSub.subscribe`.
- Manually loads project via `Projects.get_project_by_slugs` (line 121).
- Pure player: handles `exploration_element_click`, `flow_continue`, `choose_response`, ambient flow timers.

**Conclusion**: ExplorationLive is the scenes equivalent of `FlowLive.PlayerLive`. Stays in `:require_authenticated_user`, untouched by this migration.

### `CompareLive.Scene`

In `:require_authenticated_user`. Uses `Layouts.compare`. Same boundary as `CompareLive.Sheet` and `CompareLive.Flow`. Stays out of `:project_scope` for this migration.

### Key assigns currently held by `SceneLive.Show` (selection of relevance)

| Assign | Owner after migration | Notes |
|---|---|---|
| `:project, :workspace, :membership, :can_edit` | ProjectScope hook (auto) | Drop manual load. |
| `:current_user, :is_super_admin, :urls` | ProjectScope hook (auto) | Drop manual derivation. |
| `:online_users` | Page LV (overwritten by scene-scope presence in load_scene) | Same gotcha as sheets. Keep. |
| `:restoration_banner` | Page LV | Forward to ProjectShell `restoration_banner` attr. |
| `:scene, :ancestors, :layers, :zones, :pins, :connections, :annotations, :ambient_flows, :scene_data` | Page LV | Stays. Used by Canvas + panels. |
| `:scenes_tree` | Sidebar LV | Move. |
| `:active_layer_id, :renaming_layer_id` | Sidebar LV (Layers tab) — but driven by Show's scene state | See "Open question 1". |
| `:tree_panel_tab` ("scenes" / "layers") | Sidebar LV | Move. |
| `:edit_mode, :active_tool` | Page LV | Stays — Canvas + Dock + SceneActions read these. Sidebar only needs `edit_mode` to gate layer mutations. |
| `:search_query, :search_filter, :search_results` | Page LV | Stays inline in `:top_bar_extras_left` slot. |
| `:selected_element, :selected_type, :element_panel_open, :scene_settings_open` | Page LV | Stays. |
| `:versions_panel_open, :history_data` | Page LV | Stays. |
| `:project_sheets, :project_flows, :project_scenes, :project_variables` | Page LV | Stays — consumed by ElementPropertiesPanel + Dock + SettingsPanel. |
| `:tree_panel_open, :tree_panel_pinned` | Sidebar LV | Move (per sheets pattern). |
| `:pending_delete_id` | Both? | Show currently uses it for `confirm_delete_scene` AND for layer/element deletes. Sidebar will need its own; Show keeps its own for non-tree deletes. |

### What `SceneSidebarLive` will receive at sticky-mount (session map, frozen)

Per `reference_phoenix_nested_lv_constraints.md`, the sticky session is set ONCE at first live_render. Subsequent state must arrive via PubSub.

```
%{
  "current_scope" => @current_scope,
  "project_id" => @project.id,
  "workspace_slug" => @workspace.slug,
  "project_slug" => @project.slug,
  "scene_id" => nil | "<id>",         # initial selection — updated via {:active_scene, id}
  "can_edit" => @can_edit,
  "active_tool" => "scenes",
  "dashboard_url" => ~p"/workspaces/.../scenes",
  # Layers-tab seed (only meaningful when scene_id present at first mount):
  "initial_layers" => [...],          # serialized layers list
  "initial_active_layer_id" => id | nil,
  "initial_edit_mode" => boolean
}
```

PubSub channel after first mount:
- `{:active_scene, id_or_nil}` from Show.handle_params / Index.mount.
- `{:scene_payload_changed, %{layers, active_layer_id, edit_mode}}` from Show whenever any of the three change.
- `{:tree_changed, :scenes}` from sidebar after a tree mutation, so Index can refresh its dashboard.
- `{:open_scene, id}` from sidebar after `create_scene` / `create_child_scene` so Index can `push_navigate`.
- `{:toolbar_event, "tree_panel_" <> _, _}` forwarded by Show/Index from LeftToolbar.

## Numbered step-by-step plan

> Each step lists files touched, verification, and bisectability. **Bisectable** means the app fully works between commits — a `git bisect` lands on a working state.

---

### Step 0 — Pre-flight investigation (no code)

Time: 30 min. No commit.

1. Verify `/scenes/new` actually does anything by clicking it in the running dev server. If it just renders the same Index page (no `live_action`-driven UI), document it and decide:
   - (a) Keep route, no special handling (current behavior — does nothing).
   - (b) Drop the route — fewer lines, less surface.
2. Confirm `SceneTreePanel.vue` already accepts `selectedSceneId` (it does, line 22) and that `SceneLayerList.vue` doesn't depend on parent state we'd lose by moving it (verified: it `useLive()`s and pushes to whatever LV roots it).
3. Confirm `tree_props` shape today is what `SceneTreePanel.vue` expects — check `app_layout.ex:227` passes through and `TreePanel.vue:36` forwards `treeProps` into the active tree component.
4. Run `mix compile --warnings-as-errors` to record baseline (should be clean).

**Output**: a one-line note in the commit log of step 1 confirming `/scenes/new` decision.

---

### Step 1 — Add `canvas_mode` to `ProjectShell`

**Files touched**:
- `lib/storyarn_web/components/project_shell.ex` — add `canvas_mode` attr; switch `<main>` `class` to a cond mirroring `app_layout.ex:233-243`.

**What it does**: Introduces a new optional attr `canvas_mode :boolean, default: false`. When true, `<main>` becomes `class="h-full overflow-hidden"` (no `pt-`, no `px-`, no `pb-`, no `pl-` from sidebar). When false, behavior is unchanged from today.

**Verification**:
- `mix compile --warnings-as-errors` — clean.
- Browse `/sheets`, `/sheets/:id`, `/localization`, `/localization/texts/:locale`, `/workspaces/:ws/projects/:p`, `/workspaces/:ws/projects/:p/assets`. None of these use `canvas_mode`, so all should look identical to before.

**Bisectable**: Yes — pure additive change with no callers using the new attr.

---

### Step 2 — Create `SceneSidebarLive`

**Files touched (new)**:
- `lib/storyarn_web/live/scene_sidebar_live.ex` (new, ~250 lines).

**Files touched (existing)**: None. The sidebar is wired in only when Show/Index switch to ProjectShell (steps 4/5).

**What it does**: New module modeled on `SheetsSidebarLive`. Differences:

1. `mount/3` reads from session: `current_scope`, `project_id`, `workspace_slug`, `project_slug`, `scene_id`, `can_edit`, `active_tool`, `dashboard_url`, `initial_layers`, `initial_active_layer_id`, `initial_edit_mode`. Loads project via `Projects.get_project`. Loads `scenes_tree` via `Scenes.list_scenes_tree_with_elements/1` and `prepare_scenes_tree`. Subscribes to shell topic + `Collaboration.subscribe_changes({:project, project_id})`. Returns `{:ok, socket, layout: false}`.

2. Assigns:
   - `:scenes_tree` (loaded).
   - `:scene_id` (from session).
   - `:layers, :active_layer_id, :edit_mode` (seeded from session; updated via PubSub).
   - `:tree_panel_tab` ("scenes" always by default; user manually switches via tab UI).
   - `:tree_panel_open, :tree_panel_pinned` (mirror sheets default — `false, true`).
   - `:pending_delete_scene_id, :pending_delete_layer_id` (separate, since both flows route here).

3. `render/1` renders TreePanel with active-tool="scenes" and `tree_props` containing scenesTree, selectedSceneId, layers, activeLayerId, editMode, hasScene, hasLayers, plus `on-dashboard={is_nil(@scene_id)}` for the dashboard-active highlight.

4. `handle_event` clauses:
   - `tree_panel_init`, `tree_panel_toggle`, `tree_panel_pin` — same shape as SheetsSidebarLive.
   - **Tree mutations** (move from Show + Index):
     - `create_scene`, `create_child_scene` (`%{"parent_id"}`), `set_pending_delete_scene` (`%{"id"}`), `confirm_delete_scene`, `move_to_parent` (`%{"item_id", "new_parent_id", "position"}`).
   - **Layer mutations** (per open question 1, default option A): `set_active_layer`, `toggle_layer_visibility`, `update_layer_fog`, `create_layer`, `start_rename_layer`, `rename_layer`, `set_pending_delete_layer`, `confirm_delete_layer`, `delete_layer`.

5. `handle_info`:
   - `{:active_scene, id}` → assign `:scene_id, id`.
   - `{:scene_payload_changed, %{layers, active_layer_id, edit_mode}}` → assign all three.
   - `{:tree_changed, :scenes}` → reload tree.
   - `{:remote_change, action, _}` when `action in [:tree_changed, :scene_updated, :scene_restored, :layer_updated]` → reload tree.
   - `{:remote_change, _, _}` → noop.
   - `{:toolbar_event, "tree_panel_" <> _, _}` → reuse panel state mutation logic.

6. `defp shell_topic/1` (mirrors SheetsSidebarLive:278).

**Verification**:
- `mix compile --warnings-as-errors` — clean. Module is unused at this point.
- `mix format` — clean.

**Bisectable**: Yes — module exists but no LV references it; app behavior unchanged.

---

### Step 3 — Migrate `SceneLive.Index` to ProjectShell

**Files touched**:
- `lib/storyarn_web/router.ex` — move `scenes` (`:index`) and `scenes/new` (`:new`) routes from `:require_authenticated_user` into `:project_scope`.
- `lib/storyarn_web/live/scene_live/index.ex`:
  - Drop `import StoryarnWeb.Live.Shared.TreePanelHandlers`.
  - Drop `alias Storyarn.Projects` (no longer needed).
  - Add `alias StoryarnWeb.Live.Shared.ProjectChromeHelpers`.
  - Rewrite `mount/3`: signature becomes `mount(_params, _session, socket)`, reads `%{project: project} = socket.assigns`. Drop `focus_layout_defaults()`. Drop manual `get_project_by_slugs`. Subscribe to shell topic; broadcast `{:active_scene, nil}` (mirror SheetLive.Index:94-98). Keep dashboard-related assigns. Drop `:scenes_tree` and `:tree_panel_open` — those move to the sidebar.
  - `handle_params/3` — keep no-op.
  - `handle_event "tree_panel_" <> _` — replace `handle_tree_panel_event` with `ProjectChromeHelpers.forward_tree_panel/3`.
  - **Drop tree-mutation handlers**: `set_pending_delete_scene`, `confirm_delete_scene`, `delete_scene`, `create_scene`, `create_child_scene`, `move_to_parent`, plus the legacy aliases.
  - Add `handle_info {:open_scene, id}` → `push_navigate`, `{:active_scene, _}, do: noop`, `{:tree_changed, :scenes}` → `reload_scenes`, `{:toolbar_event, _, _}` noop, `{:online_users, users}` assign.
  - Replace `<Layouts.app>` render with `<ProjectShell.project_shell>` mirroring SheetLive.Index. Set `sidebar_module={StoryarnWeb.SceneSidebarLive}` and `sidebar_session=%{... scene_id: nil ...}`. Pass `online_users={@online_users}`. **Don't set `canvas_mode`**.

**Verification**:
- `mix compile --warnings-as-errors` — clean.
- Browse `/scenes`:
  - Dashboard renders, table loads.
  - Sidebar (sticky) shows scenes tree.
  - Click a scene in the tree → `push_navigate` to Show works.
  - Create scene from sidebar → success: navigates to new scene.
  - Move a scene via DnD → tree updates AND dashboard table reloads.
  - Soft-delete a scene from tree → trash flash, tree refresh, dashboard reload.
  - Tree-panel toggle from LeftToolbar pill works.
  - Right-toolbar shows current online users.
- Browse `/scenes/new` — verify decision from step 0 holds.
- Tool switcher in LeftToolbar — switch to /sheets, then back to /scenes — sidebar persists, no white-flash.

**Bisectable**: Yes — Index works on its own. Show is still on `Layouts.app`; navigating /scenes → /scenes/:id crosses live_session boundaries (`:project_scope` → `:require_authenticated_user`), tearing down the sticky sidebar. That's expected and acceptable for this intermediate state — fixed in step 4.

---

### Step 4 — Migrate `SceneLive.Show` to ProjectShell

**Files touched**:
- `lib/storyarn_web/router.ex` — move `scenes/:id` (`:show`) route into `:project_scope`. Leave `:explore` and `:compare` in `:require_authenticated_user`.
- `lib/storyarn_web/live/scene_live/show.ex`:
  - **Mount changes**:
    - Signature → `mount(_params, _session, socket)`.
    - Read `%{project: project, can_edit: can_edit} = socket.assigns`.
    - Drop manual `get_project_by_slugs`.
    - Drop `focus_layout_defaults()` call. Set `:online_users` explicitly via `ProjectChromeHelpers.initial_online_users(project.id)`.
    - Drop `:tree_panel_open`, `:tree_panel_pinned`, `:tree_panel_tab` — sidebar owns these now. Also drop `:scenes_tree`.
    - Keep `:active_layer_id` AND broadcast it whenever it changes (sidebar mirrors via PubSub).
    - Add `Phoenix.PubSub.subscribe(..., ProjectChromeHelpers.shell_topic(project.id))`.
    - Keep `Collaboration.subscribe_restoration(project.id)` and `Collaboration.subscribe_changes({:project, project.id})`.
  - **handle_params changes**: add `Phoenix.PubSub.broadcast(..., shell_topic, {:active_scene, scene_id})` mirror sheets pattern.
  - **load_scene changes**: after `assign_scene_state`, broadcast `{:scene_payload_changed, %{layers, active_layer_id, edit_mode}}`.
  - **handle_event tree mutations**: REMOVE `create_scene`, `create_child_scene`, `set_pending_delete_scene`, `confirm_delete_scene`, `delete_scene`, `move_to_parent`. KEEP `create_child_scene_from_zone`.
  - **handle_event layer mutations** (per open question 1): REMOVE all layer mutations.
  - **handle_event `tree_panel_*`**: replace `handle_tree_panel_event` with `ProjectChromeHelpers.forward_tree_panel/3`.
  - **handle_event `switch_tree_tab`**: REMOVE — sidebar owns the tab state.
  - **handle_info changes**: add `{:active_scene, _}` (no-op for Show), `{:open_scene, id}` (push_navigate), `{:tree_changed, :scenes}` (no-op — sidebar handles), `{:active_layer_changed, id}` (assign `:active_layer_id`), `{:online_users, users}`, `{:toolbar_event, _, _}` (no-op).
  - **Drop `import TreePanelHandlers`**.
  - **Render changes**:
    - Replace `<Layouts.app ...>` with `<ProjectShell.project_shell ...>`.
    - Pass `restoration_banner={@restoration_banner}`, `online_users={@online_users}`, `active_tool={:scenes}`, `is_super_admin`, `current_user`, `urls`, `current_scope`, `project`, `workspace`.
    - **`canvas_mode={true}`** — wired from step 1.
    - `sidebar_module={StoryarnWeb.SceneSidebarLive}`.
    - `sidebar_session=%{... scene_id: @scene && to_string(@scene.id), initial_layers: serialize_layers(@layers), initial_active_layer_id: @active_layer_id, initial_edit_mode: @edit_mode, ... }`.
    - `:top_bar_extras_left` slot (replaces `:top_bar_extra`): inline `SceneToolbar` and `SearchPanel` guarded by `:if={@scene}`.
    - `:top_bar_extras_right` slot (replaces `:top_bar_extra_right`): inline `SceneActions` guarded by `:if={@scene}`.
    - **Important**: SceneToolbar and SearchPanel have reactive props. Per `reference_livevue_nested_lv_race.md`, in the shell context with reactive props, they MAY need `phx-update="ignore"` + dynamic id keyed on a signature — TEST in browser.
  - **Render compact mode**: Untouched. `Layouts.compare` continues to work for `?layout=compact`.

**Verification**:
- `mix compile --warnings-as-errors` — clean.
- `mix format` — clean.
- Browse `/scenes/:id`:
  - Canvas renders full-bleed.
  - Top-left: LeftToolbar, then SceneToolbar (name/shortcut), then SearchPanel.
  - Top-right: SceneActions, then RightToolbar (presence).
  - Sticky sidebar: scenes tree + layers tab.
  - Edit a layer name in sidebar → name updates immediately.
  - Toggle layer visibility → canvas re-renders.
  - Tree mutation: create child scene from sidebar → navigates to new scene.
  - Tree mutation from canvas (right-click zone → "Create child scene") → still works.
  - Drag-drop background image → uploads, scene updates.
  - Edit mode toggle → Canvas, Dock, SettingsPanel react.
  - Search → SearchPanel, results show, click result → focus_element fires.
  - Save name from SceneToolbar → persists.
  - Restoration banner on this project → banner shows above toolbars.
  - Tool switcher: /scenes/:id → /sheets/:id → back. Sidebar should switch chromes.
  - Navigate /scenes/:id_a → /scenes/:id_b via tree click.
  - Open `?layout=compact` URL → compact render works.
  - Open `?highlight=pin:123` → focus_element pushed.
- Multi-user test: pin moves, cursors, locks, sidebar tree mutations propagate.

**Bisectable**: Yes if everything in step 2 + 3 + 4 lands together.

**Edge case to test explicitly**: tab persistence. Open scene A, switch to Layers tab in sidebar, navigate to scene B via tree → tab should stay on Layers, but show scene B's layers.

---

### Step 5 — Verify ExplorationLive and CompareLive.Scene unaffected

**Files touched**: None.

**Verification**:
- `/scenes/:id/explore` → ExplorationLive renders, full screen, no chrome.
- `/scenes/:id/compare/:n` → CompareLive.Scene renders side-by-side compact view, no chrome.

**Bisectable**: Trivially.

---

### Step 6 — Cleanup pass

**Files touched**:
- `lib/storyarn_web/live/scene_live/handlers/tree_handlers.ex` — Show no longer calls `handle_create_scene`, `handle_create_child_scene`, `handle_delete_scene`, `handle_move_to_parent`. Move tree CRUD into sidebar inline; keep `tree_handlers.ex` shrunk to `handle_create_child_scene_from_zone` and `handle_navigate_to_target`.
- `lib/storyarn_web/live/scene_live/index.ex` — verify dead alias removal.
- `lib/storyarn_web/live/scene_live/show.ex` — verify dead alias / import removal.

**Verification**:
- `mix compile --warnings-as-errors` — clean.
- `mix format` — clean.
- All step 4 browser tests still pass.

**Bisectable**: Yes.

---

## Open questions for the user

1. **Layer mutations: in sidebar or in Show?** — RESOLVED 2026-04-16: **Option B**. Sidebar forwards layer events as `{:layer_event, name, params}` PubSub messages on the shell topic; Show handles them via existing `LayerHandlers` (zero changes to layer mutation code). Rationale: layers are deeply coupled to Show's undo stack, auto-snapshot scheduler, collab `_broadcast` flag, and canvas `push_event`s. Option A would require duplicating all of that in sidebar. Option B: `handlers/layer_handlers.ex` stays untouched.

   **Future direction (out of scope, separate refactor)**: move Layers/Legend/SceneSettings into a **right-side dock** next to the canvas (à la Figma/Photoshop/Blender). Eliminate the Layers tab from the left sidebar entirely; eliminate the PubSub forwards. Dock panels live inside Show → `useLive()` pushes directly to Show. User approved direction 2026-04-16.

2. **Tree-tab default** — RESOLVED 2026-04-16: tab defaults to `"scenes"` always (Index and Show). User manually switches to `"layers"` when needed; choice persists for the session. Future work may move the Layers UI elsewhere (out of scope here). User: "Vamos a dejar el tab de scenes por defecto entonces siempre, en todos los casos. Ya veremos que hacemos con layers. A lo mejor tiene sentido cambiarlo de lugar. Pero eso está fuera del scope actual."

3. **`/scenes/new` route**: After step 0 verification, drop or keep? **Default**: keep as no-op for backward compatibility unless step 0 reveals it's actually unused.

4. **`SearchPanel` and `SceneToolbar` as inline slots vs. their own sticky LV?** Their state (search query, results) is page-scoped, so navigation between scenes resets them. **Default**: inline.

5. **`SceneActions` as inline slot?** Edit mode toggle is per-scene. **Default**: inline.

6. **Should `CompareLive.Scene` move into `:project_scope`?** It uses `Layouts.compare`, not the project chrome, so the only benefit is dropping the manual project load (~15 lines). **Default**: leave for a later sweep that handles all three Compare LVs together.

7. **Scene-scope `:online_users` overwriting project-scope `:online_users`** is a known shared pattern with sheets. Should we eventually split (e.g., `:project_online_users` vs `:scene_online_users`)? **Default**: out of scope; revisit when migrating flows (which has cursors).

## Risk register: things to revalidate in the browser

- [ ] Canvas full-bleed: ensure no 76px offset, no horizontal scroll, `overflow-hidden` on `<main>`.
- [ ] Drag-and-drop background upload: file lands inside `phx-drop-target` (the wrapper `scene-canvas-wrapper`), upload progresses, scene updates.
- [ ] Konva canvas scroll/zoom: works within the canvas-only area; no parent scroll interference.
- [ ] Presence: project online users in RightToolbar (project scope) AND scene-scope presence (cursors / locks for collab). Two separate channels — both should display.
- [ ] Locks: select element in A, B sees lock badge; release in A, B can edit.
- [ ] Cursors: live cursor positions between two browsers.
- [ ] Drag relays (pin, annotation, zone): smooth movement on remote browser without DB round-trip.
- [ ] Tree mutations propagate: A creates a scene → B's sidebar tree reloads.
- [ ] Layer mutations propagate: A renames a layer → B's canvas updates layer label.
- [ ] LiveVue race: open dev console, navigate `/scenes` → `/scenes/:id` → `/scenes/:id_b` → `/sheets` → back; check for `Cannot read properties of undefined (reading 'props')` errors.
- [ ] Restoration banner: trigger a project restoration; banner appears above all chrome on Index AND Show.
- [ ] `?highlight=pin:N`, `?highlight=zone:N` deep links continue to focus.
- [ ] `?layout=compact` continues to render `Layouts.compare`.
- [ ] Tool switcher links use `live_redirect` (not plain `<a href>`).
- [ ] Tab switcher in TreePanel (Layers / Scenes) toggles correctly when on a scene; only "Scenes" shows on the dashboard.
- [ ] Active scene highlight in tree: navigating between scenes via tree clicks updates the highlighted item.
- [ ] Dashboard active-state: navigating from `/scenes/:id` back to `/scenes` clears the highlight (because of `{:active_scene, nil}` broadcast in Index.mount).

## Estimated commit shape (likely 4-5 commits)

| # | Commit | Files | Bisectable |
|---|---|---|---|
| 1 | `feat(shell): add canvas_mode attr to ProjectShell` | `project_shell.ex` | Yes — additive |
| 2 | `feat(scenes): add SceneSidebarLive` | new file `scene_sidebar_live.ex` | Yes — unused |
| 3 | `feat(scenes): migrate Index to ProjectShell` | `router.ex`, `index.ex` | Yes — Index works; Show still on Layouts.app |
| 4 | `feat(scenes): migrate Show to ProjectShell with sticky sidebar` | `router.ex`, `show.ex`, possibly `tree_handlers.ex` cleanup | Yes |
| 5 (optional) | `chore(scenes): drop dead aliases / shrink TreeHandlers` | `index.ex`, `show.ex`, `tree_handlers.ex` | Yes |

Alternative shape: collapse 3+4 into a single commit if the intermediate "Index migrated, Show still on app layout" state is uncomfortable to ship. Recommended to keep them separate for bisect.

---

## Appendix A — Vue event vocabulary

What `SceneSidebarLive` will receive (from `SceneTree.vue` and `SceneLayerList.vue`):

| Event | Source line | Params | Today handled by |
|---|---|---|---|
| `create_scene` | SceneTree.vue:81 | `{}` | Show + Index |
| `create_child_scene` | SceneTree.vue:85 | `{ parent_id }` | Show + Index |
| `set_pending_delete_scene` | SceneTree.vue:95 | `{ id }` | Show + Index |
| `confirm_delete_scene` | SceneTree.vue:98 | `{}` | Show + Index |
| `move_to_parent` | SceneTree.vue:177 | `{ item_id, new_parent_id, position }` | Show + Index |
| `set_active_layer` | SceneLayerList.vue:48 | `{ id }` | Show |
| `toggle_layer_visibility` | SceneLayerList.vue:52 | `{ id }` | Show |
| `create_layer` | SceneLayerList.vue:56 | `{}` | Show |
| `rename_layer` | SceneLayerList.vue:71 | `{ id, name }` | Show |
| `update_layer_fog` | SceneLayerList.vue:81 | `{ ... }` | Show |
| `set_pending_delete_layer` | SceneLayerList.vue:95 | `{ id }` | Show |
| `confirm_delete_layer` | SceneLayerList.vue:98 | `{}` | Show |
| `tree_panel_init` / `_toggle` / `_pin` | TreePanel.vue:75 + LeftToolbar.vue | various | Page LV → forwarded to sidebar |

What stays in `SceneLive.Show` (from canvas + panels):

- All canvas events (pin/zone/connection/annotation CRUD, drag, select, deselect).
- All right-panel events (element properties, scene settings, version history).
- All keyboard shortcuts (`delete_selected`, `duplicate_selected`, `copy_selected`, `paste_element`, `undo`, `redo`).
- Toolbar inline slots: `save_name` (from SceneToolbar), `search_*` (from SearchPanel), `toggle_edit_mode`/`export_scene`/`open_scene_settings` (from SceneActions).
- `create_child_scene_from_zone` (canvas right-click, not sidebar).
- `navigate_to_target`, `navigate_to_referencing_flow`.
- `validate_bg_upload`, background drop/upload progress.

## Appendix B — File path quick reference

- `lib/storyarn_web/live/scene_live/index.ex` — page LV (379 lines)
- `lib/storyarn_web/live/scene_live/show.ex` — page LV (2047 lines)
- `lib/storyarn_web/live/scene_live/exploration_live.ex` — out of scope (1812 lines)
- `lib/storyarn_web/live/scene_live/handlers/tree_handlers.ex` — half moves, half stays
- `lib/storyarn_web/live/scene_live/handlers/{layer,element,canvas_event,collaboration,undo_redo}_handlers.ex` — stay with Show
- `lib/storyarn_web/live/scene_live/helpers/{props_serializer,scene_helpers,scene_serializer}.ex` — stay with Show; sidebar may import `prepare_scenes_tree` and `prepare_layers_for_vue`
- `lib/storyarn_web/components/project_shell.ex` — add `canvas_mode` attr
- `lib/storyarn_web/live/scene_sidebar_live.ex` — NEW
- `lib/storyarn_web/live/sheets_sidebar_live.ex` — model
- `lib/storyarn_web/live/sheet_live/show.ex`, `index.ex` — patterns to mirror
- `lib/storyarn_web/router.ex` lines 173-183 — routes to relocate
- `assets/app/modules/scenes/components/SceneTreePanel.vue`, `SceneTree.vue`, `SceneLayerList.vue` — no changes expected
- `assets/app/components/layout/TreePanel.vue` — no changes expected

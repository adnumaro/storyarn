# ProjectShell pivot — LV shell → function component + sticky LVs

**Status:** planning (2026-04-15)
**Branch:** feat/live-vue-sheets
**Trigger:** current `<%= if @sheet_id do %>` in `ProjectShellLive.render` is ugly; user wants each page to be its own LV with a shared layout wrapper.

## Target architecture

```
live_session :project_scope  (on_mount loads project + workspace)
 ├─ live "/sheets",        SheetLive.Index,  :index
 ├─ live "/sheets/:id",    SheetLive.Show,   :show
 ├─ live "/sheets/:id/edit", SheetLive.Show, :edit
 └─ ... (flows, scenes, screenplays later)

SheetLive.Show.render:
  <ProjectShell.project_shell ...>
    <!-- sheet content -->
  </ProjectShell.project_shell>

ProjectShell.project_shell (function component):
  - live_render(@socket, ToolbarsLive, id: "toolbars-#{project.id}", sticky: true, ...)
  - live_render(@socket, SidebarLive,  id: "sidebar-#{project.id}",  sticky: true, ...)
  - <main>{render_slot(@inner_block)}</main>

ToolbarsLive, SidebarLive:
  - Same as today internally.
  - mount returns {:ok, socket, layout: false}  (required by sticky).
  - Ids stable per project → survive navigation between Index/Show.
```

## Why this works

- `sticky: true` keeps the nested LV process alive across `live_redirect`/`live_patch` within the same `live_session` ([Phoenix docs](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#live_render/3)).
- Sticky constraint: nested LV must use `layout: false` to avoid double-wrapping with the parent's layout. ToolbarsLive and SidebarLive need this.
- Page LV (Show/Index) uses `<.project_shell>` in its render; the shell's function component emits the sticky `live_render` calls. Each page invocation reconciles to the same nested LV process by id.

## What current code maps to what

| Today                                                    | After pivot                                                                                        |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `StoryarnWeb.ProjectShellLive` (LV, route target)        | `StoryarnWeb.Components.ProjectShell` (function component, no LV)                                  |
| Shell loads project/workspace in mount                   | `on_mount {ProjectScope, :load_project}` hook in live_session                                      |
| Shell's `handle_params` broadcasts `{:active_sheet, id}` | Each page LV's `handle_params` broadcasts it                                                       |
| Shell's `handle_info({:open_sheet, id})` → `push_patch`  | Each page LV's `handle_info({:open_sheet, id})` → `push_navigate` (different URL, sticky survives) |
| Shell's subscribe to shell_topic                         | Each page LV subscribes in mount                                                                   |
| `SheetLive.Show.mount(:not_mounted_at_router, ...)`      | Removed. Show returns to route-level mount signature.                                              |
| `SheetLive.Show` no `handle_params` (was nested)         | Restored (it's route-level again).                                                                 |
| `SheetLive.Index.mount(:not_mounted_at_router, ...)`     | Removed. Same as Show.                                                                             |
| `SheetLive.Index` no `handle_params` (was nested)        | Restored.                                                                                          |
| `SheetLive.Show.render` wraps in `<Layouts.app>`         | Wraps in `<ProjectShell.project_shell>` instead. **No more duplicate toolbars/sidebar.**           |
| `SheetLive.Index.render` wraps in `<Layouts.app>`        | Wraps in `<ProjectShell.project_shell>` instead.                                                   |

## Files

### Create

1. `lib/storyarn_web/components/project_shell.ex` — function component `project_shell/1`.
2. `lib/storyarn_web/live/hooks/project_scope.ex` — `on_mount {ProjectScope, :load_project}` hook. Reads `workspace_slug` + `project_slug` from params, loads project + workspace + membership + `can_edit`, assigns.

### Modify

3. `lib/storyarn_web/router.ex`:
   - Remove `ProjectShellLive` routes.
   - Add new `live_session :project_scope` nested inside the existing `:require_authenticated_user` (or as a sibling) with `on_mount: [..., {ProjectScope, :load_project}]`.
   - Point sheet routes directly to `SheetLive.Index` / `SheetLive.Show` with the new session.

4. `lib/storyarn_web/live/sheet_live/show.ex`:
   - Remove `mount(:not_mounted_at_router, ...)` clause.
   - Restore `handle_params/3`.
   - Change `render_full` to wrap in `<ProjectShell.project_shell>` instead of `<Layouts.app>`.
   - Subscribe to `SidebarLive.shell_topic(project.id)` in mount.
   - Add `handle_info({:open_sheet, id})` → `push_navigate` to the sheet URL.
   - Add `handle_info({:active_sheet, _})` no-op (this page already has the sheet loaded).
   - Broadcast `{:active_sheet, sheet_id}` in `handle_params` (replaces what shell did).

5. `lib/storyarn_web/live/sheet_live/index.ex`:
   - Remove `mount(:not_mounted_at_router, ...)` clause.
   - Restore no-op `handle_params/3`.
   - Change render to wrap in `<ProjectShell.project_shell>` instead of `<Layouts.app>`.
   - Subscribe to `SidebarLive.shell_topic(project.id)` in mount.
   - Add `handle_info({:open_sheet, id})` → `push_navigate` to the sheet URL.
   - Remove the tree mutation handlers (`create_sheet`, `create_child_sheet`, `move_to_parent`, `set_pending_delete_sheet`/`set_pending_delete`, `confirm_delete`/`confirm_delete_sheet`, `delete`/`delete_sheet`) — they now live in `SidebarLive`. The `sort_sheets`/`page_sheets`/dashboard handlers stay.

6. `lib/storyarn_web/live/toolbars_live.ex`:
   - Change `mount` to return `{:ok, socket, layout: false}`.

7. `lib/storyarn_web/live/sidebar_live.ex`:
   - Change `mount` to return `{:ok, socket, layout: false}`.

### Delete

8. `lib/storyarn_web/live/project_shell_live.ex` — replaced by `ProjectShell` component + `ProjectScope` hook.

## Communication patterns (unchanged, just different home)

- **Shell topic**: `"project:#{project_id}:shell"` (helper `StoryarnWeb.SidebarLive.shell_topic/1`). Still used.
- **`{:active_sheet, id}`**: broadcasted by current page LV on `handle_params`, consumed by SidebarLive to update `selectedSheetId`.
- **`{:open_sheet, id}`**: broadcasted by SidebarLive after creating a sheet, consumed by current page LV → `push_navigate` to the new sheet URL.
- **`{:tree_changed, :sheets}`**: broadcasted by SidebarLive after mutations (using `broadcast_from` to avoid self-echo), consumed by other clients' SidebarLive to refresh their tree.

## Order of steps (verifiable per step)

Each step must leave the app compiling and navigable. Since we're not committing until sheets are fully done, revert by hand if any step breaks.

### Step 1 — Create the `ProjectScope` on_mount hook

- File: `lib/storyarn_web/live/hooks/project_scope.ex`
- `on_mount(:load_project, params, _session, socket)`: reads slugs, loads project + workspace + membership + computes `can_edit`, assigns all four. On auth error, halts with flash.
- Verify: compile, no app wiring yet.

### Step 2 — Create `ProjectShell` function component

- File: `lib/storyarn_web/components/project_shell.ex`
- Exposes `project_shell/1` with attrs: `project`, `workspace`, `current_scope`, `can_edit`, `sheet_id`, `active_tool`, `urls`, `current_user`, `is_super_admin`, `dashboard_url`, `socket`. Slot: `inner_block`.
- Renders:
  - `live_render(@socket, ToolbarsLive, id: "toolbars-#{project.id}", sticky: true, session: %{...})`
  - `live_render(@socket, SidebarLive,  id: "sidebar-#{project.id}",  sticky: true, session: %{...})`
  - `<main>{render_slot(@inner_block)}</main>` with appropriate padding (mirror what Layouts.app does around main content).
- Verify: compile.

### Step 3 — Add `layout: false` to Toolbars/Sidebar mounts

- Files: `toolbars_live.ex`, `sidebar_live.ex`
- Change `{:ok, socket}` → `{:ok, socket, layout: false}`.
- Verify: compile. They still render correctly if invoked from current shell (which still exists at this point).

### Step 4 — Add new `live_session :project_scope` to router

- File: `router.ex`
- Add a new `live_session` nested under `:require_authenticated_user` with the existing auth hooks PLUS `{ProjectScope, :load_project}`. Move sheet routes in. Point them directly to `SheetLive.Index` and `SheetLive.Show` (not ProjectShellLive).
- Verify: compile. At this point the pages will crash because Show/Index have the `:not_mounted_at_router` mount clause and their render still uses `<Layouts.app>` referencing assigns the new hook provides differently. But it compiles. This is the transition moment.

### Step 5 — Revert `SheetLive.Show` to route-level

- Remove `mount(:not_mounted_at_router, ...)`.
- Restore `handle_params/3` with the compact/load logic it had.
- Adjust the main `mount/3`: since `project`, `workspace`, `membership`, `can_edit` now come from `ProjectScope` hook, drop the duplicate loading here. Keep everything else (collab subscribe, sheet mount, etc.).
- Change render to use `<ProjectShell.project_shell>` wrapper instead of `<Layouts.app>`.
- Add `handle_info({:active_sheet, _})` no-op and `handle_info({:open_sheet, id})` → `push_navigate`.
- Subscribe to shell_topic in mount.
- Broadcast `{:active_sheet, id}` in `handle_params` after assigning sheet_id.
- Verify: navigate to `/sheets/384`. Should load. Toolbars + sidebar should appear (now sticky inside ProjectShell).

### Step 6 — Revert `SheetLive.Index` to route-level

- Same changes as Step 5, adapted: no `handle_params` logic beyond no-op, restore it.
- Render wraps in `<ProjectShell.project_shell>`.
- Remove the tree mutation handlers (create_sheet, create_child_sheet, delete family, move_to_parent) — these fire against SidebarLive now.
- Subscribe to shell_topic + `handle_info({:open_sheet, id})` → `push_navigate`.
- Verify: `/sheets` loads the dashboard. Toolbars/sidebar persist when navigating from dashboard to a sheet and back.

### Step 7 — Delete `ProjectShellLive`

- `rm lib/storyarn_web/live/project_shell_live.ex`.
- Verify: compile + smoke test both routes.

### Step 8 — Full smoke test

- Navigate `/sheets` → click tree item → `/sheets/:id` → create new sheet → delete → move.
- Confirm: toolbars/sidebar survive ALL navigations (sidebar ping counter would prove persistence, but we already validated it — just watch online_users stay correct).
- Confirm: no LiveVue race (check console).
- Confirm: no duplicate toolbars/sidebar (killed by removing Layouts.app from Show/Index).

## Risks / open questions

1. **Sticky + session passing**: each page LV's render calls `project_shell` → which calls `live_render(..., session: %{...})`. On first render of the sticky child, the session is used for mount. On subsequent invocations (page LV change), does Phoenix re-use the existing nested process and **ignore** the new session? Answer from docs: yes, sticky preserves the existing process; new session args in subsequent live_render calls are ignored. This is important because `sheet_id` may change between pages, but sidebar receives updates via PubSub (`{:active_sheet, id}`), not via session — so this is fine. **Verify in step 5 that sidebar's `@sheet_id` updates correctly when navigating Index → Show.**

2. **Duplicate subscribe to shell_topic**: if both Index and Show subscribe, and user navigates Index → Show, the old Index's subscription ends when process dies. No leak. Fine.

3. **Mount cost**: each page LV runs full mount on navigation (Show mount is expensive — loads sheet, blocks, etc). That's the same as today. Sticky doesn't help here; the page LV is the one that remounts, not sidebar/toolbars.

4. **Flash of content**: unavoidable. The main area swaps content. Toolbars/sidebar stay.

5. **`layout: false` interaction with root.html.heex**: sticky children with `layout: false` still get wrapped in `root.html.heex`? Actually no — `layout: false` means no Phoenix _LiveView_ layout (skips app.html.heex). `root.html.heex` is the Plug-level layout, always applied. Since sticky children are rendered as separate LV processes, they technically get their own full HTML scaffolding... hmm, need to verify. If it breaks we fix by investigating `root_layout` config.

6. **URLs in new sheet creation**: SidebarLive broadcasts `{:open_sheet, id}`. Current page LV receives it and does `push_navigate(~p"/workspaces/.../sheets/#{id}")`. If we're on Index and create a sheet, we navigate to Show. If we're on Show viewing sheet 1 and create a new one, we navigate to the new sheet's Show. Both work.

7. **Compact mode query param**: `SheetLive.Show.handle_params` currently reads `params["layout"] == "compact"`. Needs to be preserved after the revert.

## Criterio de éxito

- Ningún `<%= if %>` en render del shell.
- `SheetLive.Show`, `SheetLive.Index` son LVs route-level de primera clase otra vez.
- Toolbars + sidebar sobreviven navegación Index ↔ Show (verificable: online_users no desaparecen, sheets_tree no pierde estado como filtro).
- Sin toolbars duplicados, sin árboles duplicados.
- Sin crash de LiveVue.
- Crear/mover/borrar hojas funciona (sigue viviendo en SidebarLive).

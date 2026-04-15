# Localization migration to ProjectShell

**Status:** planning (2026-04-15)
**Branch:** feat/live-vue-sheets
**Scope decision:** start with localization (3 LVs, few events, no collab, no canvas). Flows next (111 events, heavy toolbar, canvas mode — harder).

## Context recap

Sheets already lives under ProjectShell. Current chrome:

- `ProjectShell.project_shell` (function component): renders via `live_render(sticky: true)` →
  - `ToolbarsLive` — LeftToolbar + RightToolbar (project/workspace nav, tool switcher, user menu, presence).
  - `SidebarLive` — sheets-specific tree + mutations.
  - `<main>{slot}</main>` — page content, padding reacts to sidebar open state.
- `live_session :project_scope` with `ProjectScope.load_project` on_mount hook → loads `project`, `workspace`, `membership`, `can_edit`, `current_user`, `is_super_admin`, `urls`.

## What localization looks like today

3 route-level LVs under `:require_authenticated_user`:

| LV | Purpose | Layout | Tree? | Extra toolbar? |
|---|---|---|---|---|
| `LocalizationLive.Index` | `/localization` — grid of translatable texts | `Layouts.app` | Yes — languages panel | `top_bar_extra_right` → `LocalizationToolbar.vue` (report link + export CSV/XLSX + translate-all) |
| `LocalizationLive.Edit` | `/localization/:id` — single text editor | `Layouts.app`, `has_tree={false}` | No | No |
| `LocalizationLive.Report` | `/localization/report` — analytics | `Layouts.app`, `has_tree={false}` | No | No |

Tree panel (for Index only): the left sidebar already renders **`LocalizationSidebar.vue`** from `TreePanel.vue`'s `treeComponents` map when `activeTool === "localization"`. Props today:

```elixir
%{
  sourceLanguage: serialize_language(source),
  targetLanguages: Enum.map(targets, &serialize_language/1),
  selectedLocale: locale_code,
  canEdit: bool,
  sourceLanguageOptions: [{label, value}, ...],
  addLanguageOptions: [{label, value}, ...]
}
```

Events `LocalizationSidebar.vue` pushes: `change_locale`, `change_source_language`, `add_target_language`, `remove_language`, `sync_texts`.

Extra toolbar (`top_bar_extra_right` in Index):

```elixir
<.vue v-component="modules/localization/LocalizationToolbar"
  report-url={...}
  export-csv-url={...}
  export-xlsx-url={...}
  has-provider={...} />
```

Events it pushes: `translate_batch`.

Other events in Index: `change_filter`, `search`, `change_page`, `translate_single`.

Zero collaboration/presence.

## Constraint from user

> Los toolbars tienen que mantenerse dentro de layout, no del contenido principal. De la misma manera que el sidebar izquierdo.

Both the left sidebar (languages) AND the right toolbar extra (`LocalizationToolbar`) must live in **sticky chrome**, not in main content.

## Design decision: per-tool sidebar LV + toolbar LV via slot

Two separate sticky LVs per tool (when needed):

1. **Per-tool SIDEBAR LV**: the left tree panel. Lives where our current `SidebarLive` lives — as a direct sticky child of `ProjectShell`.
2. **Per-tool TOOLBAR LV**: top-right extras (e.g. `LocalizationToolbar`). Rendered via a **slot in `ProjectShell`** that each page LV fills with `live_render(SomeToolbarLive, sticky: true, ...)`.

Why two LVs instead of one:
- Clearer naming: `SheetsSidebarLive` is literally the sidebar; `LocalizationToolbarLive` is literally the toolbar.
- Not every tool needs both (sheets has no extras → just a sidebar LV). The slot is optional.
- Each LV owns a single well-scoped concern.

**Validated by spike (2026-04-15)**: `live_render(sticky: true)` inside a `ProjectShell` slot survives navigation across page LVs in the same `live_session`. Same sticky semantics as when the live_render is called directly from the component.

Resulting architecture:

```
ProjectShell (function component)
 ├─ live_render ToolbarsLive           (sticky, SHARED: Left + Right toolbars, presence)
 ├─ live_render <sidebar_module>       (sticky, per-tool sidebar, via attr)
 ├─ slot :top_bar_extras_right         (per-tool toolbar; page LV fills with live_render of a sticky LV)
 └─ <main>{render_slot(:inner_block)}</main>
```

**Renames** (Step 1, already applied):
- `StoryarnWeb.SidebarLive` → `StoryarnWeb.SheetsSidebarLive`.

**New LVs for localization**:
- `StoryarnWeb.LocalizationSidebarLive` — sticky, left sidebar. Renders `TreePanel.vue` with `activeTool="localization"` + `treeProps` built from language state. Handlers for language mutations (`change_locale`, `change_source_language`, `add_target_language`, `remove_language`, `sync_texts`). Broadcasts `{:active_locale, locale}` on shell_topic.
- `StoryarnWeb.LocalizationToolbarLive` — sticky, top-right. Renders `LocalizationToolbar.vue`. Handlers for `translate_batch`. Receives report_url / export_csv_url / export_xlsx_url / has_provider via session.

Each renders its Vue component with `phx-update="ignore"` + dynamic id keyed on reactive state (language set for sidebar, selected_locale for toolbar export urls) to dodge the LiveVue race — same pattern already used for `RightToolbar` in `ToolbarsLive`.

## New ProjectShell contract

```elixir
# Existing attrs (no change)
attr :socket, :any, required: true
attr :project, :map, required: true
attr :workspace, :map, required: true
attr :current_scope, :map, required: true
attr :current_user, :map, required: true
attr :urls, :map, required: true
attr :active_tool, :atom, default: :sheets
attr :can_edit, :boolean, default: false
attr :is_super_admin, :boolean, default: false
attr :dashboard_url, :string, default: nil
attr :sheet_id, :any, default: nil

# NEW — per-tool sidebar module
attr :sidebar_module, :atom, required: true
attr :sidebar_session, :map, default: %{}

# NEW — slot for tool-specific top-right toolbar content
slot :top_bar_extras_right
slot :inner_block, required: true
```

Each page LV fills the slot when it has tool-specific toolbar content:

```heex
<!-- LocalizationLive.Index — has both sidebar and toolbar -->
<ProjectShell.project_shell
  sidebar_module={StoryarnWeb.LocalizationSidebarLive}
  sidebar_session={%{...}}
  active_tool={:localization}
  ...
>
  <:top_bar_extras_right>
    {live_render(@socket, StoryarnWeb.LocalizationToolbarLive,
      id: "localization-toolbar-#{@project.id}",
      sticky: true,
      session: %{
        "project_id" => @project.id,
        "workspace_slug" => @workspace.slug,
        "project_slug" => @project.slug,
        "selected_locale" => @selected_locale,
        "has_provider" => @has_provider,
        "can_edit" => @can_edit,
        "current_scope" => @current_scope
      }
    )}
  </:top_bar_extras_right>

  <!-- main content -->
</ProjectShell.project_shell>
```

```heex
<!-- LocalizationLive.Edit — sidebar but no toolbar -->
<ProjectShell.project_shell
  sidebar_module={StoryarnWeb.LocalizationSidebarLive}
  sidebar_session={%{...}}
  active_tool={:localization}
  ...
>
  <!-- main content, no :top_bar_extras_right slot filled -->
</ProjectShell.project_shell>
```

```heex
<!-- SheetLive.Show — sidebar only, no toolbar extras -->
<ProjectShell.project_shell
  sidebar_module={StoryarnWeb.SheetsSidebarLive}
  sidebar_session={%{...}}
  active_tool={:sheets}
  ...
>
  <!-- main content -->
</ProjectShell.project_shell>
```

## Files — new, changed, deleted

### New

1. `lib/storyarn_web/live/localization_sidebar_live.ex` — sticky left sidebar for localization.
   - `mount/3`: receives `project_id`, `workspace_slug`, `project_slug`, `current_scope`, `can_edit`, `selected_locale` via session. Loads `source_language`, `target_languages`. Subscribes to shell_topic + `Collaboration.subscribe_changes({:project, id})`. Returns `{:ok, socket, layout: false}`.
   - `render/1`: one fixed div with `TreePanel.vue` (activeTool=localization) + treeProps built from language state. `phx-update="ignore"` + dynamic id keyed on `languages_key` (sorted target locale codes).
   - Handlers: `tree_panel_init/toggle/pin`, `change_locale`, `change_source_language`, `add_target_language`, `remove_language`, `sync_texts`.
   - `handle_info({:toolbar_event, "tree_panel_" <> _, ...})` — same pattern as SheetsSidebarLive.
   - `handle_info({:remote_change, :language_changed | :sheet_updated, ...})` — reload languages.
   - Broadcasts `{:active_locale, locale}` on shell_topic when user picks a different locale.

2. `lib/storyarn_web/live/localization_toolbar_live.ex` — sticky top-right toolbar for localization Index.
   - `mount/3`: receives `project_id`, `workspace_slug`, `project_slug`, `selected_locale`, `has_provider`, `can_edit`, `current_scope` via session. Returns `{:ok, socket, layout: false}`.
   - `render/1`: one fixed div with `LocalizationToolbar.vue`. `phx-update="ignore"` + id keyed on `selected_locale` (export URLs depend on it).
   - Handler: `translate_batch`.
   - Subscribes to shell_topic so it can receive `{:active_locale, locale}` from the sidebar and update its export URLs.

3. `docs/plans/localization_migration.md` — this doc.

### Changed

4. `lib/storyarn_web/components/project_shell.ex`:
   - Add attrs `sidebar_module` (atom, required) + `sidebar_session` (map, default `%{}`).
   - Replace the hardcoded `live_render(SheetsSidebarLive, ...)` with `live_render(@sidebar_module, id: "sidebar-#{@project.id}", sticky: true, session: @sidebar_session)`.
   - Add slot `:top_bar_extras_right`. Rendered inside a fixed positioned div.
   - [Already done in Step 1 + spike, left to formalize as real wiring.]

5. `lib/storyarn_web/live/sheet_live/show.ex` and `lib/storyarn_web/live/sheet_live/index.ex`:
   - Update `<ProjectShell.project_shell ...>` to pass `sidebar_module={StoryarnWeb.SheetsSidebarLive}` and build `sidebar_session` map (same keys as today's SheetsSidebarLive session, hoisted explicitly).
   - No toolbar extras; don't fill the slot.

6. `lib/storyarn_web/router.ex`:
   - Move localization routes from `:require_authenticated_user` into `:project_scope`.

7. `lib/storyarn_web/live/localization_live/index.ex`:
   - Remove `Layouts.app` wrapping; replace with `<ProjectShell.project_shell sidebar_module={LocalizationSidebarLive} ...>` with `:top_bar_extras_right` slot rendering `LocalizationToolbarLive`.
   - Remove the `:top_bar_extra_right` slot and the `LocalizationToolbar` Vue invocation (moved to toolbar LV).
   - Remove `sidebar_props/1`, `serialize_language/1` from Index (moved to sidebar LV).
   - Remove `tree_panel_*` handler (sidebar handles it).
   - Remove handlers: `change_locale`, `change_source_language`, `add_target_language`, `remove_language`, `sync_texts` (move to sidebar LV), `translate_batch` (moves to toolbar LV).
   - Keep page-specific handlers: `change_filter`, `search`, `change_page`, `translate_single`.
   - `mount/3` simplified: `project`/`workspace`/`can_edit` come from `ProjectScope` hook; only load texts/pagination/filter.
   - Subscribe to shell_topic to receive `{:active_locale, locale}` from sidebar. When sidebar's `change_locale` fires, it broadcasts new locale → Index reloads texts.

8. `lib/storyarn_web/live/localization_live/edit.ex`:
   - Wrap in ProjectShell with `sidebar_module={LocalizationSidebarLive}`. Edit doesn't have a left tree today (`has_tree={false}`); with the new pattern it does get the languages panel for context. Accepted — useful for the user.
   - No toolbar extras slot filled.
   - Restore `handle_params/3` where needed. Remove `Layouts.app`.
   - Page events stay: `save_translation`, `translate_with_deepl`.

9. `lib/storyarn_web/live/localization_live/report.ex`:
   - Wrap in ProjectShell with `sidebar_module={LocalizationSidebarLive}`.
   - Remove the local `change_locale` handler; instead sidebar broadcasts `{:active_locale, locale}` → Report receives and re-runs analytics.
   - No toolbar extras slot filled.

10. `lib/storyarn_web/live/localization_live/helpers/localization_helpers.ex`:
    - `reload_languages/1` — currently assumes socket has Index's full state. Refactor: split into a sidebar-specific `reload_languages` (source/target/selected_locale) and a page-specific text reloader.

### Deleted

11. Nothing deleted in this migration. `SidebarLive` was renamed to `SheetsSidebarLive` in Step 1.

## Communication patterns

- **Shell topic** (`project:#{id}:shell`): existing. Used for:
  - `{:active_sheet, id}` (sheets) → chrome updates `selectedSheetId`.
  - NEW: `{:active_locale, locale}` (localization) → Index/Report update reloaded data.
  - NEW: `{:active_text, id}` (localization Edit) → chrome highlights current text? Not sure if sidebar shows text-level selection. Skip for now.
  - `{:toolbar_event, "tree_panel_" <> _, ...}` (ToolbarsLive → chrome).
- **Collaboration** (`project:#{id}` via `Collaboration.subscribe_changes`): existing. Localization doesn't broadcast today, but when we add `add_target_language`/`remove_language`/`sync_texts` handlers in chrome, they can broadcast `{:remote_change, :language_changed, ...}` so other clients' chromes reload.

## Order of steps (verifiable per step)

Each step leaves the app compiling and navigable.

### Step 1 ✅ — Rename `SidebarLive` → `SheetsSidebarLive`
- Mechanical rename. `shell_topic/1` stays callable on the renamed module.

### Step 2 — Generalize `ProjectShell`
- Add attrs `sidebar_module` + `sidebar_session`; replace hardcoded `live_render(SheetsSidebarLive, ...)` with `live_render(@sidebar_module, ...)`.
- Add slot `:top_bar_extras_right` inside a fixed-positioned wrapper.
- Update `SheetLive.Show` and `SheetLive.Index` to pass `sidebar_module={SheetsSidebarLive}` + explicit `sidebar_session` map. No slot content.
- Verify: `/sheets` and `/sheets/:id` still work end-to-end.

### Step 3 — Create `LocalizationSidebarLive` scaffold
- File with mount that loads languages + subscribes to shell_topic + `Collaboration.subscribe_changes`.
- Render: one fixed div with `TreePanel.vue` for localization. `phx-update="ignore"` + dynamic id keyed on language set.
- Handlers: `tree_panel_*`. Stubs for localization events (will be filled in step 5).
- Verify: compiles. Not wired to any route yet.

### Step 4 — Create `LocalizationToolbarLive` scaffold
- File with mount that receives locale + provider flag.
- Render: one fixed div with `LocalizationToolbar.vue`. `phx-update="ignore"` + id keyed on `selected_locale`.
- Subscribes to shell_topic to react to `{:active_locale, locale}`.
- Stub handler for `translate_batch`.
- Verify: compiles.

### Step 5 — Move localization routes to `:project_scope` + wire page LVs
- Router: move 3 routes into `:project_scope`.
- `LocalizationLive.Index`:
  - Swap `<Layouts.app>` → `<ProjectShell.project_shell sidebar_module={LocalizationSidebarLive}>` with `:top_bar_extras_right` slot rendering `LocalizationToolbarLive`.
  - Mount: drop project/workspace/can_edit load (hook does it).
  - Temporarily keep event handlers (move in step 6).
- `LocalizationLive.Edit` and `LocalizationLive.Report`: same swap, no toolbar slot filled.
- Verify: 3 routes load with chrome (shared ToolbarsLive + per-tool SidebarLive + optional ToolbarLive).

### Step 6 — Move localization events to the chrome LVs
- Move to `LocalizationSidebarLive`: `change_locale`, `change_source_language`, `add_target_language`, `remove_language`, `sync_texts`.
- Move to `LocalizationToolbarLive`: `translate_batch`.
- On successful mutation, sidebar broadcasts `{:active_locale, locale}` on shell_topic. Index/Report/ToolbarLive subscribe and react (Index reloads texts, Report re-runs analytics, ToolbarLive updates its export URLs).
- Remove the moved handlers from Index. Index keeps `change_filter`, `search`, `change_page`, `translate_single` (page-specific).
- Verify: sidebar interactions work (change locale, add target, etc.); translate_batch works; Index grid refreshes on locale change.

### Step 7 — Cleanup & test
- `mix compile`, `mix format`, smoke test all 3 routes + chrome interactions.
- Migrate the 5 localization test files if their mount assumptions broke.
- Remove dead code: `sidebar_props/1`, `serialize_language/1` from Index; any leftover `:top_bar_extra_right` invocations.

## Risks / open questions

1. **`LocalizationToolbar` props stability** (report_url, export urls, has_provider): these depend on project + selected_locale. Selected_locale is chrome state. If the toolbar lives in chrome and its props include `selected_locale`, we're fine — chrome's own state.

2. **`has_provider`** is a DB query (`has_active_provider?/1`). Runs once at mount. Should be part of chrome state. Not reactive for now (if user enables provider mid-session, need refresh — acceptable, existing behavior).

3. **Edit view and chrome content**: does localization chrome make sense on Edit (single-text view)? Today Edit has `has_tree={false}`. Decision: yes, show chrome sidebar on Edit too — user can see context (source/target languages) while editing a text. If UX is wrong, revert later (change one attr, no architectural effect).

4. **Dynamic id for chrome's Vue wrappers**: `LocalizationSidebar` reactive props = language set changes when user adds/removes. Keep `id="chrome-left-panel-#{language_signature}"` + `phx-update="ignore"`. `LocalizationToolbar` props almost static (urls + has_provider); plain `phx-update="ignore"` with stable id should suffice, but be ready to add dynamic id if we notice race.

5. **Report's `change_locale`**: chrome broadcasts → Report's `handle_info({:active_locale, locale})` rebuilds analytics. The Report has heavier queries (language_progress, speaker_stats, vo_progress) — be aware of cost; same as today, just triggered differently.

6. **Translate-all broadcast**: `translate_batch` can take long (DeepL). Today it's synchronous in the event handler. Keep synchronous in chrome for now; if blocking UI, move to `start_async`. Not a migration concern.

7. **Tests**: route path in tests doesn't change (same URLs). Mount expectations might break because assigns structure differs (no more `sidebar_props` in Index's assigns, etc.). Update test assertions as needed.

8. **Layouts.app other callers**: Edit and Report currently use `Layouts.app` with `has_tree={false}`. After migration they use ProjectShell with chrome. If any other LVs share this "no-tree" variant, nothing changes for them; they keep Layouts.app until their own migration.

## Success criteria

- `/localization`, `/localization/:id`, `/localization/report` all render with: shared chrome (LeftToolbar + RightToolbar) + localization chrome (languages panel + LocalizationToolbar) + page content.
- Navigating between the 3 routes keeps chrome alive (sticky). Verify by watching the LocalizationSidebar state (selected locale) survive navigation.
- All interactive flows work: change locale, add/remove target language, sync texts, translate-all, translate-single, edit a text.
- No LiveVue race crash on mount or on chrome re-renders.
- No duplicate toolbars or sidebars.
- `mix compile` clean; `mix format` clean; credo issues not increased over baseline (130 post-Styler).

## Out of scope for this migration

- Flows migration (next, and more complex — FlowHeader has heavy page-specific state that challenges sticky-chrome assumptions).
- Collaboration/presence for localization (not present today; don't add now).
- `translate_batch` async pipeline (works synchronously today).
- Any redesign of LocalizationSidebar or LocalizationToolbar Vue components.

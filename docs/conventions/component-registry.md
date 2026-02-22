# Component Registry

## Auto-imported Components

These are available in ALL HEEx templates without explicit import (via `StoryarnWeb`):

### CoreComponents (`core_components.ex`)

| Component          | Purpose             | Key Attributes                                                                                                                        |
|--------------------|---------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| `<.button>`        | Button (nav-aware)  | `variant` (primary/error), `href`/`navigate`/`patch`                                                                                  |
| `<.input>`         | Form input wrapper  | `field`, `type` (text/textarea/select/checkbox + 13 more HTML5 types), `label`, `errors`                                              |
| `<.icon>`          | Lucide icon         | `name` (string, required), `class`                                                                                                    |
| `<.header>`        | Page header         | `inner_block`, `:subtitle` slot, `:actions` slot                                                                                      |
| `<.modal>`         | Dialog modal        | `id`, `show`, `on_cancel`                                                                                                             |
| `<.confirm_modal>` | Confirmation dialog | `id`, `title`, `message`, `confirm_text`, `cancel_text`, `confirm_variant` (primary/error/warning), `on_confirm`, `on_cancel`, `icon` |
| `<.table>`         | Data table          | `rows`, `row_id`, `row_click`, `:col` slot, `:action` slot                                                                            |
| `<.list>`          | Key-value list      | `:item` slot (with title)                                                                                                             |
| `<.flash>`         | Flash notification  | `kind`, `flash`                                                                                                                       |
| `<.back>`          | Back link           | `navigate`                                                                                                                            |
| `<.block_label>`   | Block field label   | `label`, `is_constant`                                                                                                                |

**Helper functions:**
- `show(js, selector)` / `hide(js, selector)` — JS visibility commands
- `show_modal(js \\ %JS{}, id)` / `hide_modal(js \\ %JS{}, id)` — Modal open/close
- `translate_error(error_tuple)` / `translate_errors(errors, field)` — Ecto error to string

### UIComponents (`ui_components.ex`)

| Component | Purpose | Key Attributes |
|-----------|---------|---------------|
| `<.role_badge>` | Role indicator | `role` (owner/admin/editor/member/viewer) |
| `<.oauth_buttons>` | OAuth login buttons | `action` (login/link), `class` |
| `<.kbd>` | Keyboard shortcut | `inner_block` (content slot), `size` (xs/sm/md) |
| `<.empty_state>` | Empty content state | `icon`, `title`, `inner_block` (description), `:action` slot |
| `<.search_input>` | Search field | `size` (xs/sm/md/lg), global: `name`, `value`, `placeholder`, `phx-change` |
| `<.avatar_group>` | Avatar cluster | `size` (xs/sm/md/lg), `max`, `total`, `:avatar` slot (src/alt/fallback) |
| `<.theme_toggle>` | Theme switcher | — |

---

## Domain-Specific Components (require import)

### MemberComponents

```elixir
import StoryarnWeb.Components.MemberComponents
```

| Component | Purpose |
|-----------|---------|
| `<.user_avatar>` | Avatar with initials fallback. Attrs: `user`, `email`, `size` (sm/md/lg) |
| `<.member_row>` | Member list item. Attrs: `member`, `current_user_id`, `can_manage`, `on_remove`, `on_role_change` |
| `<.invitation_row>` | Invitation list item. Attrs: `invitation`, `can_revoke`, `on_revoke` |

### BlockComponents (facade)

```elixir
import StoryarnWeb.Components.BlockComponents
```

| Component | Purpose |
|-----------|---------|
| `<.block_component>` | Renders any block by type. Attrs: `block`, `can_edit`, `editing_block_id`, `target`, `table_data`, `reference_options` |
| `<.block_menu>` | Block type selector dropdown |
| `<.config_panel>` | Block configuration sidebar |

Submodules: `TextBlocks`, `SelectBlocks`, `LayoutBlocks`, `BooleanBlocks`, `ReferenceBlocks`, `TableBlocks`

### CollaborationComponents

```elixir
import StoryarnWeb.Components.CollaborationComponents
```

| Component | Purpose |
|-----------|---------|
| `<.online_users>` | Online user avatars. Attrs: `users`, `current_user_id` |
| `<.collab_toast>` | Collaboration event toast. Attrs: `action`, `user_email`, `user_color`, `details` |
| `<.node_lock_indicator>` | Lock indicator on nodes. Attrs: `lock` (map) |

### SaveIndicator

```elixir
import StoryarnWeb.Components.SaveIndicator
```

| Component | Purpose |
|-----------|---------|
| `<.save_indicator>` | Save status display. Attrs: `status` (:idle/:saving/:saved), `variant` (:inline/:floating) |

### ConditionBuilder

```elixir
import StoryarnWeb.Components.ConditionBuilder
```

| Component | Purpose |
|-----------|---------|
| `<.condition_builder>` | Variable condition editor. Attrs: `id`, `condition`, `variables`, `can_edit`, `switch_mode`, `event_name`, `context` |

### InstructionBuilder

```elixir
import StoryarnWeb.Components.InstructionBuilder
```

| Component | Purpose |
|-----------|---------|
| `<.instruction_builder>` | Variable assignment editor. Attrs: `id`, `assignments`, `variables`, `can_edit`, `event_name`, `context` |

### ColorPicker

```elixir
import StoryarnWeb.Components.ColorPicker
```

| Component | Purpose |
|-----------|---------|
| `<.color_picker>` | Color selection. Attrs: `id` (required), `color` (default "#8b5cf6"), `event` (required), `field` (default "color"), `disabled` |

### AudioPicker (LiveComponent)

```elixir
# LiveComponent — use live_component, NOT import
<.live_component module={StoryarnWeb.Components.AudioPicker} id="audio" ... />
```

| Component | Purpose |
|-----------|---------|
| `AudioPicker` | Audio asset selector for dialogue nodes (LiveComponent, not function component) |

### TreeComponents (`tree.ex`)

```elixir
import StoryarnWeb.Components.TreeComponents
```

Components: `<.tree_node>`, `<.tree_leaf>`, `<.tree_section>`, `<.tree_link>`

### Sidebar Trees (per-domain)

```elixir
import StoryarnWeb.Components.Sidebar.SheetTree
import StoryarnWeb.Components.Sidebar.FlowTree
import StoryarnWeb.Components.Sidebar.ScreenplayTree
import StoryarnWeb.Components.Sidebar.MapTree
```

### Other Shared Components

| Module | Import | Components |
|--------|--------|-----------|
| `ExpressionEditor` | `import StoryarnWeb.Components.ExpressionEditor` | `<.expression_editor>` — tabbed Builder/Code editor |
| `SheetComponents` | `import StoryarnWeb.Components.SheetComponents` | `<.sheet_avatar>` |
| `Sidebar` | `import StoryarnWeb.Components.Sidebar` | `<.sidebar>` — workspace navigation |
| `ProjectSidebar` | `import StoryarnWeb.Components.ProjectSidebar` | `<.project_sidebar>` — project navigation |

---

## Layouts (5 independent, NOT nested)

```elixir
<Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
  # Main app shell with workspace sidebar
</Layouts.app>

<Layouts.project flash={@flash} current_scope={@current_scope} project={@project}
  workspace={@workspace} sheets_tree={@sheets_tree} active_tool={:sheets}>
  # Project shell with entity tree sidebar
</Layouts.project>

<Layouts.auth flash={@flash}>
  # Centered auth pages (login/register)
</Layouts.auth>

<Layouts.public flash={@flash}>
  # Public pages (landing, marketing)
</Layouts.public>

<Layouts.settings flash={@flash} current_scope={@current_scope} current_path={@current_path}
  workspaces={@workspaces}>
  # Settings shell with section navigation. Slots: :title (required), :subtitle
</Layouts.settings>
```

**Layouts.project** additional attrs: `flows_tree`, `screenplays_tree`, `maps_tree`, `current_path`, `selected_sheet_id`, `selected_flow_id`, `selected_screenplay_id`, `selected_map_id`, `can_edit`

---

## Changeset Helpers (Maps domain)

**File:** `lib/storyarn/maps/changeset_helpers.ex`

| Function | Purpose |
|----------|---------|
| `validate_target_pair/2` | Ensures target_type and target_id are both set or both nil |
| `validate_color/2` | Validates hex color format (#RGB, #RRGGBB, #RRGGBBAA) |

These are Maps-specific but could be promoted to `Storyarn.Shared` if needed elsewhere.

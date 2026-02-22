# Component Registry

## Auto-imported Components

These are available in ALL HEEx templates without explicit import (via `StoryarnWeb`):

### CoreComponents (`core_components.ex`)

| Component | Purpose | Key Attributes |
|-----------|---------|---------------|
| `<.button>` | Button (nav-aware) | `variant` (primary/ghost/error), `href`/`navigate`/`patch` |
| `<.input>` | Form input wrapper | `field`, `type` (text/textarea/select/checkbox/hidden), `label`, `errors` |
| `<.icon>` | Lucide icon | `name` (string), `class` |
| `<.header>` | Page header | `inner_block`, `:subtitle` slot, `:actions` slot |
| `<.modal>` | Dialog modal | `id`, `show`, `on_cancel` |
| `<.confirm_modal>` | Confirmation dialog | `id`, `title`, `message`, `confirm_text`, `on_confirm` |
| `<.table>` | Data table | `rows`, `row_id`, `row_click`, `:col` slot, `:action` slot |
| `<.list>` | Key-value list | `:item` slot (with title) |
| `<.flash>` | Flash notification | `kind`, `flash` |
| `<.back>` | Back link | `navigate` |
| `<.block_label>` | Block field label | `label`, `is_constant` |

**Helper functions:**
- `show(js, selector)` / `hide(js, selector)` — JS visibility commands
- `show_modal(id)` / `hide_modal(id)` — Modal open/close
- `translate_error(error_tuple)` — Ecto error to string

### UIComponents (`ui_components.ex`)

| Component | Purpose | Key Attributes |
|-----------|---------|---------------|
| `<.role_badge>` | Role indicator | `role` (owner/admin/editor/member/viewer) |
| `<.oauth_buttons>` | OAuth login buttons | — |
| `<.kbd>` | Keyboard shortcut | `key` |
| `<.empty_state>` | Empty content state | `icon`, `title`, `description` |
| `<.search_input>` | Search field | `value`, `placeholder` |
| `<.avatar_group>` | Avatar cluster | `users` |
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
| `<.invitation_row>` | Invitation list item. Attrs: `invitation`, `can_manage`, `on_remove`, `on_resend` |

### BlockComponents (facade)

```elixir
import StoryarnWeb.Components.BlockComponents
```

| Component | Purpose |
|-----------|---------|
| `<.block_component>` | Renders any block by type. Attrs: `block`, `can_edit`, `editing_block_id`, `target`, `table_data` |
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
| `<.collab_toast>` | Collaboration event toast. Attrs: `action`, `user_email`, `user_color` |

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
| `<.condition_builder>` | Variable condition editor. Attrs: `id`, `condition`, `variables`, `can_edit`, `switch_mode`, `event_name` |

### InstructionBuilder

```elixir
import StoryarnWeb.Components.InstructionBuilder
```

| Component | Purpose |
|-----------|---------|
| `<.instruction_builder>` | Variable assignment editor. Attrs: `id`, `assignments`, `variables`, `can_edit`, `event_name` |

### ColorPicker

```elixir
import StoryarnWeb.Components.ColorPicker
```

| Component | Purpose |
|-----------|---------|
| `<.color_picker>` | Color selection. Used for hub colors, zone styling |

### AudioPicker

```elixir
import StoryarnWeb.Components.AudioPicker
```

| Component | Purpose |
|-----------|---------|
| `<.audio_picker>` | Audio asset selector for dialogue nodes |

### Tree Components

```elixir
import StoryarnWeb.Components.Tree
```

Submodules: `SheetTree`, `FlowTree`, `ScreenplayTree`, `MapTree`, `TreeHelpers`

---

## Layouts (4 independent, NOT nested)

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

<Layouts.settings flash={@flash} current_scope={@current_scope} active_section={:general}>
  # Settings shell with section navigation
</Layouts.settings>
```

**Layouts.project** additional attrs: `flows_tree`, `screenplays_tree`, `maps_tree`, `selected_sheet_id`, `selected_flow_id`, `can_edit`

---

## Changeset Helpers (Maps domain)

**File:** `lib/storyarn/maps/changeset_helpers.ex`

| Function | Purpose |
|----------|---------|
| `validate_target_pair/2` | Ensures target_type and target_id are both set or both nil |
| `validate_color/2` | Validates hex color format (#RGB, #RRGGBB, #RRGGBBAA) |

These are Maps-specific but could be promoted to `Storyarn.Shared` if needed elsewhere.

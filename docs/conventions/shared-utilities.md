# Shared Utilities Registry

**IMPORTANT: Before writing ANY helper function, search this registry first. Duplicating these utilities is a bug.**

## `Storyarn.Shared.NameNormalizer`

**File:** `lib/storyarn/shared/name_normalizer.ex`

Centralizes ALL name-to-identifier conversions. Handles Unicode transliteration (accents → ASCII), lowercasing, and character filtering.

| Function                 | Input → Output                                                                         | Used For                                    |
|--------------------------|----------------------------------------------------------------------------------------|---------------------------------------------|
| `slugify/1`              | `"My Workspace!"` → `"my-workspace"`                                                   | URL slugs (separator: `-`)                  |
| `variablify/1`           | `"Health Points"` → `"health_points"`                                                  | Variable names (separator: `_`)             |
| `shortcutify/1`          | `"MC.Jaime"` → `"mc.jaime"`                                                            | Sheet/flow/map shortcuts (separator: `.`)   |
| `generate_unique_slug/4` | `(Schema, scope, name, suffix \\ nil)` → `"my-workspace"` or `"my-workspace-a1b2c3d4"` | Unique slugs with collision suffix          |
| `maybe_regenerate/4`     | `(current, new_name, referenced?, normalize_fn)` → `String.t()`                        | Smart rename: skips if entity has backlinks |

**Pipeline:** NFD decomposition → strip combining marks → lowercase → filter allowed chars → collapse separators → trim

```elixir
# URL slug for project/workspace
NameNormalizer.generate_unique_slug(Project, [workspace_id: ws_id], "My Project")

# Variable name from block label
NameNormalizer.variablify("Health Points")  # => "health_points"

# Entity shortcut
NameNormalizer.shortcutify("MC.Jaime")  # => "mc.jaime"
```

---

## `Storyarn.Shared.ShortcutHelpers`

**File:** `lib/storyarn/shared/shortcut_helpers.ex`

Shortcut lifecycle management shared by ALL CRUD modules (FlowCrud, SheetCrud, SceneCrud, ScreenplayCrud).

| Function                              | Purpose                                                                |
|---------------------------------------|------------------------------------------------------------------------|
| `maybe_generate_shortcut/4`           | Auto-generates shortcut from name if not present in attrs              |
| `name_changing?/2`                    | Returns true if attrs contain a new, non-empty name                    |
| `missing_shortcut?/1`                 | Returns true if entity shortcut is nil/empty                           |
| `generate_shortcut_from_name/3`       | Generates shortcut from name using generator function                  |
| `maybe_assign_position/4`             | Auto-assigns next position if not in attrs                             |
| `maybe_generate_shortcut_on_update/4` | Handles shortcut regeneration on update (with optional backlink check) |

```elixir
# On entity create - auto-generate shortcut
attrs = ShortcutHelpers.maybe_generate_shortcut(attrs, project_id, nil, &generate_shortcut/3)

# On entity update - regenerate shortcut with backlink protection
attrs = ShortcutHelpers.maybe_generate_shortcut_on_update(entity, attrs, &generate_shortcut/3,
  check_backlinks_fn: &has_backlinks?/1
)
```

---

## `Storyarn.Shared.TreeOperations`

**File:** `lib/storyarn/shared/tree_operations.ex`

Generic tree manipulation for ANY entity with `parent_id` + `position` fields. Used by sheets, flows, scenes, screenplays.

| Function                     | Purpose                                               |
|------------------------------|-------------------------------------------------------|
| `reorder/5`                  | Reorder siblings within a parent (transactional)      |
| `move_to_position/5`         | Move entity to new parent at position                 |
| `next_position/3`            | Get next available position for new child             |
| `list_by_parent/3`           | List children ordered by position                     |
| `update_position_only/3`     | Update just position field                            |
| `reorder_source_container/4` | Compact positions after removal                       |
| `add_parent_filter/2`        | Add parent_id filter to query (handles nil for roots) |

```elixir
TreeOperations.reorder(Sheet, project_id, parent_id, ordered_ids, &list_fn/2)
TreeOperations.move_to_position(Flow, flow, new_parent_id, 2, &list_fn/2)
TreeOperations.next_position(Map, project_id, parent_id)
```

---

## `Storyarn.Shared.SoftDelete`

**File:** `lib/storyarn/shared/soft_delete.ex`

Recursive soft-delete for hierarchical entities. Sets `deleted_at` timestamp on entity and all descendants.

| Function                   | Purpose                                 |
|----------------------------|-----------------------------------------|
| `soft_delete_children/3-4` | Recursively soft-delete all children    |
| `list_deleted/2`           | List soft-deleted entities for trash UI |

Options: `:pre_delete` callback for cleanup before each deletion.

```elixir
SoftDelete.soft_delete_children(Flow, project_id, flow_id,
  pre_delete: &Flows.clean_flow_references/1
)
deleted = SoftDelete.list_deleted(Flow, project_id)
```

---

## `Storyarn.Shared.Validations`

**File:** `lib/storyarn/shared/validations.ex`

Centralized Ecto validators. Do NOT write custom regex for these.

| Function                  | Purpose                                                             | Pattern                                      |
|---------------------------|---------------------------------------------------------------------|----------------------------------------------|
| `validate_shortcut/1-2`   | Shortcut format (1-50 chars), optional `opts` for custom `:message` | `^[a-z0-9][a-z0-9.\-]*[a-z0-9]$\|^[a-z0-9]$` |
| `validate_email_format/1` | Email format                                                        | `^[^@,;\s]+@[^@,;\s]+$`                      |
| `shortcut_format/0`       | Returns shortcut regex                                              | For reference                                |
| `email_format/0`          | Returns email regex                                                 | For reference                                |

```elixir
changeset
|> Validations.validate_shortcut()
|> unique_constraint(:shortcut, name: :sheets_project_id_shortcut_index)
```

---

## `Storyarn.Shared.MapUtils`

**File:** `lib/storyarn/shared/map_utils.ex`

Map transformation utilities for handling mixed atom/string key maps from forms and JSON.

| Function           | Purpose                                                                              |
|--------------------|--------------------------------------------------------------------------------------|
| `stringify_keys/1` | Convert top-level atom keys to strings (NOT recursive — nested maps keep their keys) |
| `parse_int/1`      | Safe integer parsing: `"42"` → `42`, `42` → `42`, `nil` → `nil`                      |

```elixir
MapUtils.stringify_keys(%{name: "test", nested: %{key: "val"}})
# => %{"name" => "test", "nested" => %{key: "val"}}  (inner map NOT converted)

MapUtils.parse_int("42")  # => 42
MapUtils.parse_int(nil)   # => nil
```

---

## `Storyarn.Shared.SearchHelpers`

**File:** `lib/storyarn/shared/search_helpers.ex`

SQL injection prevention for LIKE queries.

| Function                | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `sanitize_like_query/1` | Escapes `%`, `_`, `\` in user input before ILIKE |

```elixir
sanitized = SearchHelpers.sanitize_like_query(user_input)
where(query, [q], ilike(q.name, ^"%#{sanitized}%"))
```

---

## `Storyarn.Shared.TimeHelpers`

**File:** `lib/storyarn/shared/time_helpers.ex`

| Function   | Purpose                                             |
|------------|-----------------------------------------------------|
| `now/0`    | `DateTime.utc_now() \|> DateTime.truncate(:second)` |

**ALWAYS use this** instead of inline `DateTime.utc_now()` with truncation.

---

## `Storyarn.Shared.TokenGenerator`

**File:** `lib/storyarn/shared/token_generator.ex`

Cryptographic token generation for invitations and auth tokens.

| Function               | Purpose                                                  |
|------------------------|----------------------------------------------------------|
| `build_hashed_token/0` | Returns `{encoded_token, hashed_token}` for invite links |
| `decode_and_hash/1`    | Verifies user-provided token                             |

---

## `Storyarn.Shared.EncryptedBinary`

**File:** `lib/storyarn/shared/encrypted_binary.ex`

Custom Ecto type for Cloak-encrypted fields. Use in schemas:

```elixir
field :api_key_encrypted, Storyarn.Shared.EncryptedBinary
```

---

## `StoryarnWeb.FlowLive.Helpers.HtmlSanitizer`

**File:** `lib/storyarn_web/live/flow_live/helpers/html_sanitizer.ex`

HTML sanitizer with XSS protection. **ALWAYS use when rendering `raw()` content.**

| Function          | Purpose                                                |
|-------------------|--------------------------------------------------------|
| `sanitize_html/1` | Strips unsafe tags/attributes, blocks javascript: URIs |

Allowlist: `p br em strong b i u s span a ul ol li blockquote code pre sub sup del h1-h6 div`

```elixir
# ALWAYS wrap raw() with sanitizer
{raw(HtmlSanitizer.sanitize_html(user_content))}

# NEVER do this
{raw(user_content)}
```

---

## `StoryarnWeb.Helpers.Authorize`

**File:** `lib/storyarn_web/helpers/authorize.ex`

Authorization for LiveView event handlers. Prevents bypassing UI-only permission checks.

```elixir
use StoryarnWeb.Helpers.Authorize

# In LiveView handle_event
def handle_event("delete", params, socket) do
  with_authorization(socket, :edit_content, fn socket ->
    do_delete(socket, params)
  end)
end

# In LiveComponent handle_event (checks @can_edit assign)
def handle_event("save", params, socket) do
  with_edit_authorization(socket, fn socket ->
    do_save(socket, params)
  end)
end
```

Actions: `:edit_content`, `:manage_project`, `:manage_members`, `:manage_workspace`, `:manage_workspace_members`

---

## `StoryarnWeb.Helpers.SaveStatusTimer`

**File:** `lib/storyarn_web/helpers/save_status_timer.ex`

Schedules a delayed reset of the save status indicator for LiveViews.

| Function             | Purpose                                                                                    |
|----------------------|--------------------------------------------------------------------------------------------|
| `schedule_reset/1-2` | Sends `:reset_save_status` after `timeout_ms` (default 4000ms). Returns socket for piping. |

```elixir
socket
|> assign(:save_status, :saved)
|> SaveStatusTimer.schedule_reset()
```

---

## JS Utilities

### `assets/js/utils/floating_popover.js`

Body-appended popover using `@floating-ui/dom`. Escapes overflow containers.

```javascript
import { createFloatingPopover } from "../utils/floating_popover";
const fp = createFloatingPopover(triggerEl, { placement: "bottom-start" });
fp.el.appendChild(content);
fp.open(); fp.close(); fp.destroy();
```

### `assets/js/flow_canvas/node_config.js`

Icon utilities for Lucide icons in different rendering contexts.

| Function                         | Context                | Output                  |
|----------------------------------|------------------------|-------------------------|
| `createIconHTML(Icon, { size })` | Shadow DOM / innerHTML | HTML string             |
| `createIconSvg(Icon)`            | Node headers           | SVG with stroke styling |

Regular DOM: use `createElement(Icon, { width, height })` from `lucide` directly.

# Shared Utilities Registry

> Owner: Engineering
>
> Last reviewed: 2026-08-25
>
> Source of truth: `lib/storyarn/platform/shared/`

**IMPORTANT: Before writing ANY helper function, search this registry first. Duplicating these utilities is a bug.**

## `Storyarn.Projects.NameNormalizer`

**File:** `lib/storyarn/projects/name_normalizer.ex` — **owned by the Project
boundary** since ENG-92 (its only consumers). Tools carry their own copies
(e.g. `Workspaces.Lifecycle.Rules.Slug`, per-context `ShortcutGenerator`s); do not add
foreign consumers.

Centralizes the Project boundary's name-to-identifier conversions. Handles Unicode transliteration (accents → ASCII), lowercasing, and character filtering.

| Function                   | Input → Output                                                                         | Used For                                                                            |
| -------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `slugify/1`                | `"My Workspace!"` → `"my-workspace"`                                                   | URL slugs. Allows `[a-z0-9-]`                                                       |
| `variablify/1`             | `"Health Points"` → `"health_points"`                                                  | Variable names. Allows `[a-z0-9_.]`, `nil` on blank                                 |
| `shortcutify/1`            | `"MC.Jaime"` → `"mc.jaime"`                                                            | Sheet/flow/scene shortcuts. Allows `[a-z0-9-.]` — spaces become `-`, dots preserved |
| `generate_unique_slug/3-4` | `(Schema, scope, name, suffix \\ nil)` → `"my-workspace"` or `"my-workspace-a1b2c3d4"` | Unique slugs with collision suffix                                                  |
| `maybe_regenerate/4`       | `(current, new_name, referenced?, normalize_fn)` → `String.t()`                        | Smart rename: skips if entity has backlinks                                         |

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

## Shortcut lifecycle (consumer-owned)

`Storyarn.Shared.ShortcutHelpers` and the global `Storyarn.Shortcuts` module
were deleted during the ENG-92 bounded-context migration. Each tool owns its
shortcut policy (e.g. `Storyarn.Sheets.ShortcutGenerator`,
`Storyarn.Flows.ShortcutGenerator`). Copy the pattern into the owning context
instead of recreating a shared module.

---

## Tree operations (consumer-owned)

`Storyarn.Shared.TreeOperations` was deleted during the ENG-92 migration.
Each hierarchical tool carries its own copy closed over its schema
(`Storyarn.Sheets.TreeOperations`, `Storyarn.Flows.TreeOperations`,
`Storyarn.Scenes.TreeOperations`) including the `batch_set_positions`
allowlists. Copy the pattern into the owning context.

---

## Soft delete (consumer-owned)

`Storyarn.Shared.SoftDelete` was deleted during the ENG-92 bounded-context
migration. Recursive soft-delete now lives inside each owning context (e.g.
`Storyarn.Scenes.SoftDelete` — `soft_delete_children/3`, `list_deleted/2`;
Flows uses its own `FlowTrash` cascade). Do not recreate a shared module —
copy the pattern into the owning context instead.

---

## `Storyarn.Projects.Validations`

**File:** `lib/storyarn/projects/validations.ex` — **owned by the Project
boundary** since ENG-92. Workspaces and Accounts carry their formats inline
(`Workspace.validate_slug`, `User.validate_email_format`,
`WorkspaceInvitation.validate_email_format`); do not add foreign consumers.

Centralized Ecto validators for the Project boundary. Do NOT write custom regex for these.

| Function                  | Purpose                                                             | Pattern                                      |
| ------------------------- | ------------------------------------------------------------------- | -------------------------------------------- |
| `validate_shortcut/1-2`   | Shortcut format (1-50 chars), optional `opts` for custom `:message` | `^[a-z0-9][a-z0-9.\-]*[a-z0-9]$\|^[a-z0-9]$` |
| `validate_email_format/1` | Email format                                                        | `^[^@,;\s]+@[^@,;\s]+$`                      |
| `validate_slug/1`         | Slug format on the `:slug` field (1-100 chars)                      | `^[a-z0-9]+(?:-[a-z0-9]+)*$`                 |
| `shortcut_format/0`       | Returns shortcut regex                                              | For reference                                |
| `email_format/0`          | Returns email regex                                                 | For reference                                |

```elixir
changeset
|> Validations.validate_shortcut()
|> unique_constraint(:shortcut, name: :sheets_project_id_shortcut_index)
```

---

## `Storyarn.Platform.Shared.MapUtils`

**File:** `lib/storyarn/platform/shared/map_utils.ex`

Map transformation and parsing utilities for handling mixed atom/string key maps from forms and JSON.

| Function                 | Purpose                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `stringify_keys/1`       | Convert top-level atom keys to strings (NOT recursive — nested maps keep their keys) |
| `get_flexible/2`         | Fetch by atom key, falling back to the string key                                    |
| `parse_int/1`            | Safe integer parsing: `"42"` → `42`, `42` → `42`, `nil` → `nil`                      |
| `parse_to_number/1`      | Parse any value to float for formulas: `"42"` → `42.0`, `nil` → `0.0`                |
| `ensure_integer/1`       | Integer passthrough, `0` for anything else                                           |
| `format_number_result/1` | Collapse a whole float back to an integer for display                                |

```elixir
MapUtils.stringify_keys(%{name: "test", nested: %{key: "val"}})
# => %{"name" => "test", "nested" => %{key: "val"}}  (inner map NOT converted)

MapUtils.parse_int("42")  # => 42
MapUtils.parse_int(nil)   # => nil

MapUtils.parse_to_number("42")  # => 42.0
MapUtils.parse_to_number(nil)   # => 0.0
```

---

## `Storyarn.Platform.Shared.Severity`

**File:** `lib/storyarn/platform/shared/severity.ex`

The single ordering of the health severity catalog for shared Web dashboards
(`StoryarnWeb.Live.Shared.DashboardHelpers`). Sealed boundaries carry their own
copies (`Flows.Severity`, `Projects.Severity`, …) — reimplement the copy in the
owning context, never a cross-boundary call.

| Function    | Purpose                                                       |
| ----------- | ------------------------------------------------------------- |
| `rank/1`    | Sort key: `:error`/`"error"` → 0, `:warning` → 1, `:info` → 2 |
| `catalog/0` | `[:error, :warning, :info]`, in rank order                    |

Strict by design: severity is a closed catalog, so `rank/1` raises `ArgumentError` on anything else rather than silently sorting it last.

```elixir
Enum.sort_by(findings, &Severity.rank(&1.severity))
```

---

## `Storyarn.Platform.Shared.StringUtils`

**File:** `lib/storyarn/platform/shared/string_utils.ex`

| Function          | Purpose                                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| `blank?/1`        | `nil` or `""` → true. **Does NOT trim.**                                                                         |
| `present_label/2` | `value` if it has a non-whitespace char, else `fallback`. Trims to decide presence; returns the value untouched. |

`blank?/1` replaced eight byte-equivalent private copies. **Three modules keep a different, trimming `blank?/1` and must not be folded in** — `Sheets.HealthChecker`, `Scenes.HealthChecker`, `Localization.GlossarySync`: for them a whitespace-only label counts as empty, and changing that changes which findings the health sweeps report.

---

## `Storyarn.Platform.Shared.SearchHelpers`

**File:** `lib/storyarn/platform/shared/search_helpers.ex`

SQL injection prevention for LIKE queries.

| Function                | Purpose                                          |
| ----------------------- | ------------------------------------------------ |
| `sanitize_like_query/1` | Escapes `%`, `_`, `\` in user input before ILIKE |

```elixir
sanitized = SearchHelpers.sanitize_like_query(user_input)
where(query, [q], ilike(q.name, ^"%#{sanitized}%"))
```

---

## `Storyarn.Platform.Shared.TimeHelpers`

**File:** `lib/storyarn/platform/shared/time_helpers.ex`

| Function | Purpose                                             |
| -------- | --------------------------------------------------- |
| `now/0`  | `DateTime.utc_now() \|> DateTime.truncate(:second)` |

**ALWAYS use this** instead of inline `DateTime.utc_now()` with truncation.

---

## `Storyarn.Platform.Shared.TokenGenerator`

**File:** `lib/storyarn/platform/shared/token_generator.ex`

Cryptographic token generation for invitations and auth tokens.

| Function               | Purpose                                                  |
| ---------------------- | -------------------------------------------------------- |
| `build_hashed_token/0` | Returns `{encoded_token, hashed_token}` for invite links |
| `decode_and_hash/1`    | Verifies user-provided token                             |

---

## `Storyarn.Platform.Shared.EncryptedBinary`

**File:** `lib/storyarn/platform/shared/encrypted_binary.ex`

Custom Ecto type for Cloak-encrypted fields. Use in schemas:

```elixir
field :api_key_encrypted, Storyarn.Platform.Shared.EncryptedBinary
```

---

## `Storyarn.Platform.Shared.CanonicalJSON`

**File:** `lib/storyarn/platform/shared/canonical_json.ex`

Deterministic canonical JSON encoding and SHA-256 hashing. Sorted object keys, rejects structs/duplicate-normalized-keys/improper lists. Its only consumers are in `lib/storyarn/ai/`: context payload and entity content hashing, the execution-intent input hash that makes a repeated AI request replay instead of re-spending, and output encoding for the size cap and stored result. Any new hash over structured data MUST go through this module — two encoders mean two hashes for the same input, and the spend guarantee is exactly that identical input yields an identical key.

| Function    | Purpose                                                          |
| ----------- | ---------------------------------------------------------------- |
| `encode/1`  | `{:ok, canonical_json}` or `{:error, :invalid_structured_input}` |
| `encode!/1` | Raising variant                                                  |
| `hash/1`    | `{:ok, lowercase_hex_sha256}` of the canonical encoding          |
| `hash!/1`   | Raising variant                                                  |

---

## `Storyarn.Platform.Shared.HtmlSanitizer`

**File:** `lib/storyarn/platform/shared/html_sanitizer.ex`

HTML sanitizer with XSS protection. **ALWAYS use when rendering `raw()` content.**

| Function          | Purpose                                                |
| ----------------- | ------------------------------------------------------ |
| `sanitize_html/1` | Strips unsafe tags/attributes, blocks javascript: URIs |

Allowlist: `p br em strong b i u s span a ul ol li blockquote code pre sub sup del h1-h6 div`

```elixir
# ALWAYS wrap raw() with sanitizer
{raw(HtmlSanitizer.sanitize_html(user_content))}

# NEVER do this
{raw(user_content)}
```

---

## Remaining `Storyarn.Platform.Shared.*` modules

One line each. Open the file before writing anything that overlaps.

| Module                 | File                       | What it owns                                                                                                                      |
| ---------------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `ColorUtils`           | `color_utils.ex`           | `valid_hex?/1`, `hex_to_oklch/1`, `darken_oklch/2` — hex→oklch for theme customization                                            |
| `HtmlUtils`            | `html_utils.ex`            | `strip_html/1`, `strip_and_truncate/2`, `word_count/1`, `add_heading_ids/1`, `heading_outline/1` — **not** a sanitizer            |
| `ImportHelpers`        | `import_helpers.ex`        | `detect_shortcut_conflicts/3`, `soft_delete_by_shortcut/3`, `bulk_insert/2-3`                                                     |
| `InvitationSchema`     | `invitation_schema.ex`     | `use`-macro that generates the invitation schema/changesets for Projects; the workspace arm lives in `Workspaces.WorkspaceInvitation` |
| `InvitationOperations` | `invitation_operations.ex` | Config-map-driven invitation CRUD for Projects (`create_invitation`, `accept_invitation`, `revoke_…`); the workspace arm lives in `Workspaces.Invitations` |
| `InvitationNotifier`   | `invitation_notifier.ex`   | `deliver_invitation/3-4` — email delivery for the above; Workspaces owns its workflow and copy in `Workspaces.Invitations.Delivery`, with transport isolated in `Workspaces.Invitations.Adapters.Email.Mailer` |
| `MembershipOperations` | `membership_operations.ex` | Config-map-driven membership CRUD + `authorize/2` for Projects; the workspace arm lives in `Workspaces.Memberships`               |
| `Trashable`            | `trashable.ex`             | `soft_delete/1`, `restore/1`, `inbound_refs/1`, `target_type!/1` — registry-driven soft-delete that also sweeps inbound refs      |
| `WordCount`            | `word_count.ex`            | `for_node_data/2`, `for_block/2`, `for_block_value/1`, `for_name/1` — **Project-boundary-owned** (versioning builders); tools own copies |

`EncryptedBinary` is covered above; it is a type, not a helper.

`FormulaEngine`, `FormulaRuntime`, and `HierarchicalSchema` were deleted in the
ENG-92 migration — each tool (and, for project coordination, `Storyarn.Projects`)
carries its own copy (`Storyarn.Sheets.FormulaEngine`,
`Storyarn.Flows.FormulaRuntime`, `Storyarn.Sheets.Schema`, …).

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

# Compatibility spelling for canonical :edit_content authorization
def handle_event("save", params, socket) do
  with_edit_authorization(socket, fn socket ->
    do_save(socket, params)
  end)
end
```

The compatibility helper reauthorizes through `Projects`; it does not trust a
cached `@can_edit` value from mount time.

Actions: `:edit_content`, `:use_ai`, `:manage_project`, `:manage_members`, `:manage_workspace`, `:manage_workspace_members`

---

## `StoryarnWeb.Helpers.SaveStatusTimer`

**File:** `lib/storyarn_web/helpers/save_status_timer.ex`

Schedules a delayed reset of the save status indicator for LiveViews.

| Function             | Purpose                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------ |
| `schedule_reset/1-2` | Sends `:reset_save_status` after `timeout_ms` (default 4000ms). Returns socket for piping. |

```elixir
socket
|> assign(:save_status, :saved)
|> SaveStatusTimer.schedule_reset()
```

---

## Remaining `StoryarnWeb.Helpers.*` modules

| Module                  | File                         | What it owns                                                                                                                                         |
| ----------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AutoSnapshot`          | `auto_snapshot.ex`           | `schedule/2`, `cancel/1` — debounced auto-versioning for entity editors                                                                              |
| `EntitySearch`          | `entity_search.ex`           | `search_entities/4`, `search_entities_multi/4`, `search_variables/2-3`, `get_entity_name/3`, `get_entity_name_multi/3`, `get_variable_name/2` — pure |
| `UndoRedoStack`         | `undo_redo_stack.ex`         | `init/1`, `push_undo/2-3`, `push_undo_no_clear/2-3`, `push_coalesced/4-5`, `pop_undo/1`, `pop_redo/1`, `push_redo/2-3`, `clear/1`                    |
| `VersionEventHelpers`   | `version_event_helpers.ex`   | `handle_create`, `handle_delete`, `handle_promote`, `handle_compare`, `handle_*_restore`, `with_authorized_restore`                                  |
| `VersionHistoryHelpers` | `version_history_helpers.ex` | `load_history_data`, `load_more_history`, `serialize_versions`, `show_conflict_preview`, `detect_and_show_restore_preview`                           |

Domain-agnostic LiveView helpers also live in `lib/storyarn_web/live/shared/`:
`CollaborationHelpers`, `DashboardHandlers`, `DashboardHelpers`, `InvitationHelpers`,
`OnboardingHelpers`, `PickerSearch`, `ProjectChromeHelpers`.

---

## JS Utilities

There is no shared JS utility layer under `assets/js/` — it holds only `app.js`
and the `PublicMobileNavigation` / `SeoMetadata` / PostHog scripts. Everything
else is Vue/TypeScript under `assets/app/`:

| Concern                      | Where                                                                     |
| ---------------------------- | ------------------------------------------------------------------------- |
| Pure utilities               | `assets/app/shared/utils/` (`utils.ts`, `date-utils.ts`)                  |
| Composables                  | `assets/app/shared/composables/` (`useLive`, `usePresence`, `useUpload`)  |
| Popovers, dropdowns, dialogs | reka-ui primitives in `assets/app/components/ui/` — never hand-positioned |
| Icons                        | `lucide-vue-next` components; `Record<string, Component>` map for dynamic |
| Flow node canvas metadata    | `assets/app/modules/flows/editor/lib/node-configs.ts`                     |

Import via the `@shared` / `@components` / `@modules` / `@shell` / `@plugins` aliases.

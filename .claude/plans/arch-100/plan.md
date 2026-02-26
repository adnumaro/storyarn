# Plan: Architecture 100% — Fix All Boundary Violations

## Goal
Fix ALL architecture boundary violations to achieve maximum score on architecture audit.

## Convention Document
See `ARCHITECTURE_CONVENTION.md` in this directory for the rules each agent must follow.

---

## Phase 1: Facade Delegations + Web Layer Updates (Parallel by Domain)

### Agent 1: Flows Domain

**Facade:** `lib/storyarn/flows.ex`

**Add delegations for Condition (from `Storyarn.Flows.Condition`):**
```elixir
defdelegate condition_sanitize(condition), to: Condition, as: :sanitize
defdelegate condition_new(), to: Condition, as: :new
defdelegate condition_has_rules?(condition), to: Condition, as: :has_rules?
defdelegate condition_to_json(condition), to: Condition, as: :to_json
defdelegate condition_from_json(json), to: Condition, as: :from_json
```

**Add delegations for Instruction (from `Storyarn.Flows.Instruction`):**
```elixir
defdelegate instruction_sanitize(assignments), to: Instruction, as: :sanitize
defdelegate instruction_format_short(assignment), to: Instruction, as: :format_assignment_short
```

**Add delegations for DebugSessionStore (from `Storyarn.Flows.DebugSessionStore`):**
```elixir
defdelegate debug_session_store(key, data), to: DebugSessionStore, as: :store
defdelegate debug_session_take(key), to: DebugSessionStore, as: :take
```

**Add delegations for NavigationHistoryStore (from `Storyarn.Flows.NavigationHistoryStore`):**
```elixir
defdelegate nav_history_get(key), to: NavigationHistoryStore, as: :get
defdelegate nav_history_put(key, data), to: NavigationHistoryStore, as: :put
defdelegate nav_history_clear(key), to: NavigationHistoryStore, as: :clear
```

**Update web-layer callers (remove submodule aliases, use Flows.xxx):**

| File | Current | New |
|------|---------|-----|
| `components/condition_builder.ex:32,35,36` | `Condition.new()` | `Flows.condition_new()` |
| `live/flow_live/nodes/condition/node.ex:45,91,92,110` | `Condition.sanitize()`, `.to_json()`, `.new()` | `Flows.condition_sanitize()`, `Flows.condition_to_json()`, `Flows.condition_new()` |
| `live/flow_live/components/builder_panel.ex:59,65` | `Condition.has_rules?()` | `Flows.condition_has_rules?()` |
| `live/screenplay_live/show.ex:259,271` | `Condition.sanitize()`, `Instruction.sanitize()` | `Flows.condition_sanitize()`, `Flows.instruction_sanitize()` |
| `live/screenplay_live/handlers/editor_handlers.ex:135,139,190,191` | `Condition.sanitize()`, `Instruction.sanitize()` | `Flows.condition_sanitize()`, `Flows.instruction_sanitize()` |
| `live/screenplay_live/handlers/element_handlers.ex:65,88,164` | `Condition.sanitize()`, `.new()`, `Instruction.sanitize()` | `Flows.condition_sanitize()`, `Flows.condition_new()`, `Flows.instruction_sanitize()` |
| `live/flow_live/nodes/dialogue/node.ex:180` | `Instruction.sanitize()` | `Flows.instruction_sanitize()` |
| `live/flow_live/nodes/instruction/node.ex:38` | `Instruction.sanitize()` | `Flows.instruction_sanitize()` |
| `components/expression_editor.ex:180` | `Instruction.format_assignment_short()` | `Flows.instruction_format_short()` |
| `live/flow_live/player_live.ex:179,444` | `DebugSessionStore.take()`, `.store()` | `Flows.debug_session_take()`, `Flows.debug_session_store()` |
| `live/flow_live/show.ex:281` | `DebugSessionStore.take()` | `Flows.debug_session_take()` |
| `live/flow_live/handlers/debug_execution_handlers.ex:168` | `DebugSessionStore.store()` | `Flows.debug_session_store()` |
| `live/flow_live/show.ex:1139,1141,1149` | `NavigationHistoryStore.get/put` | `Flows.nav_history_get/put` |
| `live/flow_live/index.ex:186` | `NavigationHistoryStore.clear()` | `Flows.nav_history_clear()` |

**After changes:** Remove all `alias Storyarn.Flows.{Condition, Instruction, DebugSessionStore, NavigationHistoryStore}` from web layer files.

---

### Agent 2: Assets Domain

**Facade:** `lib/storyarn/assets.ex`

**Add delegations for Storage (from `Storyarn.Assets.Storage`):**
```elixir
defdelegate storage_upload(key, data, content_type), to: Storage, as: :upload
defdelegate storage_delete(key), to: Storage, as: :delete
```

**Add delegations for ImageProcessor (from `Storyarn.Assets.ImageProcessor`):**
```elixir
defdelegate image_processor_available?(), to: ImageProcessor, as: :available?
defdelegate image_processor_get_dimensions(path), to: ImageProcessor, as: :get_dimensions
```

**Update web-layer callers:**

| File | Current | New |
|------|---------|-----|
| `components/audio_picker.ex:205` | `Storage.upload(...)` | `Assets.storage_upload(...)` |
| `live/sheet_live/helpers/asset_helpers.ex:130,168` | `Assets.Storage.upload(...)` | `Assets.storage_upload(...)` |
| `live/components/asset_upload.ex:233,260,266,267` | `Storage.upload()`, `Storage.delete()`, `ImageProcessor.available?()`, `ImageProcessor.get_dimensions()` | `Assets.storage_upload()`, `Assets.storage_delete()`, `Assets.image_processor_available?()`, `Assets.image_processor_get_dimensions()` |
| `live/sheet_live/components/audio_tab.ex:182` | `Storage.upload(...)` | `Assets.storage_upload(...)` |
| `live/asset_live/index.ex:281,319,322` | `Storage.upload()`, `Storage.delete()` | `Assets.storage_upload()`, `Assets.storage_delete()` |
| `live/sheet_live/components/banner.ex:176` | `Assets.Storage.upload(...)` | `Assets.storage_upload(...)` |
| `live/sheet_live/components/sheet_avatar.ex:139` | `Assets.Storage.upload(...)` | `Assets.storage_upload(...)` |

**After changes:** Remove all `alias Storyarn.Assets.{Storage, ImageProcessor}` from web layer files.

---

### Agent 3: Screenplays Domain

**Facade:** `lib/storyarn/screenplays.ex`

**Add delegations for TiptapSerialization (from `Storyarn.Screenplays.TiptapSerialization`):**
```elixir
defdelegate elements_to_doc(elements), to: TiptapSerialization
```

**Add delegations for ContentUtils (from `Storyarn.Screenplays.ContentUtils`):**
```elixir
defdelegate content_strip_html(html), to: ContentUtils, as: :strip_html
defdelegate content_sanitize_html(html), to: ContentUtils, as: :sanitize_html
```

**Add delegations for CharacterExtension (from `Storyarn.Screenplays.CharacterExtension`):**
```elixir
defdelegate character_base_name(name), to: CharacterExtension, as: :base_name
```

**Move Repo.transaction from web layer to context:**
Create `Screenplays.import_fountain_elements/3` that wraps the Ecto.Multi currently in `fountain_import_handlers.ex:20-47`.

**Update web-layer callers:**

| File | Current | New |
|------|---------|-----|
| `live/screenplay_live/helpers/socket_helpers.ex:60` | `TiptapSerialization.elements_to_doc()` | `Screenplays.elements_to_doc()` |
| `live/screenplay_live/show.ex:119` | `TiptapSerialization.elements_to_doc()` | `Screenplays.elements_to_doc()` |
| `live/screenplay_live/helpers/socket_helpers.ex:102` | `ContentUtils.strip_html()` | `Screenplays.content_strip_html()` |
| `live/localization_live/helpers/localization_helpers.ex:102` | `ContentUtils.strip_html()` | `Screenplays.content_strip_html()` |
| `live/screenplay_live/handlers/editor_handlers.ex:81,169,170` | `ContentUtils.sanitize_html()` | `Screenplays.content_sanitize_html()` |
| `live/screenplay_live/handlers/element_handlers.ex:222` | `ContentUtils.sanitize_html()` | `Screenplays.content_sanitize_html()` |
| `live/screenplay_live/handlers/fountain_import_handlers.ex:116,139` | `CharacterExtension.base_name()` | `Screenplays.character_base_name()` |
| `live/screenplay_live/handlers/fountain_import_handlers.ex:33` | `Repo.transaction()` | `Screenplays.import_fountain_elements(...)` |

**After changes:** Remove all `alias Storyarn.Screenplays.{TiptapSerialization, ContentUtils, CharacterExtension}` and `alias Storyarn.Repo` from web layer files.

---

### Agent 4: Scenes Domain

**Facade:** `lib/storyarn/scenes.ex`

**Add delegations for ZoneImageExtractor (from `Storyarn.Scenes.ZoneImageExtractor`):**
```elixir
defdelegate extract_zone_image(zone, scene, layer), to: ZoneImageExtractor, as: :extract
defdelegate zone_bounding_box(zone), to: ZoneImageExtractor, as: :bounding_box
defdelegate normalize_zone_vertices(zone), to: ZoneImageExtractor, as: :normalize_vertices_to_bbox
```

**Update web-layer callers:**

| File | Current | New |
|------|---------|-----|
| `live/scene_live/helpers/serializer.ex:192` | `ZoneImageExtractor.normalize_vertices_to_bbox()` | `Scenes.normalize_zone_vertices()` |
| `live/scene_live/handlers/tree_handlers.ex:85,181` | `ZoneImageExtractor.extract()`, `.bounding_box()` | `Scenes.extract_zone_image()`, `Scenes.zone_bounding_box()` |

**After changes:** Remove `alias Storyarn.Scenes.ZoneImageExtractor` from web layer files.

---

### Agent 5: Exports Domain

**Facade:** `lib/storyarn/exports.ex`

**Add delegations for SerializerRegistry (from `Storyarn.Exports.SerializerRegistry`):**
```elixir
defdelegate get_serializer(format), to: SerializerRegistry, as: :get
```

**Add delegations for ExportOptions (from `Storyarn.Exports.ExportOptions`):**
```elixir
defdelegate valid_export_formats(), to: ExportOptions, as: :valid_formats
```

**Update web-layer callers:**

| File | Current | New |
|------|---------|-----|
| `controllers/export_controller.ex:23` | `SerializerRegistry.get(format)` | `Exports.get_serializer(format)` |
| `controllers/export_controller.ex:67` | `ExportOptions.valid_formats()` | `Exports.valid_export_formats()` |

**After changes:** Remove `alias Storyarn.Exports.{SerializerRegistry}` from the export_controller. Keep `ExportOptions` alias only if used for struct construction.

---

## Phase 2: Cross-Context Domain Layer Fixes (Parallel)

### Agent 6: Fix Cross-Context Calls (Flows → Sheets/Localization, Scenes → Sheets/Flows)

The domain layer has these cross-context submodule bypasses. Each context should call the OTHER context's facade, not its submodules.

**Flows calling Localization.TextExtractor directly:**
These should call `Localization.extract_xxx` instead. Check if delegations exist; if not, add them.

| File | Current | New |
|------|---------|-----|
| `flows/node_update.ex:100` | `TextExtractor.extract_flow_node(node)` | `Localization.extract_flow_node(node)` |
| `flows/node_delete.ex:49` | `TextExtractor.delete_flow_node_texts(id)` | `Localization.delete_flow_node_texts(id)` |
| `flows/flow_crud.ex:298` | `TextExtractor.extract_flow(flow)` | `Localization.extract_flow(flow)` |
| `flows/flow_crud.ex:313` | `TextExtractor.delete_flow_texts(id)` | `Localization.delete_flow_texts(id)` |
| `flows/flow_crud.ex:320` | `TextExtractor.delete_flow_texts(&1.id)` | `Localization.delete_flow_texts(&1.id)` |

**Flows calling Sheets.ReferenceTracker directly:**
These should call `Sheets.xxx` instead. Check if delegations exist; if not, add them.

| File | Current | New |
|------|---------|-----|
| `flows/node_update.ex:98` | `ReferenceTracker.update_flow_node_references(node)` | `Sheets.update_flow_node_references(node)` |
| `flows/node_delete.ex:47` | `ReferenceTracker.delete_flow_node_references(id)` | `Sheets.delete_flow_node_references(id)` |
| `flows/flow_crud.ex:432` | `ReferenceTracker.count_backlinks("flow", &1.id)` | `Sheets.count_backlinks("flow", &1.id)` |

**Sheets calling Localization.TextExtractor directly:**

| File | Current | New |
|------|---------|-----|
| `sheets/block_crud.ex:176,203,206` | `TextExtractor.extract_block(block)` | `Localization.extract_block(block)` |
| `sheets/block_crud.ex:221` | `TextExtractor.delete_block_texts(id)` | `Localization.delete_block_texts(id)` |
| `sheets/sheet_crud.ex:50` | `TextExtractor.extract_sheet(sheet)` | `Localization.extract_sheet(sheet)` |
| `sheets/sheet_crud.ex:81,85` | `TextExtractor.delete_sheet_texts(id)` | `Localization.delete_sheet_texts(id)` |

**Sheets calling Flows.VariableReferenceTracker directly:**

| File | Current | New |
|------|---------|-----|
| `sheets/block_crud.ex:323` | `VariableReferenceTracker.count_variable_usage(id)` | `Flows.count_variable_usage(id)` — already delegated! |

**Scenes calling Sheets.ReferenceTracker directly:**

| File | Current | New |
|------|---------|-----|
| `scenes/zone_crud.ex:67,86,109` | `ReferenceTracker.update/delete_scene_zone_references()` | Add delegation to Sheets, then use `Sheets.xxx()` |
| `scenes/pin_crud.ex:73,92,112` | `ReferenceTracker.update/delete_scene_pin_references()` | Add delegation to Sheets, then use `Sheets.xxx()` |

**Scenes calling Flows.VariableReferenceTracker directly:**

| File | Current | New |
|------|---------|-----|
| `scenes/zone_crud.ex:68,88,110` | `VariableReferenceTracker.update/delete_map_zone_references()` | Use `Flows.xxx()` — add delegations if missing |
| `scenes/pin_crud.ex:74,93,113` | `VariableReferenceTracker.update/delete_map_pin_references()` | Use `Flows.xxx()` — add delegations if missing |

**Scenes calling Assets.Storage directly:**

| File | Current | New |
|------|---------|-----|
| `scenes/zone_image_extractor.ex:18` | `alias Storyarn.Assets.Storage` | Use `Assets.storage_upload()` etc. — check what functions are used |

**Missing delegations to add:**

In `Localization` facade — add delegations for individual entity extraction/deletion:
```elixir
defdelegate extract_flow_node(node), to: TextExtractor
defdelegate extract_flow(flow), to: TextExtractor
defdelegate extract_block(block), to: TextExtractor
defdelegate extract_sheet(sheet), to: TextExtractor
defdelegate delete_flow_node_texts(node_id), to: TextExtractor
defdelegate delete_flow_texts(flow_id), to: TextExtractor
defdelegate delete_block_texts(block_id), to: TextExtractor
defdelegate delete_sheet_texts(sheet_id), to: TextExtractor
```

In `Sheets` facade — add delegations for scene-specific reference tracking:
```elixir
defdelegate update_flow_node_references(node), to: ReferenceTracker
defdelegate delete_flow_node_references(node_id), to: ReferenceTracker
defdelegate update_scene_zone_references(zone), to: ReferenceTracker
defdelegate delete_map_zone_references(zone_id), to: ReferenceTracker
defdelegate update_scene_pin_references(pin), to: ReferenceTracker
defdelegate delete_map_pin_references(pin_id), to: ReferenceTracker
defdelegate delete_target_references(type, id), to: ReferenceTracker
```

In `Flows` facade — add delegations for scene-specific variable tracking:
```elixir
defdelegate update_scene_zone_references(zone, opts), to: VariableReferenceTracker
defdelegate delete_map_zone_references(zone_id), to: VariableReferenceTracker
defdelegate update_scene_pin_references(pin, opts), to: VariableReferenceTracker
defdelegate delete_map_pin_references(pin_id), to: VariableReferenceTracker
defdelegate delete_references(node_id), to: VariableReferenceTracker
```

---

## Phase 3: Verification

### Agent 7: Architecture Re-Audit

After all fixes are applied and verified with `mix compile --warnings-as-errors`:
1. Re-scan ALL web-layer files for remaining submodule aliases/calls
2. Re-scan ALL domain-layer files for cross-context submodule calls
3. Run `mix xref graph --format cycles` to check cycle impact
4. Produce updated score

---

## Execution Strategy

**Phase 1:** Launch Agents 1-5 in parallel (each owns one domain)
**Phase 2:** Launch Agent 6 after Phase 1 completes (cross-context depends on new delegations)
**Phase 3:** Launch Agent 7 after Phase 2 completes (verification)

Each agent:
1. Reads the convention document
2. Adds delegations to the facade
3. Updates ALL call sites in web layer
4. Removes stale aliases
5. Runs `mix compile --warnings-as-errors` to verify
6. Runs `mix format`

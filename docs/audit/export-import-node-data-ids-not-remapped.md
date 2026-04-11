# Bug: Import does not remap DB IDs inside node data maps

## Severity: high

## Files:
- `lib/storyarn/imports/parsers/storyarn_json.ex` (lines 526-555, specifically `import_nodes` and `clean_node_data`)
- `lib/storyarn/exports/serializers/storyarn_json.ex` (lines 191-213, `serialize_node` and `serialize_node_data`)

## Description

When importing flow nodes, the importer correctly remaps top-level entity IDs (sheet IDs, flow IDs, node IDs, etc.) via the `id_map`. However, the node `data` JSON map is passed through almost unchanged (`clean_node_data` only strips `instruction_assignments`). This map contains several DB integer IDs that refer to entities in the **source** project, not the target project:

1. **`data["speaker_sheet_id"]`** (dialogue nodes) -- Points to the source project's sheet ID. After import, the dialogue node references a nonexistent or wrong sheet as the speaker.

2. **`data["referenced_flow_id"]`** (subflow nodes) -- Points to the source project's flow ID. After import, the subflow node references a nonexistent or wrong flow.

3. **`data["scene_id"]`** (slug_line nodes) -- Points to the source project's scene ID.

4. **Response-level `data["responses"][n]["condition"]`** may contain structured conditions with sheet/variable references by shortcut (not ID), so those are OK.

This bug causes **data corruption** when importing into a different project. Symptoms: broken speaker assignments, broken subflow references, broken scene links. It also causes stale reference indicators to appear in the UI.

## Evidence

Export serializes node data as-is (except adding `instruction_assignments`):
```elixir
# storyarn_json.ex line 198
"data" => serialize_node_data(node.type, node.data || %{})

# line 213 — non-dialogue types pass through unchanged
defp serialize_node_data(_type, data), do: data
```

Import only strips `instruction_assignments`, does not remap IDs:
```elixir
# storyarn_json.ex line 533
"data" => clean_node_data(node_data["data"])

# line 544-555 — only removes instruction_assignments from responses
defp clean_node_data(%{"responses" => responses} = data) when is_list(responses) do
  cleaned = Enum.map(responses, fn resp ->
    Map.delete(resp, "instruction_assignments")
  end)
  Map.put(data, "responses", cleaned)
end
defp clean_node_data(data), do: data
```

The actual node types that store DB IDs in their data:
```elixir
# Dialogue: speaker_sheet_id is a DB integer
# nodes/dialogue/node.ex uses data["speaker_sheet_id"]

# Subflow: referenced_flow_id is a DB integer  
# nodes/subflow/node.ex line 23
def default_data, do: %{"referenced_flow_id" => nil}

# Slug line: scene_id
# flows/flow_crud.ex line 389 uses data["scene_id"]
```

## Suggested Fix

Add ID remapping to `clean_node_data` or create a new `remap_node_data` function:

```elixir
defp remap_node_data(nil, _map), do: %{}

defp remap_node_data(data, map) do
  data
  |> remap_data_field(map, "speaker_sheet_id", :sheet)
  |> remap_data_field(map, "referenced_flow_id", :flow)
  |> remap_data_field(map, "scene_id", :scene)
  |> clean_responses()
end

defp remap_data_field(data, map, field, type) do
  case data[field] do
    nil -> data
    "" -> data
    old_id -> Map.put(data, field, remap_id(map, type, old_id))
  end
end

defp clean_responses(%{"responses" => responses} = data) when is_list(responses) do
  cleaned = Enum.map(responses, &Map.delete(&1, "instruction_assignments"))
  Map.put(data, "responses", cleaned)
end

defp clean_responses(data), do: data
```

Then in `import_nodes`:
```elixir
"data" => remap_node_data(node_data["data"], map)
```

Note: Remapping must happen **after** all entities of the referenced type have been imported. Currently flows are imported after sheets but before scenes, so `scene_id` in slug_line nodes won't have a mapping yet. The import order may need adjustment, or scene_id remapping should be done in a post-processing pass.

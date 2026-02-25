defmodule Storyarn.Imports.Parsers.StoryarnJSON do
  @moduledoc """
  Parses and imports Storyarn JSON format files.

  Handles:
  - JSON parsing and structure validation
  - Import preview with entity counts and conflict detection
  - Import execution with ID remapping and conflict resolution
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Localization.{GlossaryEntry, LocalizedText, ProjectLanguage}
  alias Storyarn.Scenes.{Scene, SceneAnnotation, SceneConnection, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Screenplays.{Screenplay, ScreenplayElement}
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}

  @required_top_keys ~w(storyarn_version export_version project)

  @max_entity_counts %{
    sheets: 1_000,
    flows: 500,
    nodes_per_flow: 5_000,
    scenes: 200,
    screenplays: 500,
    assets: 5_000,
    languages: 50,
    localized_texts: 100_000,
    glossary_entries: 10_000
  }

  # =============================================================================
  # Parse
  # =============================================================================

  @doc """
  Parse a JSON binary into a structured map.

  Validates the top-level structure. Returns `{:ok, data}` or `{:error, reason}`.
  """
  def parse(binary) when is_binary(binary) do
    with {:ok, data} <- decode_json(binary),
         :ok <- validate_structure(data) do
      {:ok, data}
    end
  end

  defp decode_json(binary) do
    case Jason.decode(binary) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, :invalid_json_structure}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp validate_structure(data) do
    missing = Enum.reject(@required_top_keys, &Map.has_key?(data, &1))

    if missing == [] do
      :ok
    else
      {:error, {:missing_required_keys, missing}}
    end
  end

  # =============================================================================
  # Preview
  # =============================================================================

  @doc """
  Generate a preview of what an import would create.

  Returns entity counts and detected shortcut conflicts.
  """
  def preview(project_id, data) do
    counts = count_import_entities(data)
    conflicts = detect_conflicts(project_id, data)

    {:ok,
     %{
       counts: counts,
       conflicts: conflicts,
       has_conflicts: conflicts != %{}
     }}
  end

  defp count_import_entities(data) do
    %{
      sheets: length(data["sheets"] || []),
      flows: length(data["flows"] || []),
      nodes: (data["flows"] || []) |> Enum.flat_map(&(Map.get(&1, "nodes") || [])) |> length(),
      scenes: length(data["scenes"] || []),
      screenplays: length(data["screenplays"] || []),
      assets: length(get_in(data, ["assets", "items"]) || [])
    }
  end

  defp detect_conflicts(project_id, data) do
    conflicts = %{}

    conflicts = detect_shortcut_conflicts(conflicts, project_id, Sheet, data["sheets"] || [])
    conflicts = detect_shortcut_conflicts(conflicts, project_id, Flow, data["flows"] || [])
    conflicts = detect_shortcut_conflicts(conflicts, project_id, Scene, data["scenes"] || [])
    detect_shortcut_conflicts(conflicts, project_id, Screenplay, data["screenplays"] || [])
  end

  defp detect_shortcut_conflicts(conflicts, project_id, schema, entities) do
    shortcuts =
      entities
      |> Enum.map(& &1["shortcut"])
      |> Enum.reject(&is_nil/1)

    if shortcuts == [] do
      conflicts
    else
      existing =
        from(e in schema,
          where:
            e.project_id == ^project_id and e.shortcut in ^shortcuts and is_nil(e.deleted_at),
          select: e.shortcut
        )
        |> Repo.all()

      if existing == [] do
        conflicts
      else
        key = schema |> Module.split() |> List.last() |> String.downcase() |> String.to_atom()
        Map.put(conflicts, key, existing)
      end
    end
  end

  # =============================================================================
  # Execute
  # =============================================================================

  @doc """
  Execute the import into a project.

  Options:
  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:skip`)

  Uses a database transaction. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(project, data, opts \\ []) do
    strategy = Keyword.get(opts, :conflict_strategy, :skip)

    with :ok <- validate_entity_counts(data) do
      existing_shortcuts = preload_existing_shortcuts(project.id)

      Repo.transaction(
        fn ->
          id_map = %{}

          {id_map, asset_results} = import_assets(project.id, data, id_map)

          {id_map, sheet_results} =
            import_sheets(project, data, id_map, strategy, existing_shortcuts)

          {id_map, flow_results} =
            import_flows(project, data, id_map, strategy, existing_shortcuts)

          {id_map, scene_results} =
            import_scenes(project, data, id_map, strategy, existing_shortcuts)

          {id_map, screenplay_results} =
            import_screenplays(project, data, id_map, strategy, existing_shortcuts)

          {_id_map, loc_results} = import_localization(project.id, data, id_map)

          %{
            assets: asset_results,
            sheets: sheet_results,
            flows: flow_results,
            scenes: scene_results,
            screenplays: screenplay_results,
            localization: loc_results
          }
        end,
        timeout: :timer.minutes(5)
      )
    end
  end

  # =============================================================================
  # Entity count validation
  # =============================================================================

  defp validate_entity_counts(data) do
    checks = build_entity_checks(data)
    violations = Enum.filter(checks, fn {_key, count, limit} -> count > limit end)

    if violations == [] do
      :ok
    else
      details =
        Map.new(violations, fn {key, count, limit} ->
          {key, %{count: count, limit: limit}}
        end)

      {:error, {:entity_limits_exceeded, details}}
    end
  end

  defp build_entity_checks(data) do
    flows = data["flows"] || []

    build_core_checks(data, flows) ++ build_localization_checks(data)
  end

  defp build_core_checks(data, flows) do
    max_nodes_per_flow =
      flows |> Enum.map(fn f -> length(f["nodes"] || []) end) |> Enum.max(fn -> 0 end)

    [
      {:sheets, length(data["sheets"] || []), @max_entity_counts.sheets},
      {:flows, length(flows), @max_entity_counts.flows},
      {:nodes_per_flow, max_nodes_per_flow, @max_entity_counts.nodes_per_flow},
      {:scenes, length(data["scenes"] || []), @max_entity_counts.scenes},
      {:screenplays, length(data["screenplays"] || []), @max_entity_counts.screenplays},
      {:assets, length(get_in(data, ["assets", "items"]) || []), @max_entity_counts.assets}
    ]
  end

  defp build_localization_checks(data) do
    loc = data["localization"]
    loc_strings = (loc && loc["strings"]) || []
    glossary = (loc && loc["glossary"]) || []

    [
      {:languages, length((loc && loc["languages"]) || []), @max_entity_counts.languages},
      {:localized_texts, count_translations(loc_strings), @max_entity_counts.localized_texts},
      {:glossary_entries, count_translations(glossary), @max_entity_counts.glossary_entries}
    ]
  end

  defp count_translations(entries) do
    Enum.reduce(entries, 0, fn entry, acc ->
      acc + map_size(entry["translations"] || %{})
    end)
  end

  # =============================================================================
  # Shortcut pre-loading
  # =============================================================================

  defp preload_existing_shortcuts(project_id) do
    %{
      sheet: load_shortcuts(Sheet, project_id),
      flow: load_shortcuts(Flow, project_id),
      scene: load_shortcuts(Scene, project_id),
      screenplay: load_shortcuts(Screenplay, project_id)
    }
  end

  defp load_shortcuts(schema, project_id) do
    from(e in schema,
      where: e.project_id == ^project_id and is_nil(e.deleted_at),
      select: e.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # =============================================================================
  # Assets import
  # =============================================================================

  defp import_assets(project_id, data, id_map) do
    items = get_in(data, ["assets", "items"]) || []

    Enum.reduce(items, {id_map, []}, fn item, {map, results} ->
      attrs = %{
        "filename" => item["filename"],
        "content_type" => item["content_type"],
        "size" => item["size"],
        "key" => regenerate_asset_key(item["filename"]),
        "url" => item["url"],
        "metadata" => item["metadata"] || %{}
      }

      changeset = Asset.create_changeset(%Asset{project_id: project_id}, attrs)
      asset = insert_or_rollback!(changeset, {:asset, item["filename"]})

      {Map.put(map, {:asset, item["id"]}, asset.id), [asset | results]}
    end)
  end

  # =============================================================================
  # Sheets import (two-pass for parent_id)
  # =============================================================================

  defp import_sheets(project, data, id_map, strategy, existing_shortcuts) do
    sheets = data["sheets"] || []

    if sheets == [],
      do: {id_map, []},
      else: do_import_sheets(project, sheets, id_map, strategy, existing_shortcuts)
  end

  defp do_import_sheets(project, sheets, id_map, strategy, existing_shortcuts) do
    # Pass 1: create all sheets without parent_id
    {id_map, sheet_records} =
      Enum.reduce(sheets, {id_map, []}, fn sheet_data, {map, records} ->
        case resolve_shortcut(
               sheet_data["shortcut"],
               strategy,
               project.id,
               Sheet,
               existing_shortcuts
             ) do
          :skip ->
            {map, records}

          shortcut ->
            attrs = %{
              "name" => sheet_data["name"],
              "shortcut" => shortcut,
              "description" => sheet_data["description"],
              "color" => sheet_data["color"],
              "position" => sheet_data["position"] || 0,
              "avatar_asset_id" => remap_id(map, :asset, sheet_data["avatar_asset_id"]),
              "banner_asset_id" => remap_id(map, :asset, sheet_data["banner_asset_id"]),
              "hidden_inherited_block_ids" => []
            }

            changeset = Sheet.create_changeset(%Sheet{project_id: project.id}, attrs)
            sheet = insert_or_rollback!(changeset, {:sheet, sheet_data["name"]})

            map = Map.put(map, {:sheet, sheet_data["id"]}, sheet.id)

            # Import blocks
            {map, _} = import_blocks(sheet.id, sheet_data["blocks"] || [], map)

            {map, [{sheet, sheet_data} | records]}
        end
      end)

    # Pass 2: set parent_id references
    link_parent_ids(sheet_records, id_map, :sheet)

    {id_map, Enum.map(sheet_records, fn {sheet, _} -> sheet end)}
  end

  defp import_blocks(sheet_id, blocks, id_map) do
    Enum.reduce(blocks, {id_map, []}, fn block_data, {map, results} ->
      attrs = build_block_attrs(block_data)

      changeset = Block.create_changeset(%Block{sheet_id: sheet_id}, attrs)
      block = insert_or_rollback!(changeset, {:block, block_data["type"]})

      map = Map.put(map, {:block, block_data["id"]}, block.id)
      map = maybe_import_table_data(map, block, block_data)

      {map, [block | results]}
    end)
  end

  defp build_block_attrs(block_data) do
    %{
      "type" => block_data["type"],
      "position" => block_data["position"] || 0,
      "config" => block_data["config"] || %{},
      "value" => block_data["value"] || %{},
      "is_constant" => block_data["is_constant"] || false,
      "variable_name" => block_data["variable_name"],
      "scope" => block_data["scope"],
      "required" => block_data["required"] || false,
      "detached" => block_data["detached"] || false,
      "column_group_id" => block_data["column_group_id"],
      "column_index" => block_data["column_index"]
    }
  end

  defp maybe_import_table_data(map, block, %{"type" => "table"} = block_data) do
    table_data = block_data["table_data"] || %{}
    {map, _} = import_table_columns(block.id, table_data["columns"] || [], map)
    {map, _} = import_table_rows(block.id, table_data["rows"] || [], map)
    map
  end

  defp maybe_import_table_data(map, _block, _block_data), do: map

  defp import_table_columns(block_id, columns, id_map) do
    Enum.reduce(columns, {id_map, []}, fn col_data, {map, results} ->
      attrs = %{
        "name" => col_data["name"],
        "type" => col_data["type"],
        "is_constant" => col_data["is_constant"] || false,
        "required" => col_data["required"] || false,
        "position" => col_data["position"] || 0,
        "config" => col_data["config"] || %{}
      }

      changeset = TableColumn.create_changeset(%TableColumn{block_id: block_id}, attrs)
      col = insert_or_rollback!(changeset, {:table_column, col_data["name"]})

      {Map.put(map, {:table_column, col_data["id"]}, col.id), [col | results]}
    end)
  end

  defp import_table_rows(block_id, rows, id_map) do
    Enum.reduce(rows, {id_map, []}, fn row_data, {map, results} ->
      attrs = %{
        "name" => row_data["name"],
        "position" => row_data["position"] || 0,
        "cells" => row_data["cells"] || %{}
      }

      changeset = TableRow.create_changeset(%TableRow{block_id: block_id}, attrs)
      row = insert_or_rollback!(changeset, {:table_row, row_data["name"]})

      {Map.put(map, {:table_row, row_data["id"]}, row.id), [row | results]}
    end)
  end

  # =============================================================================
  # Flows import (two-pass for parent_id)
  # =============================================================================

  defp import_flows(project, data, id_map, strategy, existing_shortcuts) do
    flows = data["flows"] || []

    if flows == [],
      do: {id_map, []},
      else: do_import_flows(project, flows, id_map, strategy, existing_shortcuts)
  end

  defp do_import_flows(project, flows, id_map, strategy, existing_shortcuts) do
    # Pass 1: create flows without parent_id
    {id_map, flow_records} =
      Enum.reduce(flows, {id_map, []}, fn flow_data, {map, records} ->
        case resolve_shortcut(
               flow_data["shortcut"],
               strategy,
               project.id,
               Flow,
               existing_shortcuts
             ) do
          :skip ->
            {map, records}

          shortcut ->
            {map, flow} = create_flow_record(project, flow_data, shortcut, map)
            {map, [{flow, flow_data} | records]}
        end
      end)

    # Pass 2: set parent_id
    link_parent_ids(flow_records, id_map, :flow)

    {id_map, Enum.map(flow_records, fn {flow, _} -> flow end)}
  end

  defp create_flow_record(project, flow_data, shortcut, map) do
    attrs = %{
      "name" => flow_data["name"],
      "shortcut" => shortcut,
      "description" => flow_data["description"],
      "position" => flow_data["position"] || 0,
      "is_main" => flow_data["is_main"] || false,
      "settings" => flow_data["settings"] || %{},
      "scene_id" => remap_id(map, :scene, flow_data["scene_id"])
    }

    changeset = Flow.create_changeset(%Flow{project_id: project.id}, attrs)
    flow = insert_or_rollback!(changeset, {:flow, flow_data["name"]})

    map = Map.put(map, {:flow, flow_data["id"]}, flow.id)
    {map, _} = import_nodes(flow.id, flow_data["nodes"] || [], map)
    {map, _} = import_flow_connections(flow.id, flow_data["connections"] || [], map)

    {map, flow}
  end

  defp import_nodes(flow_id, nodes, id_map) do
    Enum.reduce(nodes, {id_map, []}, fn node_data, {map, results} ->
      attrs = %{
        "type" => node_data["type"],
        "position_x" => node_data["position_x"] || 0.0,
        "position_y" => node_data["position_y"] || 0.0,
        "source" => node_data["source"],
        "data" => clean_node_data(node_data["data"])
      }

      changeset = FlowNode.create_changeset(%FlowNode{flow_id: flow_id}, attrs)
      node = insert_or_rollback!(changeset, {:node, node_data["type"]})

      {Map.put(map, {:node, node_data["id"]}, node.id), [node | results]}
    end)
  end

  # Remove instruction_assignments (serializer-added field, not stored in DB)
  defp clean_node_data(nil), do: %{}

  defp clean_node_data(%{"responses" => responses} = data) when is_list(responses) do
    cleaned =
      Enum.map(responses, fn resp ->
        Map.delete(resp, "instruction_assignments")
      end)

    Map.put(data, "responses", cleaned)
  end

  defp clean_node_data(data), do: data

  defp import_flow_connections(flow_id, connections, id_map) do
    now = Storyarn.Shared.TimeHelpers.now()

    # Build valid connection attrs, filtering out those with missing node references
    {valid_attrs, _} =
      Enum.reduce(connections, {[], id_map}, fn conn_data, {acc, map} ->
        source_node_id = Map.get(map, {:node, conn_data["source_node_id"]})
        target_node_id = Map.get(map, {:node, conn_data["target_node_id"]})

        if source_node_id && target_node_id && source_node_id != target_node_id do
          attrs = %{
            flow_id: flow_id,
            source_node_id: source_node_id,
            target_node_id: target_node_id,
            source_pin: truncate_string(conn_data["source_pin"], 100),
            target_pin: truncate_string(conn_data["target_pin"], 100),
            label: truncate_string(conn_data["label"], 200),
            inserted_at: now,
            updated_at: now
          }

          {[attrs | acc], map}
        else
          {acc, map}
        end
      end)

    # Batch insert in chunks of 500
    results =
      valid_attrs
      |> Enum.reverse()
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_count, inserted} = Repo.insert_all(FlowConnection, chunk, returning: [:id])
        inserted
      end)

    {id_map, results}
  end

  defp truncate_string(nil, _max), do: nil
  defp truncate_string(str, max) when is_binary(str), do: String.slice(str, 0, max)
  defp truncate_string(val, _max), do: val

  # =============================================================================
  # Scenes import (two-pass for parent_id)
  # =============================================================================

  defp import_scenes(project, data, id_map, strategy, existing_shortcuts) do
    scenes = data["scenes"] || []

    if scenes == [],
      do: {id_map, []},
      else: do_import_scenes(project, scenes, id_map, strategy, existing_shortcuts)
  end

  defp do_import_scenes(project, scenes, id_map, strategy, existing_shortcuts) do
    {id_map, scene_records} =
      Enum.reduce(scenes, {id_map, []}, fn scene_data, {map, records} ->
        case resolve_shortcut(
               scene_data["shortcut"],
               strategy,
               project.id,
               Scene,
               existing_shortcuts
             ) do
          :skip ->
            {map, records}

          shortcut ->
            {map, scene} = create_scene_record(project, scene_data, shortcut, map)
            {map, [{scene, scene_data} | records]}
        end
      end)

    link_parent_ids(scene_records, id_map, :scene)

    {id_map, Enum.map(scene_records, fn {scene, _} -> scene end)}
  end

  defp create_scene_record(project, scene_data, shortcut, map) do
    attrs = %{
      "name" => scene_data["name"],
      "shortcut" => shortcut,
      "description" => scene_data["description"],
      "position" => scene_data["position"] || 0,
      "background_asset_id" => remap_id(map, :asset, scene_data["background_asset_id"]),
      "width" => scene_data["width"],
      "height" => scene_data["height"],
      "default_zoom" => scene_data["default_zoom"],
      "default_center_x" => scene_data["default_center_x"],
      "default_center_y" => scene_data["default_center_y"],
      "scale_unit" => scene_data["scale_unit"],
      "scale_value" => scene_data["scale_value"]
    }

    changeset = Scene.create_changeset(%Scene{project_id: project.id}, attrs)
    scene = insert_or_rollback!(changeset, {:scene, scene_data["name"]})

    map = Map.put(map, {:scene, scene_data["id"]}, scene.id)
    {map, _} = import_layers(scene.id, scene_data["layers"] || [], map)
    {map, _} = import_pins(scene.id, scene_data["pins"] || [], map)
    {map, _} = import_zones(scene.id, scene_data["zones"] || [], map)
    {map, _} = import_scene_connections(scene.id, scene_data["connections"] || [], map)
    {map, _} = import_annotations(scene.id, scene_data["annotations"] || [], map)

    {map, scene}
  end

  defp import_layers(scene_id, layers, id_map) do
    Enum.reduce(layers, {id_map, []}, fn layer_data, {map, results} ->
      attrs = %{
        "name" => layer_data["name"],
        "is_default" => layer_data["is_default"] || false,
        "position" => layer_data["position"] || 0,
        "visible" => Map.get(layer_data, "visible", true),
        "fog_enabled" => layer_data["fog_enabled"] || false,
        "fog_color" => layer_data["fog_color"],
        "fog_opacity" => layer_data["fog_opacity"]
      }

      changeset = SceneLayer.create_changeset(%SceneLayer{scene_id: scene_id}, attrs)
      layer = insert_or_rollback!(changeset, {:layer, layer_data["name"]})

      {Map.put(map, {:layer, layer_data["id"]}, layer.id), [layer | results]}
    end)
  end

  defp import_pins(scene_id, pins, id_map) do
    Enum.reduce(pins, {id_map, []}, fn pin_data, {map, results} ->
      attrs = %{
        "layer_id" => remap_id(map, :layer, pin_data["layer_id"]),
        "position_x" => pin_data["position_x"] || 0.0,
        "position_y" => pin_data["position_y"] || 0.0,
        "pin_type" => pin_data["pin_type"],
        "icon" => pin_data["icon"],
        "color" => pin_data["color"],
        "opacity" => pin_data["opacity"],
        "label" => pin_data["label"],
        "target_type" => pin_data["target_type"],
        "target_id" => remap_target_id(map, pin_data["target_type"], pin_data["target_id"]),
        "tooltip" => pin_data["tooltip"],
        "size" => pin_data["size"],
        "position" => pin_data["position"] || 0,
        "locked" => pin_data["locked"] || false,
        "icon_asset_id" => remap_id(map, :asset, pin_data["icon_asset_id"]),
        "sheet_id" => remap_id(map, :sheet, pin_data["sheet_id"]),
        "action_type" => pin_data["action_type"],
        "action_data" => pin_data["action_data"] || %{},
        "condition" => pin_data["condition"],
        "condition_effect" => pin_data["condition_effect"]
      }

      changeset = ScenePin.create_changeset(%ScenePin{scene_id: scene_id}, attrs)
      pin = insert_or_rollback!(changeset, {:pin, pin_data["label"]})

      {Map.put(map, {:pin, pin_data["id"]}, pin.id), [pin | results]}
    end)
  end

  defp import_zones(scene_id, zones, id_map) do
    Enum.reduce(zones, {id_map, []}, fn zone_data, {map, results} ->
      attrs = %{
        "name" => zone_data["name"],
        "layer_id" => remap_id(map, :layer, zone_data["layer_id"]),
        "vertices" => zone_data["vertices"] || [],
        "fill_color" => zone_data["fill_color"],
        "border_color" => zone_data["border_color"],
        "border_width" => zone_data["border_width"],
        "border_style" => zone_data["border_style"],
        "opacity" => zone_data["opacity"],
        "target_type" => zone_data["target_type"],
        "target_id" => remap_target_id(map, zone_data["target_type"], zone_data["target_id"]),
        "tooltip" => zone_data["tooltip"],
        "position" => zone_data["position"] || 0,
        "locked" => zone_data["locked"] || false,
        "action_type" => zone_data["action_type"],
        "action_data" => zone_data["action_data"] || %{},
        "condition" => zone_data["condition"],
        "condition_effect" => zone_data["condition_effect"]
      }

      changeset = SceneZone.create_changeset(%SceneZone{scene_id: scene_id}, attrs)
      zone = insert_or_rollback!(changeset, {:zone, zone_data["name"]})

      {Map.put(map, {:zone, zone_data["id"]}, zone.id), [zone | results]}
    end)
  end

  defp import_scene_connections(scene_id, connections, id_map) do
    now = Storyarn.Shared.TimeHelpers.now()

    # Build valid connection attrs, filtering out those with missing pin references
    valid_attrs =
      Enum.reduce(connections, [], fn conn_data, acc ->
        from_pin_id = Map.get(id_map, {:pin, conn_data["from_pin_id"]})
        to_pin_id = Map.get(id_map, {:pin, conn_data["to_pin_id"]})

        if from_pin_id && to_pin_id do
          attrs = %{
            scene_id: scene_id,
            from_pin_id: from_pin_id,
            to_pin_id: to_pin_id,
            line_style: conn_data["line_style"] || "solid",
            line_width: conn_data["line_width"] || 2,
            color: conn_data["color"],
            label: conn_data["label"],
            show_label: Map.get(conn_data, "show_label", true),
            bidirectional: conn_data["bidirectional"] || false,
            waypoints: conn_data["waypoints"] || [],
            inserted_at: now,
            updated_at: now
          }

          [attrs | acc]
        else
          acc
        end
      end)

    # Batch insert in chunks of 500
    results =
      valid_attrs
      |> Enum.reverse()
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_count, inserted} = Repo.insert_all(SceneConnection, chunk, returning: [:id])
        inserted
      end)

    {id_map, results}
  end

  defp import_annotations(scene_id, annotations, id_map) do
    now = Storyarn.Shared.TimeHelpers.now()

    # Build annotation attrs with remapped layer_id references
    valid_attrs =
      Enum.reduce(annotations, [], fn ann_data, acc ->
        attrs = %{
          scene_id: scene_id,
          text: ann_data["text"],
          position_x: ann_data["position_x"] || 0.0,
          position_y: ann_data["position_y"] || 0.0,
          font_size: ann_data["font_size"] || "md",
          color: ann_data["color"],
          layer_id: remap_id(id_map, :layer, ann_data["layer_id"]),
          position: ann_data["position"] || 0,
          locked: ann_data["locked"] || false,
          inserted_at: now,
          updated_at: now
        }

        [attrs | acc]
      end)

    # Batch insert in chunks of 500
    results =
      valid_attrs
      |> Enum.reverse()
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_count, inserted} = Repo.insert_all(SceneAnnotation, chunk, returning: [:id])
        inserted
      end)

    {id_map, results}
  end

  # =============================================================================
  # Screenplays import (two-pass for parent_id)
  # =============================================================================

  defp import_screenplays(project, data, id_map, strategy, existing_shortcuts) do
    screenplays = data["screenplays"] || []

    if screenplays == [],
      do: {id_map, []},
      else: do_import_screenplays(project, screenplays, id_map, strategy, existing_shortcuts)
  end

  defp do_import_screenplays(project, screenplays, id_map, strategy, existing_shortcuts) do
    {id_map, sp_records} =
      Enum.reduce(screenplays, {id_map, []}, fn sp_data, {map, records} ->
        case resolve_shortcut(
               sp_data["shortcut"],
               strategy,
               project.id,
               Screenplay,
               existing_shortcuts
             ) do
          :skip ->
            {map, records}

          shortcut ->
            {map, sp} = create_screenplay_record(project, sp_data, shortcut, map)
            {map, [{sp, sp_data} | records]}
        end
      end)

    # Pass 2: parent_id + draft_of_id
    link_screenplay_refs(sp_records, id_map)

    {id_map, Enum.map(sp_records, fn {sp, _} -> sp end)}
  end

  defp create_screenplay_record(project, sp_data, shortcut, map) do
    attrs = %{
      "name" => sp_data["name"],
      "shortcut" => shortcut,
      "description" => sp_data["description"],
      "position" => sp_data["position"] || 0
    }

    changeset =
      Screenplay.create_changeset(%Screenplay{project_id: project.id}, attrs)
      |> maybe_put_change(:linked_flow_id, remap_id(map, :flow, sp_data["linked_flow_id"]))
      |> maybe_put_change(:draft_label, sp_data["draft_label"])
      |> maybe_put_change(:draft_status, sp_data["draft_status"] || "active")

    sp = insert_or_rollback!(changeset, {:screenplay, sp_data["name"]})

    map = Map.put(map, {:screenplay, sp_data["id"]}, sp.id)
    {map, _} = import_elements(sp.id, sp_data["elements"] || [], map)

    {map, sp}
  end

  defp link_screenplay_refs(sp_records, id_map) do
    for {sp, sp_data} <- sp_records do
      changes =
        %{}
        |> maybe_remap_ref(:parent_id, id_map, :screenplay, sp_data["parent_id"])
        |> maybe_remap_ref(:draft_of_id, id_map, :screenplay, sp_data["draft_of_id"])

      if changes != %{} do
        sp |> Ecto.Changeset.change(changes) |> Repo.update!()
      end
    end
  end

  defp import_elements(screenplay_id, elements, id_map) do
    Enum.reduce(elements, {id_map, []}, fn el_data, {map, results} ->
      attrs = %{
        "type" => el_data["type"],
        "position" => el_data["position"] || 0,
        "content" => el_data["content"],
        "data" => el_data["data"] || %{},
        "depth" => el_data["depth"] || 0,
        "branch" => el_data["branch"]
      }

      # Two-step: create_changeset doesn't cast linked_node_id
      changeset =
        ScreenplayElement.create_changeset(
          %ScreenplayElement{screenplay_id: screenplay_id},
          attrs
        )
        |> maybe_put_change(:linked_node_id, remap_id(map, :node, el_data["linked_node_id"]))

      el = insert_or_rollback!(changeset, {:element, el_data["type"]})

      {Map.put(map, {:element, el_data["id"]}, el.id), [el | results]}
    end)
  end

  # =============================================================================
  # Localization import
  # =============================================================================

  defp import_localization(project_id, data, id_map) do
    loc = data["localization"]
    if is_nil(loc), do: {id_map, %{}}, else: do_import_localization(project_id, loc, id_map)
  end

  defp do_import_localization(project_id, loc, id_map) do
    # Import languages
    {id_map, _} = import_languages(project_id, loc["languages"] || [], id_map)

    # Import strings
    _ = import_localized_texts(project_id, loc["strings"] || [], id_map)

    # Import glossary
    _ = import_glossary(project_id, loc["glossary"] || [])

    {id_map, %{languages: length(loc["languages"] || []), strings: length(loc["strings"] || [])}}
  end

  defp import_languages(project_id, languages, id_map) do
    Enum.reduce(languages, {id_map, []}, fn lang_data, {map, results} ->
      attrs = %{
        "locale_code" => lang_data["locale_code"],
        "name" => lang_data["name"],
        "is_source" => lang_data["is_source"] || false,
        "position" => lang_data["position"] || 0
      }

      changeset =
        ProjectLanguage.create_changeset(%ProjectLanguage{project_id: project_id}, attrs)

      lang = insert_or_rollback!(changeset, {:language, lang_data["locale_code"]})

      {Map.put(map, {:language, lang_data["locale_code"]}, lang.id), [lang | results]}
    end)
  end

  defp import_localized_texts(project_id, strings, id_map) do
    now = Storyarn.Shared.TimeHelpers.now()

    # Build all text attrs from the nested strings/translations structure
    valid_attrs =
      Enum.reduce(strings, [], fn entry, acc ->
        translations = entry["translations"] || %{}
        remapped_source_id = remap_source_id(id_map, entry["source_type"], entry["source_id"])
        source_id = remapped_source_id || MapUtils.parse_int(entry["source_id"])

        Enum.reduce(translations, acc, fn {locale_code, translation}, inner_acc ->
          attrs = %{
            project_id: project_id,
            source_type: entry["source_type"],
            source_id: source_id,
            source_field: entry["source_field"],
            source_text: entry["source_text"],
            source_text_hash: entry["source_text_hash"],
            speaker_sheet_id: remap_id(id_map, :sheet, entry["speaker_sheet_id"]),
            locale_code: locale_code,
            translated_text: translation["translated_text"],
            status: translation["status"] || "pending",
            vo_status: translation["vo_status"] || "none",
            vo_asset_id: remap_id(id_map, :asset, translation["vo_asset_id"]),
            translator_notes: translation["translator_notes"],
            reviewer_notes: translation["reviewer_notes"],
            word_count: translation["word_count"],
            machine_translated: translation["machine_translated"] || false,
            last_translated_at: parse_datetime(translation["last_translated_at"]),
            last_reviewed_at: parse_datetime(translation["last_reviewed_at"]),
            translated_by_id: nil,
            reviewed_by_id: nil,
            inserted_at: now,
            updated_at: now
          }

          [attrs | inner_acc]
        end)
      end)

    # Batch insert in chunks of 500 with on_conflict: :nothing for duplicates
    valid_attrs
    |> Enum.reverse()
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(LocalizedText, chunk, on_conflict: :nothing)
    end)
  end

  defp import_glossary(project_id, glossary_entries) do
    now = Storyarn.Shared.TimeHelpers.now()

    # Build all glossary attrs from the nested entries/translations structure
    valid_attrs =
      Enum.reduce(glossary_entries, [], fn entry, acc ->
        translations = entry["translations"] || %{}

        Enum.reduce(translations, acc, fn {target_locale, target_term}, inner_acc ->
          attrs = %{
            project_id: project_id,
            source_term: entry["source_term"],
            source_locale: entry["source_locale"],
            target_locale: target_locale,
            target_term: target_term,
            do_not_translate: entry["do_not_translate"] || false,
            context: entry["context"],
            inserted_at: now,
            updated_at: now
          }

          [attrs | inner_acc]
        end)
      end)

    # Batch insert in chunks of 500
    valid_attrs
    |> Enum.reverse()
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(GlossaryEntry, chunk)
    end)
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp remap_id(_map, _type, nil), do: nil

  defp remap_id(map, type, old_id) do
    Map.get(map, {type, old_id})
  end

  defp remap_source_id(_map, _source_type, nil), do: nil
  defp remap_source_id(map, "flow_node", old_id), do: Map.get(map, {:node, old_id})
  defp remap_source_id(map, "block", old_id), do: Map.get(map, {:block, old_id})
  defp remap_source_id(map, "sheet", old_id), do: Map.get(map, {:sheet, old_id})
  defp remap_source_id(map, "flow", old_id), do: Map.get(map, {:flow, old_id})
  defp remap_source_id(map, "scene", old_id), do: Map.get(map, {:scene, old_id})
  defp remap_source_id(map, "screenplay", old_id), do: Map.get(map, {:screenplay, old_id})
  defp remap_source_id(map, "screenplay_element", old_id), do: Map.get(map, {:element, old_id})
  defp remap_source_id(_map, _source_type, _old_id), do: nil

  defp remap_target_id(_map, nil, _target_id), do: nil
  defp remap_target_id(_map, _type, nil), do: nil

  defp remap_target_id(map, target_type, target_id) do
    type =
      case target_type do
        "sheet" -> :sheet
        "flow" -> :flow
        "scene" -> :scene
        _ -> nil
      end

    if type, do: Map.get(map, {type, target_id}), else: nil
  end

  defp resolve_shortcut(nil, _strategy, _project_id, _schema, _existing_shortcuts), do: nil

  defp resolve_shortcut(shortcut, strategy, project_id, schema, existing_shortcuts) do
    key = schema_shortcut_key(schema)
    existing_set = Map.fetch!(existing_shortcuts, key)
    exists? = MapSet.member?(existing_set, shortcut)

    cond do
      not exists? ->
        shortcut

      strategy == :skip ->
        :skip

      strategy == :overwrite ->
        overwrite_existing(shortcut, project_id, schema)

      strategy == :rename ->
        suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
        "#{shortcut}-#{suffix}"

      true ->
        shortcut
    end
  end

  defp schema_shortcut_key(Sheet), do: :sheet
  defp schema_shortcut_key(Flow), do: :flow
  defp schema_shortcut_key(Scene), do: :scene
  defp schema_shortcut_key(Screenplay), do: :screenplay

  defp overwrite_existing(shortcut, project_id, schema) do
    now = Storyarn.Shared.TimeHelpers.now()

    from(e in schema,
      where: e.project_id == ^project_id and e.shortcut == ^shortcut and is_nil(e.deleted_at)
    )
    |> Repo.update_all(set: [deleted_at: now])

    shortcut
  end

  defp maybe_put_change(changeset, _field, nil), do: changeset

  defp maybe_put_change(changeset, field, value) do
    Ecto.Changeset.put_change(changeset, field, value)
  end

  defp insert_or_rollback!(changeset, context, opts \\ []) do
    case Repo.insert(changeset, opts) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({:import_failed, context, changeset})
    end
  end

  defp regenerate_asset_key(filename) do
    uuid = Ecto.UUID.generate()
    sanitized = String.replace(filename || "unknown", ~r/[^\w\-.]/, "_")
    "imports/#{uuid}/#{sanitized}"
  end

  defp link_parent_ids(records, id_map, type) do
    for {entity, data} <- records,
        parent_old_id = data["parent_id"],
        not is_nil(parent_old_id),
        new_parent_id = Map.get(id_map, {type, parent_old_id}),
        not is_nil(new_parent_id) do
      entity |> Ecto.Changeset.change(%{parent_id: new_parent_id}) |> Repo.update!()
    end
  end

  defp maybe_remap_ref(changes, field, id_map, type, nil) when is_map(changes) do
    _ = {field, id_map, type}
    changes
  end

  defp maybe_remap_ref(changes, field, id_map, type, old_id) do
    case Map.get(id_map, {type, old_id}) do
      nil -> changes
      new_id -> Map.put(changes, field, new_id)
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end

defmodule Storyarn.Imports.Parsers.StoryarnJSON do
  @moduledoc """
  Parses and imports Storyarn JSON format files.

  Handles:
  - JSON parsing and structure validation
  - Import preview with entity counts and conflict detection
  - Import execution with ID remapping and conflict resolution
  """

  @behaviour Storyarn.Imports.Parser

  import Ecto.Query, warn: false

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Parser
  alias Storyarn.Imports.SourceBundle
  alias Storyarn.Localization
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.RoutePoints
  alias Storyarn.Screenplays
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

  @required_top_keys ~w(storyarn_version export_version project)

  @impl Parser
  def format, do: :storyarn

  @impl Parser
  def parser_version, do: "1"

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
         :ok <- validate_structure(data),
         :ok <- validate_types(data),
         :ok <- validate_runtime_identifiers(data) do
      {:ok, data}
    end
  end

  @impl Parser
  def parse(%SourceBundle{kind: kind, files: [%{content: binary}]}) do
    with {:ok, data} <- parse(binary) do
      {:ok,
       %ImportPlan{
         format: format(),
         parser_version: parser_version(),
         source_kind: kind,
         data: data
       }}
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

  @array_keys ~w(sheets flows scenes screenplays)

  defp validate_types(data) do
    bad =
      Enum.filter(@array_keys, fn k -> (v = data[k]) != nil and not is_list(v) end)

    loc = data["localization"]

    bad_loc =
      cond do
        is_nil(loc) ->
          []

        not is_map(loc) ->
          ["localization"]

        true ->
          ~w(languages strings glossary)
          |> Enum.filter(fn k -> (v = loc[k]) != nil and not is_list(v) end)
          |> Enum.map(&"localization.#{&1}")
      end

    bad_nested =
      invalid_entity_entries(data) ++
        invalid_flow_entries(data) ++
        invalid_localization_entries(data)

    case bad ++ bad_loc ++ bad_nested do
      [] -> :ok
      fields -> {:error, {:invalid_field_types, Enum.uniq(fields)}}
    end
  end

  defp invalid_entity_entries(data) do
    Enum.flat_map(@array_keys, fn key ->
      case data[key] do
        entries when is_list(entries) ->
          entries
          |> Enum.with_index()
          |> Enum.flat_map(fn
            {entry, _index} when is_map(entry) -> []
            {_entry, index} -> ["#{key}[#{index}]"]
          end)

        _other ->
          []
      end
    end)
  end

  defp invalid_flow_entries(data) do
    case data["flows"] do
      flows when is_list(flows) ->
        flows
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {flow, flow_index} when is_map(flow) -> invalid_flow_nodes(flow, flow_index)
          {_flow, _flow_index} -> []
        end)

      _other ->
        []
    end
  end

  defp invalid_flow_nodes(flow, flow_index) do
    case flow["nodes"] do
      nil ->
        []

      nodes when is_list(nodes) ->
        nodes
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {node, node_index} when is_map(node) -> invalid_flow_node_data(node, flow_index, node_index)
          {_node, node_index} -> ["flows[#{flow_index}].nodes[#{node_index}]"]
        end)

      _other ->
        ["flows[#{flow_index}].nodes"]
    end
  end

  defp invalid_flow_node_data(%{"type" => "dialogue", "data" => data}, _flow_index, _node_index) when is_map(data), do: []

  defp invalid_flow_node_data(%{"type" => "dialogue"}, flow_index, node_index),
    do: ["flows[#{flow_index}].nodes[#{node_index}].data"]

  defp invalid_flow_node_data(_node, _flow_index, _node_index), do: []

  defp invalid_localization_entries(data) do
    case data["localization"] do
      localization when is_map(localization) ->
        Enum.flat_map(~w(languages strings glossary), &invalid_localization_collection(localization, &1))

      _other ->
        []
    end
  end

  defp invalid_localization_collection(localization, key) do
    case localization[key] do
      entries when is_list(entries) ->
        entries
        |> Enum.with_index()
        |> Enum.flat_map(&invalid_localization_entry(&1, key))

      _other ->
        []
    end
  end

  defp invalid_localization_entry({entry, index}, key) when is_map(entry) do
    translations = entry["translations"]

    cond do
      key not in ["strings", "glossary"] or is_nil(translations) ->
        []

      not is_map(translations) ->
        ["localization.#{key}[#{index}].translations"]

      true ->
        invalid_translation_values(translations, key, index)
    end
  end

  defp invalid_localization_entry({_entry, index}, key), do: ["localization.#{key}[#{index}]"]

  defp invalid_translation_values(translations, "strings", index) do
    Enum.flat_map(translations, fn
      {_locale, translation} when is_map(translation) -> []
      {locale, _translation} -> ["localization.strings[#{index}].translations.#{locale}"]
    end)
  end

  defp invalid_translation_values(translations, "glossary", index) do
    Enum.flat_map(translations, fn
      {_locale, target_term} when is_binary(target_term) -> []
      {locale, _target_term} -> ["localization.glossary[#{index}].translations.#{locale}"]
    end)
  end

  defp validate_runtime_identifiers(data) do
    with :ok <- validate_locale_codes(data) do
      validate_dialogue_ids(data)
    end
  end

  defp validate_locale_codes(data) do
    localization = data["localization"] || %{}

    locale_codes =
      [localization["source_language"]] ++
        Enum.map(localization["languages"] || [], & &1["locale_code"]) ++
        Enum.flat_map(localization["strings"] || [], &Map.keys(&1["translations"] || %{})) ++
        Enum.flat_map(localization["glossary"] || [], fn entry ->
          [entry["source_locale"] | Map.keys(entry["translations"] || %{})]
        end)

    invalid = locale_codes |> Enum.reject(&(is_nil(&1) or LocaleCode.valid?(&1))) |> Enum.uniq() |> Enum.sort()

    if invalid == [], do: :ok, else: {:error, {:invalid_locale_codes, invalid}}
  end

  defp validate_dialogue_ids(data) do
    dialogue_nodes =
      data
      |> Map.get("flows")
      |> Kernel.||([])
      |> Enum.flat_map(fn flow -> Map.get(flow, "nodes") || [] end)
      |> Enum.filter(&(&1["type"] == "dialogue"))

    invalid = Enum.flat_map(dialogue_nodes, &dialogue_id_errors/1) ++ duplicate_dialogue_id_errors(dialogue_nodes)

    if invalid == [], do: :ok, else: {:error, {:invalid_dialogue_ids, invalid}}
  end

  defp duplicate_dialogue_id_errors(nodes) do
    nodes
    |> Enum.map(&get_in(&1, ["data", "localization_id"]))
    |> Enum.filter(&RuntimeKey.valid_dialogue_id?/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.map(fn {id, _count} -> %{field: "localization_id", value: id, reason: "duplicate"} end)
  end

  defp dialogue_id_errors(node) do
    data = node["data"] || %{}
    responses = data["responses"] || []

    errors =
      if RuntimeKey.valid_dialogue_id?(data["localization_id"]),
        do: [],
        else: [%{node_id: node["id"], field: "localization_id"}]

    if is_list(responses) do
      response_ids =
        Enum.map(responses, fn
          response when is_map(response) -> response["id"]
          _response -> nil
        end)

      cond do
        not Enum.all?(response_ids, &RuntimeKey.valid_response_id?/1) ->
          [%{node_id: node["id"], field: "response.id"} | errors]

        length(response_ids) != length(Enum.uniq(response_ids)) ->
          [%{node_id: node["id"], field: "response.id", reason: "duplicate"} | errors]

        true ->
          errors
      end
    else
      [%{node_id: node["id"], field: "responses"} | errors]
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
    with :ok <- validate_structure(data),
         :ok <- validate_types(data),
         :ok <- validate_runtime_identifiers(data) do
      counts = count_import_entities(data)
      conflicts = detect_conflicts(project_id, data)

      {:ok,
       %{
         counts: counts,
         conflicts: conflicts,
         has_conflicts: conflicts != %{}
       }}
    end
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

    conflicts = detect_shortcut_conflicts(conflicts, project_id, :sheet, data["sheets"] || [])
    conflicts = detect_shortcut_conflicts(conflicts, project_id, :flow, data["flows"] || [])
    conflicts = detect_shortcut_conflicts(conflicts, project_id, :scene, data["scenes"] || [])
    detect_shortcut_conflicts(conflicts, project_id, :screenplay, data["screenplays"] || [])
  end

  defp detect_shortcut_conflicts(conflicts, project_id, entity_type, entities) do
    shortcuts =
      entities
      |> Enum.map(& &1["shortcut"])
      |> Enum.reject(&is_nil/1)

    if shortcuts == [] do
      conflicts
    else
      existing = detect_conflicts_for_type(entity_type, project_id, shortcuts)

      if existing == [] do
        conflicts
      else
        Map.put(conflicts, entity_type, existing)
      end
    end
  end

  defp detect_conflicts_for_type(:sheet, project_id, shortcuts),
    do: Sheets.detect_sheet_shortcut_conflicts(project_id, shortcuts)

  defp detect_conflicts_for_type(:flow, project_id, shortcuts),
    do: Flows.detect_flow_shortcut_conflicts(project_id, shortcuts)

  defp detect_conflicts_for_type(:scene, project_id, shortcuts),
    do: Scenes.detect_scene_shortcut_conflicts(project_id, shortcuts)

  defp detect_conflicts_for_type(:screenplay, project_id, shortcuts),
    do: Screenplays.detect_screenplay_shortcut_conflicts(project_id, shortcuts)

  # =============================================================================
  # Execute
  # =============================================================================

  @doc """
  Execute the import into a project.

  Options:
  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:skip`)

  Uses a database transaction. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(project, plan, opts \\ [])

  def execute(project, %ImportPlan{} = plan, opts) do
    result =
      Repo.transact(
        fn -> materialize_in_transaction(project, plan, opts) end,
        timeout: to_timeout(minute: 5)
      )

    case result do
      {:ok, _result} -> Collaboration.broadcast_dashboard_change(project.id, :all)
      _error -> :ok
    end

    result
  end

  def execute(_project, data, _opts) when is_map(data), do: {:error, :import_plan_required}

  @doc false
  def materialize_in_transaction(project, plan, opts \\ [])

  def materialize_in_transaction(project, %ImportPlan{data: data} = plan, opts) do
    cond do
      not Repo.in_transaction?() -> {:error, :import_transaction_required}
      ImportPlan.error?(plan) -> {:error, :import_plan_has_errors}
      true -> do_materialize_in_transaction(project, data, opts)
    end
  end

  def materialize_in_transaction(_project, data, _opts) when is_map(data), do: {:error, :import_plan_required}

  defp do_materialize_in_transaction(project, data, opts) do
    strategy = Keyword.get(opts, :conflict_strategy, :skip)

    with :ok <- validate_structure(data),
         :ok <- validate_types(data),
         :ok <- validate_runtime_identifiers(data),
         :ok <- validate_entity_counts(data) do
      existing_shortcuts = preload_existing_shortcuts(project.id)
      id_map = %{}
      {id_map, asset_results} = import_assets(project.id, data, id_map)

      {id_map, sheet_results} =
        import_sheets(project, data, id_map, strategy, existing_shortcuts)

      {id_map, scene_results} =
        import_scenes(project, data, id_map, strategy, existing_shortcuts)

      {id_map, flow_results, node_count} =
        import_flows(project, data, id_map, strategy, existing_shortcuts)

      # Pass 3: link scene→flow references now that flows exist in id_map
      link_scene_flow_references(data, id_map)

      # Pass 4: link node→flow references (referenced_flow_id, target_id)
      # now that all flows exist in id_map
      link_node_flow_references(data, id_map)

      {id_map, screenplay_results} =
        import_screenplays(project, data, id_map, strategy, existing_shortcuts)

      {_id_map, loc_results} = import_localization(project.id, data, id_map)

      counts = %{
        assets: length(asset_results),
        sheets: length(sheet_results),
        flows: length(flow_results),
        nodes: node_count,
        scenes: length(scene_results),
        screenplays: length(screenplay_results)
      }

      {:ok,
       %{
         assets: asset_results,
         sheets: sheet_results,
         flows: flow_results,
         scenes: scene_results,
         screenplays: screenplay_results,
         localization: loc_results,
         counts: counts
       }}
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
    Enum.reduce(entries, 0, fn
      entry, acc when is_map(entry) ->
        case entry["translations"] do
          t when is_map(t) -> acc + map_size(t)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  # =============================================================================
  # Shortcut pre-loading
  # =============================================================================

  defp preload_existing_shortcuts(project_id) do
    %{
      sheet: Sheets.list_sheet_shortcuts(project_id),
      flow: Flows.list_flow_shortcuts(project_id),
      scene: Scenes.list_scene_shortcuts(project_id),
      screenplay: Screenplays.list_screenplay_shortcuts(project_id)
    }
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

      asset =
        facade_insert_or_rollback!(
          Assets.import_asset(project_id, attrs),
          {:asset, item["filename"]}
        )

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
               :sheet,
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
              "banner_asset_id" => remap_id(map, :asset, sheet_data["banner_asset_id"]),
              "hidden_inherited_block_ids" => []
            }

            sheet =
              facade_insert_or_rollback!(
                Sheets.import_sheet(project.id, attrs),
                {:sheet, sheet_data["name"]}
              )

            import_sheet_avatars(sheet, sheet_data, map)
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

      block =
        facade_insert_or_rollback!(
          Sheets.import_block(sheet_id, attrs),
          {:block, block_data["type"]}
        )

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

      col =
        facade_insert_or_rollback!(
          Sheets.import_table_column(block_id, attrs),
          {:table_column, col_data["name"]}
        )

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

      row =
        facade_insert_or_rollback!(
          Sheets.import_table_row(block_id, attrs),
          {:table_row, row_data["name"]}
        )

      {Map.put(map, {:table_row, row_data["id"]}, row.id), [row | results]}
    end)
  end

  # =============================================================================
  # Flows import (two-pass for parent_id)
  # =============================================================================

  defp import_flows(project, data, id_map, strategy, existing_shortcuts) do
    flows = data["flows"] || []

    if flows == [],
      do: {id_map, [], 0},
      else: do_import_flows(project, flows, id_map, strategy, existing_shortcuts)
  end

  defp do_import_flows(project, flows, id_map, strategy, existing_shortcuts) do
    # Pass 1: create flows without parent_id
    {id_map, flow_records, node_count} =
      Enum.reduce(flows, {id_map, [], 0}, fn flow_data, {map, records, node_count} ->
        case resolve_shortcut(
               flow_data["shortcut"],
               strategy,
               project.id,
               :flow,
               existing_shortcuts
             ) do
          :skip ->
            {map, records, node_count}

          shortcut ->
            {map, flow, imported_node_count} = create_flow_record(project, flow_data, shortcut, map)
            {map, [{flow, flow_data} | records], node_count + imported_node_count}
        end
      end)

    # Pass 2: set parent_id
    link_parent_ids(flow_records, id_map, :flow)

    {id_map, Enum.map(flow_records, fn {flow, _} -> flow end), node_count}
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

    flow =
      facade_insert_or_rollback!(Flows.import_flow(project.id, attrs), {:flow, flow_data["name"]})

    map = Map.put(map, {:flow, flow_data["id"]}, flow.id)
    {map, node_results} = import_nodes(project.id, flow.id, flow_data["nodes"] || [], map)
    {map, _} = import_flow_connections(flow.id, flow_data["connections"] || [], map)

    {map, flow, length(node_results)}
  end

  defp import_nodes(project_id, flow_id, nodes, id_map) do
    existing_dialogue_ids = load_dialogue_localization_ids(project_id)

    {id_map, results, _dialogue_ids} =
      Enum.reduce(nodes, {id_map, [], existing_dialogue_ids}, fn node_data, {map, results, dialogue_ids} ->
        {data, dialogue_ids} =
          node_data["data"]
          |> remap_node_data(map)
          |> rekey_conflicting_import_dialogue(node_data["type"], dialogue_ids)

        attrs = %{
          "type" => node_data["type"],
          "position_x" => node_data["position_x"] || 0.0,
          "position_y" => node_data["position_y"] || 0.0,
          "source" => node_data["source"],
          "data" => data
        }

        node =
          facade_insert_or_rollback!(Flows.import_node(flow_id, attrs), {:node, node_data["type"]})

        {Map.put(map, {:node, node_data["id"]}, node.id), [node | results], dialogue_ids}
      end)

    {id_map, results}
  end

  defp rekey_conflicting_import_dialogue(%{"localization_id" => localization_id} = data, "dialogue", used_ids)
       when is_binary(localization_id) and localization_id != "" do
    localization_id =
      if MapSet.member?(used_ids, localization_id),
        do: unique_dialogue_localization_id(used_ids),
        else: localization_id

    {Map.put(data, "localization_id", localization_id), MapSet.put(used_ids, localization_id)}
  end

  defp rekey_conflicting_import_dialogue(data, _type, used_ids), do: {data, used_ids}

  defp load_dialogue_localization_ids(project_id) do
    from(node in FlowNode,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      where: flow.project_id == ^project_id and node.type == "dialogue",
      select: fragment("?->>'localization_id'", node.data)
    )
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp unique_dialogue_localization_id(used_ids) do
    candidate = "dialogue_#{Ecto.UUID.generate()}"

    if MapSet.member?(used_ids, candidate),
      do: unique_dialogue_localization_id(used_ids),
      else: candidate
  end

  # Remap DB IDs inside node data and clean serializer-added fields.
  # Sheet/asset/scene IDs are remapped immediately (already in id_map).
  # Flow IDs (referenced_flow_id, target_id for flow targets) are deferred
  # to link_node_flow_references/2 since other flows may not exist yet.
  defp remap_node_data(nil, _map), do: %{}

  defp remap_node_data(data, map) do
    data
    |> remap_data_field(map, "speaker_sheet_id", :sheet)
    |> remap_data_field(map, "location_sheet_id", :sheet)
    |> remap_data_field(map, "avatar_id", :asset)
    |> remap_data_field(map, "audio_asset_id", :asset)
    |> clean_responses()
  end

  defp remap_data_field(data, _map, _field, _type) when not is_map(data), do: data

  defp remap_data_field(data, map, field, type) do
    case data[field] do
      nil -> data
      "" -> data
      old_id -> Map.put(data, field, remap_id(map, type, old_id))
    end
  end

  defp clean_responses(%{"responses" => responses} = data) when is_list(responses) do
    cleaned =
      Enum.map(responses, fn resp ->
        Map.delete(resp, "instruction_assignments")
      end)

    Map.put(data, "responses", cleaned)
  end

  defp clean_responses(data), do: data

  defp import_flow_connections(flow_id, connections, id_map) do
    now = TimeHelpers.now()

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

    results = Flows.bulk_import_connections(Enum.reverse(valid_attrs))

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
               :scene,
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
      "scale_value" => scene_data["scale_value"],
      "fog_color" => scene_data["fog_color"] || "#000000",
      "fog_opacity" => scene_data["fog_opacity"] || 0.85
    }

    scene =
      facade_insert_or_rollback!(
        Scenes.import_scene(project.id, attrs),
        {:scene, scene_data["name"]}
      )

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
        "fog_enabled" => layer_data["fog_enabled"] || false
      }

      layer =
        facade_insert_or_rollback!(
          Scenes.import_layer(scene_id, attrs),
          {:layer, layer_data["name"]}
        )

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
        "shortcut" => pin_data["shortcut"],
        "hidden" => pin_data["hidden"] || false,
        "flow_id" => resolve_pin_flow_id(pin_data, map),
        "tooltip" => pin_data["tooltip"],
        "size" => pin_data["size"],
        "position" => pin_data["position"] || 0,
        "locked" => pin_data["locked"] || false,
        "icon_asset_id" => remap_id(map, :asset, pin_data["icon_asset_id"]),
        "sheet_id" => remap_id(map, :sheet, pin_data["sheet_id"]),
        "condition" => pin_data["condition"],
        "condition_effect" => pin_data["condition_effect"],
        "is_playable" => pin_data["is_playable"] || false,
        "is_leader" => pin_data["is_leader"] || false
      }

      pin =
        facade_insert_or_rollback!(Scenes.import_pin(scene_id, attrs), {:pin, pin_data["label"]})

      {Map.put(map, {:pin, pin_data["id"]}, pin.id), [pin | results]}
    end)
  end

  defp import_zones(scene_id, zones, id_map) do
    Enum.reduce(zones, {id_map, []}, fn zone_data, {map, results} ->
      attrs = import_zone_attrs(zone_data, map)

      zone =
        facade_insert_or_rollback!(
          Scenes.import_zone(scene_id, attrs),
          {:zone, zone_data["name"]}
        )

      {Map.put(map, {:zone, zone_data["id"]}, zone.id), [zone | results]}
    end)
  end

  defp import_zone_attrs(zone_data, map) do
    zone_data
    |> zone_base_import_attrs(map)
    |> Map.merge(zone_visual_import_attrs(zone_data, map))
    |> Map.merge(zone_behavior_import_attrs(zone_data, map))
  end

  defp zone_base_import_attrs(zone_data, map) do
    %{
      "name" => zone_data["name"],
      "shortcut" => zone_data["shortcut"],
      "hidden" => zone_data["hidden"] || false,
      "layer_id" => remap_id(map, :layer, zone_data["layer_id"]),
      "vertices" => zone_data["vertices"] || [],
      "fill_color" => zone_data["fill_color"],
      "border_color" => zone_data["border_color"],
      "border_width" => zone_data["border_width"],
      "border_style" => zone_data["border_style"],
      "opacity" => zone_data["opacity"],
      "tooltip" => zone_data["tooltip"],
      "position" => zone_data["position"] || 0,
      "locked" => zone_data["locked"] || false
    }
  end

  defp zone_visual_import_attrs(zone_data, map) do
    %{
      "label_mode" => zone_data["label_mode"] || "text",
      "label_font_size" => zone_data["label_font_size"] || 12,
      "label_font_family" => zone_data["label_font_family"] || "system",
      "label_font_weight" => zone_data["label_font_weight"] || "600",
      "label_font_style" => zone_data["label_font_style"] || "normal",
      "label_icon_asset_id" => remap_id(map, :asset, zone_data["label_icon_asset_id"])
    }
  end

  defp zone_behavior_import_attrs(zone_data, map) do
    action_type = zone_data["action_type"] || "action"

    Map.merge(
      %{
        "action_type" => action_type,
        "action_data" => zone_data["action_data"] || default_zone_action_data(action_type),
        "condition" => zone_data["condition"],
        "condition_effect" => zone_data["condition_effect"],
        "is_walkable" => zone_data["is_walkable"] || false
      },
      zone_target_import_attrs(zone_data, map, action_type)
    )
  end

  defp zone_target_import_attrs(zone_data, map, action_type) when action_type in [nil, "action"] do
    case zone_data["target_type"] do
      "flow" ->
        %{"target_type" => nil, "target_id" => nil}

      target_type ->
        %{
          "target_type" => target_type,
          "target_id" => remap_target_id(map, target_type, zone_data["target_id"])
        }
    end
  end

  defp zone_target_import_attrs(_zone_data, _map, _action_type) do
    %{"target_type" => nil, "target_id" => nil}
  end

  defp default_zone_action_data("action"), do: %{"assignments" => []}
  defp default_zone_action_data("display"), do: %{"variable_ref" => "", "display_mode" => "value"}
  defp default_zone_action_data("collection"), do: %{"items" => []}
  defp default_zone_action_data(_action_type), do: %{}

  defp import_scene_connections(scene_id, connections, id_map) do
    now = TimeHelpers.now()

    # Build valid connection attrs, filtering out those with missing pin references
    valid_attrs =
      Enum.reduce(connections, [], fn conn_data, acc ->
        from_pin_id = remap_optional_pin_id(id_map, conn_data["from_pin_id"])
        to_pin_id = remap_optional_pin_id(id_map, conn_data["to_pin_id"])
        waypoints = conn_data["waypoints"] || []

        if RoutePoints.enough_points?(from_pin_id, to_pin_id, waypoints) do
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
            waypoints: waypoints,
            from_stop: Map.get(conn_data, "from_stop", true),
            to_stop: Map.get(conn_data, "to_stop", true),
            from_pause_ms: conn_data["from_pause_ms"],
            to_pause_ms: conn_data["to_pause_ms"],
            inserted_at: now,
            updated_at: now
          }

          [attrs | acc]
        else
          acc
        end
      end)

    results = Scenes.bulk_import_scene_connections(Enum.reverse(valid_attrs))

    {id_map, results}
  end

  defp remap_optional_pin_id(_id_map, nil), do: nil
  defp remap_optional_pin_id(_id_map, ""), do: nil
  defp remap_optional_pin_id(id_map, pin_id), do: Map.get(id_map, {:pin, pin_id})

  defp import_annotations(scene_id, annotations, id_map) do
    now = TimeHelpers.now()

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

    results = Scenes.bulk_import_scene_annotations(Enum.reverse(valid_attrs))

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
               :screenplay,
               existing_shortcuts
             ) do
          :skip ->
            {map, records}

          shortcut ->
            {map, sp} = create_screenplay_record(project, sp_data, shortcut, map)
            {map, [{sp, sp_data} | records]}
        end
      end)

    # Pass 2: parent_id
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

    extra_changes = maybe_put_extra(%{}, :linked_flow_id, remap_id(map, :flow, sp_data["linked_flow_id"]))

    sp =
      facade_insert_or_rollback!(
        Screenplays.import_screenplay(project.id, attrs, extra_changes),
        {:screenplay, sp_data["name"]}
      )

    map = Map.put(map, {:screenplay, sp_data["id"]}, sp.id)
    {map, _} = import_elements(sp.id, sp_data["elements"] || [], map)

    {map, sp}
  end

  defp link_screenplay_refs(sp_records, id_map) do
    for {sp, sp_data} <- sp_records do
      changes = maybe_remap_ref(%{}, :parent_id, id_map, :screenplay, sp_data["parent_id"])

      if changes != %{} do
        Screenplays.link_screenplay_import_refs(sp, changes)
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

      extra_changes =
        maybe_put_extra(%{}, :linked_node_id, remap_id(map, :node, el_data["linked_node_id"]))

      el =
        facade_insert_or_rollback!(
          Screenplays.import_element(screenplay_id, attrs, extra_changes),
          {:element, el_data["type"]}
        )

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
        "position" => lang_data["position"] || 0,
        "archived_at" => parse_datetime(lang_data["archived_at"])
      }

      lang =
        facade_insert_or_rollback!(
          Localization.import_language(project_id, attrs),
          {:language, lang_data["locale_code"]}
        )

      {Map.put(map, {:language, lang_data["locale_code"]}, lang.id), [lang | results]}
    end)
  end

  defp import_localized_texts(project_id, strings, id_map) do
    now = TimeHelpers.now()
    runtime_sources = load_runtime_localization_sources(strings, id_map)

    # Build all text attrs from the nested strings/translations structure
    valid_attrs =
      Enum.reduce(strings, [], fn entry, acc ->
        translations = entry["translations"] || %{}
        source_type = entry["source_type"]
        source_field = entry["source_field"]
        remapped_source_id = remap_source_id(id_map, source_type, entry["source_id"])
        # Skip texts whose source entity was not imported (avoid cross-project ID links)
        source_id = remapped_source_id

        if is_nil(source_id) or
             not SourceContract.field?(source_type, source_field) do
          acc
        else
          source_runtime? = runtime_localization_source?(runtime_sources, source_type, source_id, source_field)
          build_translation_attrs(acc, entry, translations, project_id, source_id, id_map, now, source_runtime?)
        end
      end)

    Localization.bulk_import_texts(Enum.reverse(valid_attrs))
  end

  defp build_translation_attrs(acc, entry, translations, project_id, source_id, id_map, now, source_runtime?) do
    metadata = SourceContract.field_metadata(entry["source_type"], entry["source_field"])

    Enum.reduce(translations, acc, fn {locale_code, translation}, inner_acc ->
      translated_source_hash = imported_translation_hash(translation, entry["source_text_hash"])
      vo_asset_id = if(metadata.vo_eligible, do: remap_id(id_map, :asset, translation["vo_asset_id"]))

      attrs = %{
        project_id: project_id,
        source_type: entry["source_type"],
        source_id: source_id,
        source_field: entry["source_field"],
        source_text: entry["source_text"],
        source_text_hash: entry["source_text_hash"],
        translated_source_hash: translated_source_hash,
        speaker_sheet_id:
          if(metadata.content_role == "dialogue",
            do: remap_id(id_map, :sheet, entry["speaker_sheet_id"])
          ),
        locale_code: locale_code,
        translated_text: translation["translated_text"],
        status: imported_status(translation, entry["source_text_hash"], translated_source_hash),
        vo_status: imported_vo_status(translation["vo_status"], metadata.vo_eligible, vo_asset_id),
        vo_asset_id: vo_asset_id,
        translator_notes: translation["translator_notes"],
        reviewer_notes: translation["reviewer_notes"],
        word_count: translation["word_count"],
        content_role: metadata.content_role,
        vo_eligible: metadata.vo_eligible,
        machine_translated: translation["machine_translated"] || false,
        last_translated_at: parse_datetime(translation["last_translated_at"]),
        last_reviewed_at: parse_datetime(translation["last_reviewed_at"]),
        archived_at: imported_archived_at(translation, source_runtime?, now),
        archive_reason: imported_archive_reason(translation, source_runtime?),
        translated_by_id: nil,
        reviewed_by_id: nil,
        inserted_at: now,
        updated_at: now
      }

      [attrs | inner_acc]
    end)
  end

  defp imported_translation_hash(%{"translated_source_hash" => hash}, _source_hash) when is_binary(hash), do: hash

  defp imported_translation_hash(translation, source_hash) do
    if is_binary(translation["translated_text"]) and
         String.trim(translation["translated_text"]) != "" do
      source_hash
    end
  end

  defp imported_status(%{"status" => "final"} = translation, source_hash, translated_hash) do
    if present_translation?(translation["translated_text"]) and not is_nil(source_hash) and
         translated_hash == source_hash do
      "final"
    else
      if(present_translation?(translation["translated_text"]), do: "review", else: "pending")
    end
  end

  defp imported_status(translation, _source_hash, _translated_hash) do
    case translation["status"] do
      status when status in ~w(pending draft in_progress review final) -> status
      _status -> if(present_translation?(translation["translated_text"]), do: "draft", else: "pending")
    end
  end

  defp imported_vo_status(_status, false, _asset_id), do: "none"
  defp imported_vo_status(status, true, nil) when status in ~w(recorded approved), do: "needed"
  defp imported_vo_status(status, true, _asset_id) when status in ~w(none needed recorded approved), do: status
  defp imported_vo_status(_status, true, _asset_id), do: "none"

  defp imported_archived_at(translation, true, _now), do: parse_datetime(translation["archived_at"])
  defp imported_archived_at(_translation, false, now), do: now

  defp imported_archive_reason(_translation, false), do: "source_not_runtime"

  defp imported_archive_reason(%{"archive_reason" => reason}, true)
       when reason in ["source_deleted", "source_field_removed", "source_not_runtime", "version_replaced"], do: reason

  defp imported_archive_reason(_translation, true), do: nil

  defp load_runtime_localization_sources(strings, id_map) do
    ids_by_type =
      Enum.reduce(strings, %{}, fn entry, acc ->
        source_type = entry["source_type"]
        source_id = remap_source_id(id_map, source_type, entry["source_id"])

        if source_type in SourceContract.source_types() and not is_nil(source_id) do
          Map.update(acc, source_type, MapSet.new([source_id]), &MapSet.put(&1, source_id))
        else
          acc
        end
      end)

    %{
      "flow_node" => load_sources(FlowNode, ids_by_type["flow_node"]),
      "block" => load_sources(Storyarn.Sheets.Block, ids_by_type["block"]),
      "sheet" => load_sources(Storyarn.Sheets.Sheet, ids_by_type["sheet"])
    }
  end

  defp load_sources(_schema, nil), do: %{}

  defp load_sources(schema, ids) do
    schema
    |> where([source], source.id in ^MapSet.to_list(ids))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp runtime_localization_source?(sources, source_type, source_id, source_field) do
    source = get_in(sources, [source_type, source_id])
    SourceContract.localizable_source_field?(source_type, source, source_field)
  end

  defp present_translation?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_translation?(_value), do: false

  defp import_glossary(project_id, glossary_entries) do
    now = TimeHelpers.now()

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

    Localization.bulk_import_glossary_entries(Enum.reverse(valid_attrs))
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  # Backwards compat: old exports have target_type/target_id, new ones have flow_id
  defp resolve_pin_flow_id(pin_data, id_map) do
    cond do
      pin_data["flow_id"] ->
        remap_id(id_map, :flow, pin_data["flow_id"])

      pin_data["target_type"] == "flow" && pin_data["target_id"] ->
        remap_id(id_map, :flow, pin_data["target_id"])

      true ->
        nil
    end
  end

  defp remap_id(_map, _type, nil), do: nil

  defp remap_id(map, type, old_id) do
    Map.get(map, {type, old_id}) || remap_equivalent_id(map, type, old_id)
  end

  defp remap_equivalent_id(map, type, old_id) when is_integer(old_id) do
    Map.get(map, {type, to_string(old_id)})
  end

  defp remap_equivalent_id(map, type, old_id) when is_binary(old_id) do
    case Integer.parse(old_id) do
      {int_id, ""} -> Map.get(map, {type, int_id})
      _ -> nil
    end
  end

  defp remap_equivalent_id(_map, _type, _old_id), do: nil

  defp remap_source_id(_map, _source_type, nil), do: nil
  defp remap_source_id(map, "flow_node", old_id), do: Map.get(map, {:node, old_id})
  defp remap_source_id(map, "block", old_id), do: Map.get(map, {:block, old_id})
  defp remap_source_id(map, "sheet", old_id), do: Map.get(map, {:sheet, old_id})
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

    if type, do: Map.get(map, {type, target_id})
  end

  defp resolve_shortcut(nil, _strategy, _project_id, _entity_type, _existing_shortcuts), do: nil

  defp resolve_shortcut(shortcut, strategy, project_id, entity_type, existing_shortcuts) do
    existing_set = Map.fetch!(existing_shortcuts, entity_type)
    exists? = MapSet.member?(existing_set, shortcut)

    cond do
      not exists? ->
        shortcut

      strategy == :skip ->
        :skip

      strategy == :overwrite ->
        overwrite_existing(shortcut, project_id, entity_type)

      strategy == :rename ->
        suffix = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
        "#{shortcut}-#{suffix}"

      true ->
        shortcut
    end
  end

  defp overwrite_existing(shortcut, project_id, :sheet) do
    Sheets.soft_delete_sheet_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp overwrite_existing(shortcut, project_id, :flow) do
    Flows.soft_delete_flow_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp overwrite_existing(shortcut, project_id, :scene) do
    Scenes.soft_delete_scene_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp overwrite_existing(shortcut, project_id, :screenplay) do
    Screenplays.soft_delete_screenplay_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp maybe_put_extra(map, _key, nil), do: map
  defp maybe_put_extra(map, key, value), do: Map.put(map, key, value)

  defp facade_insert_or_rollback!({:ok, record}, _context), do: record

  defp facade_insert_or_rollback!({:error, changeset}, context), do: Repo.rollback({:import_failed, context, changeset})

  defp regenerate_asset_key(filename) do
    uuid = Ecto.UUID.generate()
    sanitized = String.replace(filename || "unknown", ~r/[^\w\-.]/, "_")
    "imports/#{uuid}/#{sanitized}"
  end

  defp import_sheet_avatars(sheet, sheet_data, id_map) do
    case sheet_data["avatars"] do
      avatars when is_list(avatars) and avatars != [] ->
        Enum.each(avatars, &import_single_avatar(sheet, &1, id_map))

      _ ->
        # Fallback: legacy format with avatar_asset_id
        avatar_asset_id = remap_id(id_map, :asset, sheet_data["avatar_asset_id"])
        if avatar_asset_id, do: Sheets.add_avatar(sheet, avatar_asset_id)
    end
  end

  defp import_single_avatar(sheet, avatar_data, id_map) do
    asset_id = remap_id(id_map, :asset, avatar_data["asset_id"])

    if asset_id do
      Sheets.add_avatar(sheet, asset_id, %{
        name: avatar_data["name"],
        notes: avatar_data["notes"],
        is_default: avatar_data["is_default"] || false
      })
    end
  end

  defp link_parent_ids(records, id_map, entity_type) do
    for {entity, data} <- records,
        parent_old_id = data["parent_id"],
        not is_nil(parent_old_id),
        new_parent_id = Map.get(id_map, {entity_type, parent_old_id}),
        not is_nil(new_parent_id) do
      link_import_parent(entity_type, entity, new_parent_id)
    end
  end

  defp link_import_parent(:sheet, entity, parent_id), do: Sheets.link_sheet_import_parent(entity, parent_id)

  defp link_import_parent(:flow, entity, parent_id), do: Flows.link_flow_import_parent(entity, parent_id)

  defp link_import_parent(:scene, entity, parent_id), do: Scenes.link_scene_import_parent(entity, parent_id)

  # Scenes are imported before flows, so flow references in pins and zones
  # are nil at creation time. This pass links them after flows exist in the id_map.
  defp link_scene_flow_references(data, id_map) do
    for scene_data <- data["scenes"] || [] do
      # Link pin flow_ids
      for pin_data <- scene_data["pins"] || [],
          flow_id = resolve_pin_flow_id(pin_data, id_map),
          not is_nil(flow_id),
          pin_new_id = Map.get(id_map, {:pin, pin_data["id"]}),
          not is_nil(pin_new_id) do
        Scenes.link_pin_import_flow_id(pin_new_id, flow_id)
      end

      # Link zone target_ids that reference flows
      for zone_data <- scene_data["zones"] || [],
          zone_data["action_type"] in [nil, "action"],
          zone_data["target_type"] == "flow",
          target_id = remap_id(id_map, :flow, zone_data["target_id"]),
          not is_nil(target_id),
          zone_new_id = Map.get(id_map, {:zone, zone_data["id"]}),
          not is_nil(zone_new_id) do
        Scenes.link_zone_import_target(zone_new_id, "flow", target_id)
      end
    end
  end

  # Nodes are imported during flow creation, but flow-to-flow references
  # (subflow referenced_flow_id, exit referenced_flow_id, exit target_id for flow targets)
  # can't be resolved until all flows exist in the id_map. This pass links them.
  defp link_node_flow_references(data, id_map) do
    data
    |> exported_flow_nodes()
    |> Enum.each(&link_node_flow_reference(&1, id_map))
  end

  defp remap_node_flow_fields(data, id_map) do
    %{}
    |> maybe_put_remapped_node_ref("referenced_flow_id", data["referenced_flow_id"], :flow, id_map)
    |> maybe_put_remapped_node_target(data, id_map)
  end

  defp exported_flow_nodes(data) do
    data["flows"]
    |> List.wrap()
    |> Enum.flat_map(fn flow_data -> flow_data["nodes"] || [] end)
  end

  defp link_node_flow_reference(node_data, id_map) do
    node_data
    |> remapped_node_flow_fields(id_map)
    |> maybe_link_node_import_data(node_data, id_map)
  end

  defp remapped_node_flow_fields(node_data, id_map) do
    node_data
    |> Map.get("data", %{})
    |> remap_node_flow_fields(id_map)
  end

  defp maybe_link_node_import_data(remapped_fields, _node_data, _id_map) when remapped_fields == %{}, do: :ok

  defp maybe_link_node_import_data(remapped_fields, node_data, id_map) do
    case Map.get(id_map, {:node, node_data["id"]}) do
      nil -> :ok
      node_id -> link_existing_node_import_data(node_id, remapped_fields)
    end
  end

  defp link_existing_node_import_data(node_id, remapped_fields) do
    case Repo.get(FlowNode, node_id) do
      nil ->
        :ok

      existing_node ->
        updated_data = Map.merge(existing_node.data || %{}, remapped_fields)
        Flows.link_node_import_data(node_id, updated_data)
    end
  end

  defp maybe_put_remapped_node_target(result, %{"target_type" => "flow", "target_id" => old_id}, id_map) do
    maybe_put_remapped_node_ref(result, "target_id", old_id, :flow, id_map)
  end

  defp maybe_put_remapped_node_target(result, %{"target_type" => "scene", "target_id" => old_id}, id_map) do
    maybe_put_remapped_node_ref(result, "target_id", old_id, :scene, id_map)
  end

  defp maybe_put_remapped_node_target(result, _data, _id_map), do: result

  defp maybe_put_remapped_node_ref(result, _field, nil, _type, _id_map), do: result
  defp maybe_put_remapped_node_ref(result, _field, "", _type, _id_map), do: result

  defp maybe_put_remapped_node_ref(result, field, old_id, type, id_map) do
    case remap_id(id_map, type, old_id) do
      nil -> result
      new_id -> Map.put(result, field, new_id)
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

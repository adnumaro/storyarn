defmodule Storyarn.Projects.Imports.Materializer do
  @moduledoc """
  Writes an `%ImportPlan{}` into a project.

  This is the shared back half of every import, not one format's parser. Each
  parser normalizes its source into the plan shape — `yarn/normalizer.ex` builds
  the same `storyarn_version`/`export_version` envelope — and everything from
  there is common: plan validation, preview with entity counts and conflict
  detection, and execution with ID remapping and conflict resolution.

  It used to live in the native JSON format's parser module, which is why the
  removal of that format could not simply delete the file: the name described
  the parser half that has now gone, while every importer depended on this half.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.FlowImportPersistence
  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Parsers.Yarn.Expression
  alias Storyarn.Projects.Imports.Parsers.Yarn.Layout
  alias Storyarn.Projects.Imports.Parsers.Yarn.ReviewDecisions
  alias Storyarn.Projects.Imports.Parsers.Yarn.Shortcut
  alias Storyarn.Projects.Imports.Parsers.Yarn.SpeakerClassifier
  alias Storyarn.Projects.LocalizationLocaleCode, as: LocaleCode
  alias Storyarn.Projects.LocalizationReconstitution
  alias Storyarn.Projects.LocalizationRuntimeKey, as: RuntimeKey
  alias Storyarn.Projects.LocalizationSourceContract, as: SourceContract
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References
  alias Storyarn.Projects.SceneImportPersistence
  alias Storyarn.Projects.SceneReadModel
  alias Storyarn.Projects.SceneRoutePoints, as: RoutePoints
  alias Storyarn.Projects.SheetImportPersistence
  alias Storyarn.Repo

  @required_top_keys ~w(storyarn_version export_version project)

  @max_entity_counts %{
    sheets: 1_000,
    flows: 500,
    nodes_per_flow: 5_000,
    scenes: 200,
    assets: 5_000,
    languages: 50,
    localized_texts: 100_000,
    glossary_entries: 10_000
  }
  @transient_import_node_data_keys ~w(
    import_yarn_inherited_speaker
    import_yarn_speaker
    import_yarn_literal_text
    import_yarn_literal_source_text
    import_yarn_source_text
  )
  @transient_import_response_data_keys ~w(import_yarn_source_text)

  # =============================================================================
  # Plan validation
  # =============================================================================

  @doc """
  Validates an import plan's `data` map before anything is written.

  Every parser normalizes into this shape, so these checks belong to the plan,
  not to any one source format.
  """
  def validate_plan_data(data) when is_map(data) do
    with :ok <- validate_structure(data),
         :ok <- validate_types(data) do
      validate_runtime_identifiers(data)
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

  @array_keys ~w(sheets flows scenes)

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
        invalid_asset_entries(data) ++
        invalid_flow_entries(data) ++
        invalid_localization_entries(data)

    case bad ++ bad_loc ++ bad_nested do
      [] -> :ok
      fields -> {:error, {:invalid_field_types, Enum.uniq(fields)}}
    end
  end

  defp invalid_asset_entries(data) do
    case data["assets"] do
      nil ->
        []

      assets when not is_map(assets) ->
        ["assets"]

      assets ->
        invalid_asset_items(assets["items"])
    end
  end

  defp invalid_asset_items(nil), do: []
  defp invalid_asset_items(items) when not is_list(items), do: ["assets.items"]

  defp invalid_asset_items(items) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {item, index} when is_map(item) -> invalid_asset_item_fields(item, index)
      {_item, index} -> ["assets.items[#{index}]"]
    end)
  end

  defp invalid_asset_item_fields(item, index) do
    []
    |> maybe_invalid_asset_filename(item["filename"], index)
    |> maybe_invalid_asset_size(item["size"], index)
  end

  defp maybe_invalid_asset_filename(fields, filename, _index) when is_binary(filename) and filename != "", do: fields

  defp maybe_invalid_asset_filename(fields, _filename, index), do: ["assets.items[#{index}].filename" | fields]

  defp maybe_invalid_asset_size(fields, size, _index) when is_integer(size) and size > 0, do: fields
  defp maybe_invalid_asset_size(fields, _size, index), do: ["assets.items[#{index}].size" | fields]

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

  defp invalid_flow_node_data(%{"type" => "sequence"} = node, flow_index, node_index) do
    case node["sequence_config"] do
      %{"name" => name} when is_binary(name) ->
        if String.trim(name) == "",
          do: ["flows[#{flow_index}].nodes[#{node_index}].sequence_config"],
          else: []

      _other ->
        ["flows[#{flow_index}].nodes[#{node_index}].sequence_config"]
    end
  end

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
         :ok <- validate_runtime_identifiers(data),
         :ok <- validate_entity_counts(data) do
      counts = count_import_entities(data)
      conflicts = detect_conflicts(project_id, data)

      {:ok,
       %{
         counts: counts,
         conflicts: conflicts,
         has_conflicts: conflicts != %{},
         import_review:
           data
           |> Map.get("import_review", %{})
           |> ReviewDecisions.put_allowed_actions(),
         import_review_draft: Map.get(data, "import_review_draft"),
         import_review_resolution: Map.get(data, "import_review_resolution")
       }}
    end
  end

  defp count_import_entities(data) do
    %{
      sheets: length(data["sheets"] || []),
      flows: length(data["flows"] || []),
      nodes: (data["flows"] || []) |> Enum.flat_map(&(Map.get(&1, "nodes") || [])) |> length(),
      scenes: length(data["scenes"] || []),
      assets: length(get_in(data, ["assets", "items"]) || [])
    }
  end

  defp detect_conflicts(project_id, data) do
    conflicts = %{}

    conflicts = detect_shortcut_conflicts(conflicts, project_id, :sheet, data["sheets"] || [])
    conflicts = detect_shortcut_conflicts(conflicts, project_id, :flow, data["flows"] || [])
    detect_shortcut_conflicts(conflicts, project_id, :scene, data["scenes"] || [])
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
    do: SheetImportPersistence.detect_shortcut_conflicts(project_id, shortcuts)

  defp detect_conflicts_for_type(:flow, project_id, shortcuts),
    do: FlowImportPersistence.detect_shortcut_conflicts(project_id, shortcuts)

  defp detect_conflicts_for_type(:scene, project_id, shortcuts),
    do: SceneReadModel.detect_shortcut_conflicts(project_id, shortcuts)

  # =============================================================================
  # Execute
  # =============================================================================

  @doc """
  Execute the import into a project.

  Options:
  - `:conflict_strategy` — `:skip` | `:overwrite` | `:rename` (default: `:rename`,
    the same default the schema and the LiveView carry; three layers used to
    disagree here)

  Uses a database transaction. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def execute(project, plan, opts \\ [])

  def execute(project, %ImportPlan{} = plan, opts) do
    result =
      if ReviewDecisions.resolved?(plan) do
        project.workspace_id
        |> Billing.transact_with_workspace_lock(
          fn _workspace ->
            project
            |> materialize_in_transaction(plan, opts)
            |> normalize_transaction_result()
          end,
          timeout: to_timeout(minute: 5)
        )
        |> restore_transaction_result()
      else
        {:error, :invalid_import_review}
      end

    case result do
      {:ok, _result} -> Collaboration.broadcast_dashboard_change(project.id, :all)
      _error -> :ok
    end

    result
  end

  def execute(_project, data, _opts) when is_map(data), do: {:error, :import_plan_required}

  defp normalize_transaction_result({:error, reason, details}), do: {:error, {:detailed_import_error, reason, details}}

  defp normalize_transaction_result(result), do: result

  defp restore_transaction_result({:error, {:detailed_import_error, reason, details}}), do: {:error, reason, details}

  defp restore_transaction_result(result), do: result

  @doc false
  def materialize_in_transaction(project, plan, opts \\ [])

  def materialize_in_transaction(project, %ImportPlan{data: data} = plan, opts) do
    cond do
      not Repo.in_transaction?() -> {:error, :import_transaction_required}
      not Billing.workspace_lock_held?(project.workspace_id) -> {:error, :storage_accounting_lock_required}
      ImportPlan.error?(plan) -> {:error, :import_plan_has_errors}
      not ReviewDecisions.resolved?(plan) -> {:error, :invalid_import_review}
      true -> do_materialize_in_transaction(project, data, opts)
    end
  end

  def materialize_in_transaction(_project, data, _opts) when is_map(data), do: {:error, :import_plan_required}

  @doc false
  def materialize_locked_project_in_transaction(project, plan, opts \\ [])

  def materialize_locked_project_in_transaction(%Project{deleted_at: nil} = project, %ImportPlan{data: data} = plan, opts) do
    cond do
      not Repo.in_transaction?() -> {:error, :import_transaction_required}
      not Billing.workspace_lock_held?(project.workspace_id) -> {:error, :storage_accounting_lock_required}
      ImportPlan.error?(plan) -> {:error, :import_plan_has_errors}
      not ReviewDecisions.resolved?(plan) -> {:error, :invalid_import_review}
      true -> materialize_validated_project(project, data, opts)
    end
  end

  def materialize_locked_project_in_transaction(%Project{}, %ImportPlan{}, _opts), do: {:error, :project_not_active}

  def materialize_locked_project_in_transaction(_project, data, _opts) when is_map(data),
    do: {:error, :import_plan_required}

  defp do_materialize_in_transaction(project, data, opts) do
    with {:ok, project} <- lock_active_import_project(project),
         do: materialize_validated_project(project, data, opts)
  end

  defp materialize_validated_project(project, data, opts) do
    strategy = Keyword.get(opts, :conflict_strategy, :rename)

    with :ok <- validate_structure(data),
         :ok <- validate_types(data),
         :ok <- validate_runtime_identifiers(data),
         :ok <- validate_entity_counts(data) do
      Assets.with_import_capacity(project, imported_asset_bytes(data), fn ->
        materialize_capacity_authorized_project(project, data, strategy)
      end)
    end
  end

  defp materialize_capacity_authorized_project(project, data, strategy) do
    existing_shortcuts = preload_existing_shortcuts(project.id)
    id_map = %{}
    {id_map, asset_results} = import_assets(project, data, id_map)

    {id_map, sheet_results, sheet_shortcut_renames} =
      import_sheets(project, data, id_map, strategy, existing_shortcuts)

    {id_map, scene_results} =
      import_scenes(project, data, id_map, strategy, existing_shortcuts, sheet_shortcut_renames)

    {id_map, flow_results, node_count} =
      import_flows(project, data, id_map, strategy, existing_shortcuts, sheet_shortcut_renames)

    # Pass 3: link scene→flow references now that flows exist in id_map
    link_scene_flow_references(data, id_map)

    # Pass 4: link node→flow references (referenced_flow_id, target_id)
    # now that all flows exist in id_map
    link_node_flow_references(data, id_map)

    {_id_map, loc_results} = import_localization(project.id, data, id_map)

    rebuild_imported_references!(project.id)

    counts = %{
      assets: length(asset_results),
      sheets: length(sheet_results),
      flows: length(flow_results),
      nodes: node_count,
      scenes: length(scene_results)
    }

    {:ok,
     %{
       assets: asset_results,
       sheets: sheet_results,
       flows: flow_results,
       scenes: scene_results,
       localization: loc_results,
       counts: counts
     }}
  end

  defp rebuild_imported_references!(project_id) do
    with :ok <- References.rebuild_project_entity_references(project_id),
         :ok <- References.rebuild_project_variable_references(project_id) do
      :ok
    else
      {:error, reason} -> Repo.rollback({:import_reference_rebuild_failed, reason})
    end
  end

  defp lock_active_import_project(%Project{id: project_id}) when is_integer(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, :project_not_active}
      nil -> {:error, :project_not_found}
    end
  end

  defp lock_active_import_project(_project), do: {:error, :project_not_found}

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
      sheet: SheetImportPersistence.list_shortcuts(project_id),
      flow: FlowImportPersistence.list_shortcuts(project_id),
      scene: SceneReadModel.list_shortcuts(project_id)
    }
  end

  # =============================================================================
  # Assets import
  # =============================================================================

  defp imported_asset_bytes(data) do
    items = get_in(data, ["assets", "items"]) || []
    Enum.reduce(items, 0, fn item, total -> total + item["size"] end)
  end

  defp import_assets(project, data, id_map) do
    items = get_in(data, ["assets", "items"]) || []

    Enum.reduce(items, {id_map, []}, fn item, {map, results} ->
      attrs = %{
        "filename" => item["filename"],
        "content_type" => item["content_type"],
        "size" => item["size"],
        "key" => Assets.generate_key(project, item["filename"]),
        "url" => item["url"],
        "metadata" => item["metadata"] || %{}
      }

      asset =
        facade_insert_or_rollback!(
          Assets.import_asset(project, attrs),
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
      do: {id_map, [], %{}},
      else: do_import_sheets(project, sheets, id_map, strategy, existing_shortcuts)
  end

  defp do_import_sheets(project, sheets, id_map, strategy, existing_shortcuts) do
    used_shortcuts = Map.fetch!(existing_shortcuts, :sheet)

    # Pass 1: create all sheets without parent_id
    {id_map, sheet_records, shortcut_renames, _used_shortcuts} =
      Enum.reduce(sheets, {id_map, [], %{}, used_shortcuts}, fn sheet_data, {map, records, renames, used} ->
        case resolve_shortcut(
               sheet_data["shortcut"],
               strategy,
               project.id,
               :sheet,
               used
             ) do
          :skip ->
            {map, records, renames, used}

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
                SheetImportPersistence.import_sheet(project.id, attrs),
                {:sheet, sheet_data["name"]}
              )

            import_sheet_avatars(sheet, sheet_data, map)
            map = Map.put(map, {:sheet, sheet_data["id"]}, sheet.id)

            # Import blocks
            {map, _} = import_blocks(sheet.id, sheet_data["blocks"] || [], map)

            renames = record_shortcut_rename(renames, sheet_data["shortcut"], shortcut)
            {map, [{sheet, sheet_data} | records], renames, reserve_shortcut(used, shortcut)}
        end
      end)

    # Pass 2: set parent_id references
    link_parent_ids(sheet_records, id_map, :sheet)

    {id_map, Enum.map(sheet_records, fn {sheet, _} -> sheet end), shortcut_renames}
  end

  defp record_shortcut_rename(renames, imported, resolved)
       when is_binary(imported) and is_binary(resolved) and imported != resolved, do: Map.put(renames, imported, resolved)

  defp record_shortcut_rename(renames, _imported, _resolved), do: renames

  # Imported node data references variables through semantic fields: structured
  # `sheet`/`value_sheet`/`variable_ref` keys, encoded response conditions, and
  # the interpolation syntax understood by dialogue/response rendering. Rewrite
  # only those sites. A recursive rewrite of every string corrupts authored
  # prose and assignment literals that merely happen to contain `$yarn.gold`.
  defp rewrite_imported_refs(node_data, "annotation", _renames), do: node_data

  defp rewrite_imported_refs(node_data, "dialogue", renames) do
    node_data
    |> rewrite_variable_shortcuts(renames)
    |> rewrite_dialogue_interpolations(renames)
  end

  defp rewrite_imported_refs(node_data, _type, renames), do: rewrite_variable_shortcuts(node_data, renames)

  defp rewrite_variable_shortcuts(node_data, renames) when renames == %{} or not is_map(node_data), do: node_data

  defp rewrite_variable_shortcuts(node_data, renames), do: deep_rewrite_refs(node_data, renames)

  defp deep_rewrite_refs(%{} = map, renames) do
    Map.new(map, fn
      {key, value} when key in ["sheet", "value_sheet"] and is_binary(value) ->
        {key, Map.get(renames, value, value)}

      # Response conditions are persisted as a JSON-encoded string, so the
      # embedded-reference pass cannot see their "sheet" fields; decode,
      # rewrite structurally, re-encode. Anything that is not the JSON shape
      # is ordinary text and takes the embedded pass.
      {"condition" = key, value} when is_binary(value) ->
        {key, rewrite_encoded_condition(value, renames)}

      # Display zones reference a variable as a bare "shortcut.name" string,
      # with no sigil for the embedded pass to key on.
      {"variable_ref" = key, value} when is_binary(value) ->
        {key, rewrite_bare_variable_ref(value, renames)}

      {key, value} ->
        {key, deep_rewrite_refs(value, renames)}
    end)
  end

  defp deep_rewrite_refs(list, renames) when is_list(list), do: Enum.map(list, &deep_rewrite_refs(&1, renames))

  defp deep_rewrite_refs(value, _renames), do: value

  defp rewrite_encoded_condition(value, renames) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) ->
        decoded |> deep_rewrite_refs(renames) |> Jason.encode!()

      _not_structured ->
        value
    end
  end

  defp rewrite_dialogue_interpolations(data, renames) when renames == %{} or not is_map(data), do: data

  defp rewrite_dialogue_interpolations(data, renames) do
    data
    |> rewrite_dialogue_text(renames)
    |> Map.update("responses", [], fn
      responses when is_list(responses) ->
        Enum.map(responses, fn
          response when is_map(response) ->
            rewrite_response_interpolations(response, renames)

          response ->
            response
        end)

      responses ->
        responses
    end)
  end

  defp rewrite_dialogue_text(%{"import_yarn_source_text" => source_text} = data, renames) when is_binary(source_text) do
    shortcut = Map.get(renames, "yarn", "yarn")

    data
    |> dialogue_source_for_rendering(source_text)
    |> Expression.interpolate(:dialogue, shortcut)
    |> then(&Map.put(data, "text", &1))
  end

  # Backwards-compatible fallback for a stored plan created before Yarn source
  # text was retained. New plans always take the source-aware clause above.
  defp rewrite_dialogue_text(data, renames) do
    Map.update(data, "text", nil, &rewrite_semantic_interpolations(&1, renames, :dialogue))
  end

  # Explicit dialogue keeps its complete authored source so review decisions
  # can be revised without reparsing. A linked speaker renders only the body;
  # preserve-literal renders the complete line. Legacy revisions may carry a
  # separate literal source and are folded through the same path before their
  # metadata is removed on persistence.
  defp dialogue_source_for_rendering(data, source_text) do
    case Map.get(data, "import_yarn_speaker") do
      speaker when is_binary(speaker) ->
        full_source = legacy_literal_source(data) || source_text

        if is_nil(Map.get(data, "speaker_sheet_id")),
          do: full_source,
          else: explicit_dialogue_body(full_source, source_text, speaker)

      _ordinary_or_inherited ->
        source_text
    end
  end

  defp legacy_literal_source(%{"import_yarn_literal_source_text" => source_text}) when is_binary(source_text),
    do: source_text

  defp legacy_literal_source(_data), do: nil

  defp explicit_dialogue_body(full_source, fallback_source, speaker) do
    case SpeakerClassifier.split(full_source) do
      {^speaker, body} -> body
      _legacy_body_only -> fallback_source
    end
  end

  # A single alternation avoids rename chains (`yarn` -> `yarn-2` followed by
  # `yarn-2` -> `yarn-2-2`). Curly interpolation is semantic in dialogue text;
  # dollar interpolation is semantic in response labels. Other strings remain
  # byte-for-byte authored prose.
  defp rewrite_semantic_interpolations(value, renames, mode) when is_binary(value) do
    {prefix, suffix} = if(mode == :dialogue, do: {"{", "}"}, else: {"$", ""})

    alternation =
      renames
      |> Map.keys()
      |> Enum.sort_by(&byte_size/1, :desc)
      |> Enum.map_join("|", &Regex.escape/1)

    pattern =
      Regex.compile!(
        Regex.escape(prefix) <> "(" <> alternation <> ")\\.([A-Za-z_][A-Za-z0-9_.]*)" <> Regex.escape(suffix)
      )

    Regex.replace(pattern, value, fn _match, imported, variable ->
      prefix <> Map.fetch!(renames, imported) <> "." <> variable <> suffix
    end)
  end

  defp rewrite_semantic_interpolations(value, _renames, _mode), do: value

  defp rewrite_response_interpolations(%{"import_yarn_source_text" => source_text} = response, renames)
       when is_binary(source_text) do
    shortcut = Map.get(renames, "yarn", "yarn")
    Map.put(response, "text", Expression.interpolate(source_text, :response, shortcut))
  end

  defp rewrite_response_interpolations(response, renames) do
    Map.update(response, "text", nil, &rewrite_semantic_interpolations(&1, renames, :response))
  end

  defp rewrite_bare_variable_ref(value, renames) do
    case String.split(value, ".", parts: 2) do
      [shortcut, rest] -> Map.get(renames, shortcut, shortcut) <> "." <> rest
      _no_prefix -> value
    end
  end

  defp import_blocks(sheet_id, blocks, id_map) do
    Enum.reduce(blocks, {id_map, []}, fn block_data, {map, results} ->
      attrs = build_block_attrs(block_data)

      block =
        facade_insert_or_rollback!(
          SheetImportPersistence.import_block(sheet_id, attrs),
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
          SheetImportPersistence.import_column(block_id, attrs),
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
          SheetImportPersistence.import_row(block_id, attrs),
          {:table_row, row_data["name"]}
        )

      {Map.put(map, {:table_row, row_data["id"]}, row.id), [row | results]}
    end)
  end

  # =============================================================================
  # Flows import (two-pass for parent_id)
  # =============================================================================

  defp import_flows(project, data, id_map, strategy, existing_shortcuts, sheet_shortcut_renames) do
    flows = data["flows"] || []

    if flows == [],
      do: {id_map, [], 0},
      else: do_import_flows(project, flows, id_map, strategy, existing_shortcuts, sheet_shortcut_renames)
  end

  defp do_import_flows(project, flows, id_map, strategy, existing_shortcuts, sheet_shortcut_renames) do
    used_shortcuts = Map.fetch!(existing_shortcuts, :flow)

    # Pass 1: create flows without parent_id
    {id_map, flow_records, node_count, _used_shortcuts} =
      Enum.reduce(flows, {id_map, [], 0, used_shortcuts}, fn flow_data, {map, records, node_count, used} ->
        case resolve_shortcut(
               flow_data["shortcut"],
               strategy,
               project.id,
               :flow,
               used
             ) do
          :skip ->
            {map, records, node_count, used}

          shortcut ->
            {map, flow, imported_node_count} =
              create_flow_record(project, flow_data, shortcut, map, sheet_shortcut_renames)

            {
              map,
              [{flow, flow_data} | records],
              node_count + imported_node_count,
              reserve_shortcut(used, shortcut)
            }
        end
      end)

    # Pass 2: set parent_id
    link_parent_ids(flow_records, id_map, :flow)

    {id_map, Enum.map(flow_records, fn {flow, _} -> flow end), node_count}
  end

  defp create_flow_record(project, flow_data, shortcut, map, sheet_shortcut_renames) do
    flow_data = finalize_import_flow_layout(flow_data, sheet_shortcut_renames)

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
      project.id
      |> FlowImportPersistence.import_flow(attrs)
      |> reject_duplicate_main_flow()
      |> facade_insert_or_rollback!({:flow, flow_data["name"]})

    map = Map.put(map, {:flow, flow_data["id"]}, flow.id)

    {map, node_results} =
      import_nodes(project.id, flow.id, flow_data["nodes"] || [], map, sheet_shortcut_renames)

    {map, _} = import_flow_connections(flow.id, flow_data["connections"] || [], map)

    {map, flow, length(node_results)}
  end

  # Yarn layout is initially computed while the review is still unresolved and
  # before target-project shortcut conflicts are known. Re-measure the final
  # rendered data immediately before persistence so review decisions and
  # semantic shortcut rewrites cannot make parallel nodes overlap. Only copy
  # positions back: applying the rewrites to the persisted input here would
  # allow chained shortcut maps to be rewritten a second time in `import_nodes`.
  defp finalize_import_flow_layout(
         %{"settings" => %{"import_source" => "yarn_spinner"}, "nodes" => nodes} = flow_data,
         shortcut_renames
       )
       when is_list(nodes) do
    layout_nodes =
      Enum.map(nodes, fn node ->
        Map.update(node, "data", %{}, &rewrite_imported_refs(&1, node["type"], shortcut_renames))
      end)

    positions =
      layout_nodes
      |> Layout.assign_positions(
        flow_data["connections"] || [],
        flow_data["import_yarn_annotation_anchors"] || %{}
      )
      |> Map.new(&{&1["id"], {&1["position_x"], &1["position_y"]}})

    positioned_nodes =
      Enum.map(nodes, fn node ->
        case Map.fetch(positions, node["id"]) do
          {:ok, {x, y}} -> node |> Map.put("position_x", x) |> Map.put("position_y", y)
          :error -> node
        end
      end)

    Map.put(flow_data, "nodes", positioned_nodes)
  end

  defp finalize_import_flow_layout(flow_data, _shortcut_renames), do: flow_data

  defp import_nodes(project_id, flow_id, nodes, id_map, sheet_shortcut_renames) do
    existing_dialogue_ids = load_dialogue_localization_ids(project_id)

    {id_map, results, _dialogue_ids} =
      Enum.reduce(nodes, {id_map, [], existing_dialogue_ids}, fn node_data, {map, results, dialogue_ids} ->
        {data, dialogue_ids} =
          node_data["data"]
          |> rewrite_imported_refs(node_data["type"], sheet_shortcut_renames)
          |> remap_node_data(map)
          |> normalize_legacy_hub_color(node_data["type"])
          |> rekey_conflicting_import_dialogue(node_data["type"], dialogue_ids)

        attrs = %{
          "type" => node_data["type"],
          "position_x" => node_data["position_x"] || 0.0,
          "position_y" => node_data["position_y"] || 0.0,
          "data" => data,
          "sequence_config" => node_data["sequence_config"]
        }

        node =
          facade_insert_or_rollback!(FlowImportPersistence.import_node(flow_id, attrs), {:node, node_data["type"]})

        {Map.put(map, {:node, node_data["id"]}, node.id), [node | results], dialogue_ids}
      end)

    link_node_parent_ids(nodes, results, id_map)

    {id_map, results}
  end

  defp link_node_parent_ids(nodes, imported_nodes, id_map) do
    imported_nodes_by_id = Map.new(imported_nodes, &{&1.id, &1})

    Enum.each(nodes, fn node_data ->
      with parent_source_id when not is_nil(parent_source_id) <- node_data["parent_id"],
           node_id when is_integer(node_id) <- Map.get(id_map, {:node, node_data["id"]}),
           parent_id when is_integer(parent_id) <- Map.get(id_map, {:node, parent_source_id}),
           %FlowNode{} = node <- Map.get(imported_nodes_by_id, node_id) do
        facade_insert_or_rollback!(
          FlowImportPersistence.link_node_parent(node, parent_id),
          {:node_parent, node_data["id"]}
        )
      else
        _unresolved_reference -> :ok
      end
    end)
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
    |> Map.drop(@transient_import_node_data_keys)
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
        Map.drop(resp, ["instruction_assignments" | @transient_import_response_data_keys])
      end)

    Map.put(data, "responses", cleaned)
  end

  defp clean_responses(data), do: data

  defp normalize_legacy_hub_color(data, type) when type in ["hub", "hub_marker"] and is_map(data) do
    Map.put(data, "color", FlowImportPersistence.resolve_legacy_hub_color(data["color"]))
  end

  defp normalize_legacy_hub_color(data, _type), do: data

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

    results = FlowImportPersistence.bulk_insert_connections(Enum.reverse(valid_attrs))

    {id_map, results}
  end

  defp truncate_string(nil, _max), do: nil
  defp truncate_string(str, max) when is_binary(str), do: String.slice(str, 0, max)
  defp truncate_string(val, _max), do: val

  # =============================================================================
  # Scenes import (two-pass for parent_id)
  # =============================================================================

  defp import_scenes(project, data, id_map, strategy, existing_shortcuts, sheet_shortcut_renames) do
    scenes = data["scenes"] || []

    if scenes == [],
      do: {id_map, []},
      else: do_import_scenes(project, scenes, id_map, strategy, existing_shortcuts, sheet_shortcut_renames)
  end

  defp do_import_scenes(project, scenes, id_map, strategy, existing_shortcuts, sheet_shortcut_renames) do
    used_shortcuts = Map.fetch!(existing_shortcuts, :scene)

    {id_map, scene_records, _used_shortcuts} =
      Enum.reduce(scenes, {id_map, [], used_shortcuts}, fn scene_data, {map, records, used} ->
        case resolve_shortcut(
               scene_data["shortcut"],
               strategy,
               project.id,
               :scene,
               used
             ) do
          :skip ->
            {map, records, used}

          shortcut ->
            {map, scene} = create_scene_record(project, scene_data, shortcut, map, sheet_shortcut_renames)
            {map, [{scene, scene_data} | records], reserve_shortcut(used, shortcut)}
        end
      end)

    link_parent_ids(scene_records, id_map, :scene)

    {id_map, Enum.map(scene_records, fn {scene, _} -> scene end)}
  end

  defp create_scene_record(project, scene_data, shortcut, map, sheet_shortcut_renames) do
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
        SceneImportPersistence.import_scene(project.id, attrs),
        {:scene, scene_data["name"]}
      )

    map = Map.put(map, {:scene, scene_data["id"]}, scene.id)
    {map, _} = import_layers(scene.id, scene_data["layers"] || [], map)

    # Pin and zone payloads carry the same variable references flow nodes do
    # (conditions, action assignments, display variable_refs), so a renamed
    # sheet shortcut must follow them too. Scene annotations stay verbatim —
    # they are prose, not references.
    {map, _} = import_pins(scene.id, scene_data["pins"] || [], map, sheet_shortcut_renames)
    {map, _} = import_zones(scene.id, scene_data["zones"] || [], map, sheet_shortcut_renames)
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
          SceneImportPersistence.import_layer(scene_id, attrs),
          {:layer, layer_data["name"]}
        )

      {Map.put(map, {:layer, layer_data["id"]}, layer.id), [layer | results]}
    end)
  end

  defp import_pins(scene_id, pins, id_map, sheet_shortcut_renames) do
    Enum.reduce(pins, {id_map, []}, fn pin_data, {map, results} ->
      pin_data = rewrite_variable_shortcuts(pin_data, sheet_shortcut_renames)

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
        facade_insert_or_rollback!(SceneImportPersistence.import_pin(scene_id, attrs), {:pin, pin_data["label"]})

      {Map.put(map, {:pin, pin_data["id"]}, pin.id), [pin | results]}
    end)
  end

  defp import_zones(scene_id, zones, id_map, sheet_shortcut_renames) do
    Enum.reduce(zones, {id_map, []}, fn zone_data, {map, results} ->
      zone_data = rewrite_variable_shortcuts(zone_data, sheet_shortcut_renames)
      attrs = import_zone_attrs(zone_data, map)

      zone =
        facade_insert_or_rollback!(
          SceneImportPersistence.import_zone(scene_id, attrs),
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

    results = SceneImportPersistence.bulk_insert_connections(Enum.reverse(valid_attrs))

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

    results = SceneImportPersistence.bulk_insert_annotations(Enum.reverse(valid_attrs))

    {id_map, results}
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
          LocalizationReconstitution.import_language(project_id, attrs),
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

    LocalizationReconstitution.bulk_import_texts(Enum.reverse(valid_attrs))
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
      "block" => load_sources(Storyarn.Projects.Persistence.BlockRecord, ids_by_type["block"]),
      "sheet" => load_sources(Storyarn.Projects.Persistence.SheetRecord, ids_by_type["sheet"])
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

    LocalizationReconstitution.bulk_import_glossary_entries(Enum.reverse(valid_attrs))
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

  defp reserve_shortcut(used, shortcut) when is_binary(shortcut), do: MapSet.put(used, shortcut)
  defp reserve_shortcut(used, _shortcut), do: used

  defp resolve_shortcut(nil, _strategy, _project_id, _entity_type, _used_shortcuts), do: nil

  defp resolve_shortcut(shortcut, strategy, project_id, entity_type, used_shortcuts) do
    exists? = MapSet.member?(used_shortcuts, shortcut)

    cond do
      not exists? ->
        shortcut

      strategy == :skip ->
        :skip

      strategy == :overwrite ->
        overwrite_existing(shortcut, project_id, entity_type)

      strategy == :rename ->
        Shortcut.unique(shortcut, used_shortcuts, shortcut)

      true ->
        shortcut
    end
  end

  defp overwrite_existing(shortcut, project_id, :sheet) do
    SheetImportPersistence.soft_delete_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp overwrite_existing(shortcut, project_id, :flow) do
    FlowImportPersistence.soft_delete_by_shortcut(project_id, shortcut)
    shortcut
  end

  defp overwrite_existing(shortcut, project_id, :scene) do
    SceneImportPersistence.soft_delete_by_shortcut(project_id, shortcut)
    shortcut
  end

  # A project may hold exactly one main flow. Rolling back with a named reason
  # keeps this out of the generic retry path: a unique-constraint violation is
  # deterministic, so retrying it three times can only fail three times and
  # then report "it may be retried automatically" about something that cannot.
  defp reject_duplicate_main_flow({:error, %Ecto.Changeset{errors: errors}} = result) do
    # Only the named partial unique index means "this project already has a
    # main flow" — any other `:is_main` error (a cast failure, a future
    # validation) must keep its own changeset instead of borrowing that
    # message about a main flow the project may not even have.
    duplicate_main? =
      errors
      |> Keyword.get_values(:is_main)
      |> Enum.any?(fn {_message, meta} ->
        meta[:constraint] == :unique and meta[:constraint_name] == "flows_project_id_is_main_index"
      end)

    if duplicate_main?, do: Repo.rollback(:project_already_has_main_flow), else: result
  end

  defp reject_duplicate_main_flow(result), do: result

  defp facade_insert_or_rollback!({:ok, record}, _context), do: record

  defp facade_insert_or_rollback!({:error, changeset}, context), do: Repo.rollback({:import_failed, context, changeset})

  defp import_sheet_avatars(sheet, sheet_data, id_map) do
    case sheet_data["avatars"] do
      avatars when is_list(avatars) and avatars != [] ->
        Enum.each(avatars, &import_single_avatar(sheet, &1, id_map))

      _ ->
        # Fallback: legacy format with avatar_asset_id
        avatar_asset_id = remap_id(id_map, :asset, sheet_data["avatar_asset_id"])
        if avatar_asset_id, do: SheetImportPersistence.add_avatar(sheet, avatar_asset_id)
    end
  end

  defp import_single_avatar(sheet, avatar_data, id_map) do
    asset_id = remap_id(id_map, :asset, avatar_data["asset_id"])

    if asset_id do
      SheetImportPersistence.add_avatar(sheet, asset_id, %{
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

  defp link_import_parent(:sheet, entity, parent_id), do: SheetImportPersistence.link_import_parent(entity, parent_id)

  defp link_import_parent(:flow, entity, parent_id), do: FlowImportPersistence.link_flow_parent(entity, parent_id)

  defp link_import_parent(:scene, entity, parent_id), do: SceneImportPersistence.link_parent(entity, parent_id)

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
        SceneImportPersistence.link_pin_flow_id(pin_new_id, flow_id)
      end

      # Link zone target_ids that reference flows
      for zone_data <- scene_data["zones"] || [],
          zone_data["action_type"] in [nil, "action"],
          zone_data["target_type"] == "flow",
          target_id = remap_id(id_map, :flow, zone_data["target_id"]),
          not is_nil(target_id),
          zone_new_id = Map.get(id_map, {:zone, zone_data["id"]}),
          not is_nil(zone_new_id) do
        SceneImportPersistence.link_zone_target(zone_new_id, "flow", target_id)
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
        FlowImportPersistence.link_node_data(node_id, updated_data)
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

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end

defmodule Storyarn.Versioning.SnapshotProjectContentHealth do
  @moduledoc """
  Collects project-wide content findings that cannot be attributed by an
  individual sheet, flow, or scene snapshot builder.

  The collector is deliberately pure and emits locations only. Values used to
  detect a collision or mismatch (shortcuts, localization contents, locales,
  and runtime localization identifiers) never enter the returned issues.
  """

  alias Storyarn.Localization.SourceContract

  @root_collections [
    {"sheets", :sheet},
    {"flows", :flow},
    {"scenes", :scene}
  ]

  @doc "Returns a deterministic, exhaustive inventory of project-wide findings."
  @spec issues(map(), pos_integer()) :: [map()]
  def issues(project_snapshot, project_id) when is_map(project_snapshot) and is_integer(project_id) and project_id > 0 do
    project_snapshot
    |> collect_issues(project_id)
    |> Enum.uniq()
    |> Enum.sort_by(&issue_sort_key/1)
  end

  def issues(_project_snapshot, _project_id), do: []

  defp collect_issues(project_snapshot, project_id) do
    tree_issues(project_snapshot, project_id) ++
      duplicate_shortcut_issues(project_snapshot, project_id) ++
      multiple_main_flow_issues(project_snapshot, project_id) ++
      cross_flow_dialogue_localization_id_issues(project_snapshot, project_id) ++
      runtime_localization_issues(project_snapshot, project_id)
  end

  # -- Project trees -------------------------------------------------------

  defp tree_issues(project_snapshot, project_id) do
    Enum.flat_map(@root_collections, fn {collection, entity_type} ->
      roots = root_entries(project_snapshot, collection)
      root_ids = MapSet.new(roots, & &1.id)
      entries = tree_entries(project_snapshot, collection)
      tree_ids = entries |> Enum.flat_map(&positive_entry_ids/1) |> MapSet.new()

      tree_coverage_issues(root_ids, tree_ids, entity_type, project_id) ++
        tree_parent_issues(entries, root_ids, entity_type, project_id) ++
        tree_cycle_issues(entries, root_ids, entity_type, project_id)
    end)
  end

  defp tree_entries(project_snapshot, collection) do
    case get_in(project_snapshot, ["tree", collection]) do
      entries when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _invalid -> []
    end
  end

  defp positive_entry_ids(%{"id" => id}) when is_integer(id) and id > 0, do: [id]
  defp positive_entry_ids(_entry), do: []

  defp tree_coverage_issues(root_ids, tree_ids, entity_type, project_id) do
    root_ids
    |> MapSet.symmetric_difference(tree_ids)
    |> Enum.map(fn entity_id ->
      issue(
        :project_snapshot_tree_coverage_mismatch,
        entity_type,
        entity_id,
        "tree",
        :project,
        project_id
      )
    end)
  end

  defp tree_parent_issues(entries, root_ids, entity_type, project_id) do
    Enum.flat_map(entries, fn entry ->
      entity_id = entry["id"]
      parent_id = entry["parent_id"]

      if positive_id?(entity_id) and invalid_tree_parent?(entity_id, parent_id, root_ids) do
        [
          issue(
            :invalid_project_snapshot_tree_parent,
            entity_type,
            entity_id,
            "parent_id",
            :project,
            project_id
          )
        ]
      else
        []
      end
    end)
  end

  defp invalid_tree_parent?(_entity_id, nil, _root_ids), do: false

  defp invalid_tree_parent?(entity_id, parent_id, root_ids) do
    not positive_id?(parent_id) or parent_id == entity_id or
      not MapSet.member?(root_ids, parent_id)
  end

  defp tree_cycle_issues(entries, root_ids, entity_type, project_id) do
    parents = valid_tree_parents(entries, root_ids)

    parents
    |> cycle_nodes()
    |> Enum.map(fn entity_id ->
      issue(
        :project_snapshot_tree_cycle,
        entity_type,
        entity_id,
        "parent_id",
        :project,
        project_id
      )
    end)
  end

  defp valid_tree_parents(entries, root_ids) do
    Enum.reduce(entries, %{}, fn entry, parents ->
      entity_id = entry["id"]
      parent_id = entry["parent_id"]

      if positive_id?(entity_id) and MapSet.member?(root_ids, entity_id) and
           not invalid_tree_parent?(entity_id, parent_id, root_ids) do
        Map.put_new(parents, entity_id, parent_id)
      else
        parents
      end
    end)
  end

  defp cycle_nodes(parents) do
    parents
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn entity_id, {resolved, cycles} ->
      collect_cycle_nodes(entity_id, parents, resolved, cycles)
    end)
    |> elem(1)
  end

  defp collect_cycle_nodes(entity_id, parents, resolved, cycles) do
    if MapSet.member?(resolved, entity_id) do
      {resolved, cycles}
    else
      {visited, found_cycle} = walk_tree_chain(entity_id, parents, resolved, [], MapSet.new())
      {Enum.reduce(visited, resolved, &MapSet.put(&2, &1)), MapSet.union(cycles, found_cycle)}
    end
  end

  defp walk_tree_chain(nil, _parents, _resolved, path, _seen), do: {path, MapSet.new()}

  defp walk_tree_chain(entity_id, parents, resolved, path, seen) do
    cond do
      not Map.has_key?(parents, entity_id) ->
        {path, MapSet.new()}

      MapSet.member?(resolved, entity_id) ->
        {path, MapSet.new()}

      MapSet.member?(seen, entity_id) ->
        cycle = path |> Enum.take_while(&(&1 != entity_id)) |> then(&[entity_id | &1])
        {path, MapSet.new(cycle)}

      true ->
        walk_tree_chain(
          Map.get(parents, entity_id),
          parents,
          resolved,
          [entity_id | path],
          MapSet.put(seen, entity_id)
        )
    end
  end

  # -- Global root contracts ---------------------------------------------

  defp duplicate_shortcut_issues(project_snapshot, project_id) do
    Enum.flat_map(
      @root_collections,
      &duplicate_shortcut_collection_issues(project_snapshot, project_id, &1)
    )
  end

  defp duplicate_shortcut_collection_issues(project_snapshot, project_id, {collection, entity_type}) do
    project_snapshot
    |> root_entries(collection)
    |> Enum.reject(&is_nil(&1.snapshot["shortcut"]))
    |> Enum.group_by(& &1.snapshot["shortcut"])
    |> Enum.flat_map(&duplicate_shortcut_group_issues(&1, entity_type, project_id))
  end

  defp duplicate_shortcut_group_issues({_shortcut, [_single]}, _entity_type, _project_id), do: []

  defp duplicate_shortcut_group_issues({_shortcut, collisions}, entity_type, project_id) do
    Enum.map(collisions, fn collision ->
      issue(
        :duplicate_project_snapshot_root_field,
        entity_type,
        collision.id,
        "shortcut",
        :project,
        project_id
      )
    end)
  end

  defp multiple_main_flow_issues(project_snapshot, project_id) do
    main_flows =
      project_snapshot
      |> root_entries("flows")
      |> Enum.filter(&(&1.snapshot["is_main"] == true))

    if length(main_flows) > 1 do
      Enum.map(main_flows, fn flow ->
        issue(
          :invalid_project_snapshot_main_flow_count,
          :flow,
          flow.id,
          "is_main",
          :project,
          project_id
        )
      end)
    else
      []
    end
  end

  defp cross_flow_dialogue_localization_id_issues(project_snapshot, _project_id) do
    project_snapshot
    |> dialogue_localization_id_occurrences()
    |> Enum.group_by(& &1.localization_id)
    |> Enum.flat_map(&cross_flow_dialogue_localization_id_group_issues/1)
  end

  defp cross_flow_dialogue_localization_id_group_issues({_localization_id, occurrences}) do
    flow_count = occurrences |> MapSet.new(& &1.flow_id) |> MapSet.size()
    if flow_count > 1, do: Enum.map(occurrences, &dialogue_localization_id_issue/1), else: []
  end

  defp dialogue_localization_id_issue(occurrence) do
    issue(
      :duplicate_snapshot_dialogue_localization_id,
      :flow_node,
      occurrence.node_id,
      "localization_id",
      :flow,
      occurrence.flow_id
    )
  end

  defp dialogue_localization_id_occurrences(project_snapshot) do
    project_snapshot
    |> root_entries("flows")
    |> Enum.flat_map(fn flow ->
      case flow.snapshot["nodes"] do
        nodes when is_list(nodes) ->
          Enum.flat_map(nodes, &dialogue_localization_id_occurrence(&1, flow.id))

        _invalid ->
          []
      end
    end)
  end

  defp dialogue_localization_id_occurrence(%{"original_id" => node_id, "type" => "dialogue", "data" => data}, flow_id)
       when is_integer(node_id) and node_id > 0 and is_map(data) do
    if Map.has_key?(data, "localization_id") do
      [%{flow_id: flow_id, node_id: node_id, localization_id: data["localization_id"]}]
    else
      []
    end
  end

  defp dialogue_localization_id_occurrence(_node, _flow_id), do: []

  # -- Runtime localization inventory ------------------------------------

  defp runtime_localization_issues(project_snapshot, project_id) do
    source_locations = source_location_index(project_snapshot)
    global_rows = active_runtime_global_rows(project_snapshot)
    nested_rows = nested_runtime_rows(project_snapshot)
    global_index = localization_index(global_rows)
    nested_index = localization_index(nested_rows)
    global_keys = global_index |> Map.keys() |> MapSet.new()
    nested_keys = nested_index |> Map.keys() |> MapSet.new()

    localization_scope_issues(
      global_rows,
      source_locations,
      active_snapshot_locales(project_snapshot),
      project_id
    ) ++
      localization_coverage_issues(
        MapSet.difference(global_keys, nested_keys),
        global_index,
        source_locations,
        project_id
      ) ++
      localization_coverage_issues(
        MapSet.difference(nested_keys, global_keys),
        nested_index,
        source_locations,
        project_id
      ) ++
      localization_row_mismatch_issues(
        MapSet.intersection(global_keys, nested_keys),
        global_index,
        nested_index,
        source_locations,
        project_id
      )
  end

  defp active_runtime_global_rows(project_snapshot) do
    case get_in(project_snapshot, ["localization", "texts"]) do
      rows when is_list(rows) ->
        Enum.flat_map(rows, &active_runtime_global_row/1)

      _invalid ->
        []
    end
  end

  defp active_runtime_global_row(row) when is_map(row) do
    if is_nil(row["archived_at"]),
      do: [%{row: row, container: nil}],
      else: []
  end

  defp active_runtime_global_row(_row), do: []

  defp localization_scope_issues(rows, source_locations, target_locales, project_id) do
    Enum.flat_map(rows, fn entry ->
      row = entry.row

      locale_issues =
        if MapSet.member?(target_locales, row["locale_code"]),
          do: [],
          else: [localization_issue(:localization_locale_outside_snapshot, entry, source_locations, project_id)]

      source_issues =
        if valid_localization_source?(row, source_locations),
          do: [],
          else: [localization_issue(:localization_source_outside_snapshot, entry, source_locations, project_id)]

      locale_issues ++ source_issues
    end)
  end

  defp valid_localization_source?(row, source_locations) do
    Map.has_key?(source_locations, {row["source_type"], row["source_id"]}) and
      SourceContract.field?(row["source_type"], row["source_field"])
  end

  defp active_snapshot_locales(project_snapshot) do
    case get_in(project_snapshot, ["localization", "languages"]) do
      languages when is_list(languages) ->
        languages
        |> Enum.filter(fn
          language when is_map(language) ->
            is_nil(language["archived_at"])

          _invalid ->
            false
        end)
        |> MapSet.new(& &1["locale_code"])

      _invalid ->
        MapSet.new()
    end
  end

  defp nested_runtime_rows(project_snapshot) do
    Enum.flat_map(
      [{"sheets", :sheet}, {"flows", :flow}],
      &nested_runtime_collection_rows(project_snapshot, &1)
    )
  end

  defp nested_runtime_collection_rows(project_snapshot, {collection, container_type}) do
    project_snapshot
    |> root_entries(collection)
    |> Enum.flat_map(&nested_runtime_root_rows(&1, container_type))
  end

  defp nested_runtime_root_rows(root, container_type) do
    case root.snapshot["localization"] do
      rows when is_list(rows) ->
        Enum.flat_map(rows, &nested_runtime_row(&1, container_type, root.id))

      _invalid ->
        []
    end
  end

  defp nested_runtime_row(row, container_type, container_id) when is_map(row),
    do: [%{row: row, container: {container_type, container_id}}]

  defp nested_runtime_row(_row, _container_type, _container_id), do: []

  defp localization_index(rows) do
    Enum.reduce(rows, %{}, fn entry, index ->
      Map.update(index, runtime_localization_key(entry.row), [entry], &[entry | &1])
    end)
  end

  defp runtime_localization_key(row) do
    {
      row["source_type"],
      row["source_id"],
      row["source_field"],
      row["locale_code"]
    }
  end

  defp localization_coverage_issues(keys, index, source_locations, project_id) do
    Enum.flat_map(keys, fn key ->
      index
      |> Map.fetch!(key)
      |> Enum.map(fn entry ->
        localization_issue(
          :project_snapshot_runtime_localization_coverage_mismatch,
          entry,
          source_locations,
          project_id
        )
      end)
    end)
  end

  defp localization_row_mismatch_issues(keys, global_index, nested_index, source_locations, project_id) do
    Enum.flat_map(keys, fn key ->
      localization_row_mismatch_issues(
        Map.fetch!(global_index, key),
        Map.fetch!(nested_index, key),
        source_locations,
        project_id
      )
    end)
  end

  defp localization_row_mismatch_issues(global_entries, nested_entries, source_locations, project_id) do
    if equivalent_runtime_rows?(global_entries, nested_entries) do
      []
    else
      Enum.map(
        nested_entries,
        &localization_issue(
          :project_snapshot_runtime_localization_row_mismatch,
          &1,
          source_locations,
          project_id
        )
      )
    end
  end

  defp equivalent_runtime_rows?(global_entries, nested_entries) do
    global_rows = MapSet.new(global_entries, &Map.drop(&1.row, ["content_role", "vo_eligible"]))
    nested_rows = MapSet.new(nested_entries, & &1.row)
    global_rows == nested_rows
  end

  defp localization_issue(code, entry, source_locations, project_id) do
    row = entry.row
    source_type = safe_source_type(row["source_type"])
    source_id = row["source_id"]
    source_field = row["source_field"]

    if not is_nil(source_type) and positive_id?(source_id) and
         SourceContract.field?(row["source_type"], source_field) do
      {container_type, container_id} =
        entry.container ||
          Map.get(source_locations, {row["source_type"], source_id}, {:project, project_id})

      issue(
        code,
        source_type,
        source_id,
        source_field,
        container_type,
        container_id
      )
    else
      issue(code, :project, project_id, "localization", :project, project_id)
    end
  end

  defp source_location_index(project_snapshot) do
    sheet_locations =
      project_snapshot
      |> root_entries("sheets")
      |> Enum.flat_map(fn sheet ->
        [{{"sheet", sheet.id}, {:sheet, sheet.id}}] ++
          nested_source_locations(sheet.snapshot["blocks"], "block", :sheet, sheet.id)
      end)

    flow_locations =
      project_snapshot
      |> root_entries("flows")
      |> Enum.flat_map(fn flow ->
        nested_source_locations(flow.snapshot["nodes"], "flow_node", :flow, flow.id)
      end)

    (sheet_locations ++ flow_locations)
    |> Enum.sort_by(fn {{source_type, source_id}, {container_type, container_id}} ->
      {source_type, source_id, Atom.to_string(container_type), container_id}
    end)
    |> Enum.reduce(%{}, fn {source, container}, locations ->
      Map.put_new(locations, source, container)
    end)
  end

  defp nested_source_locations(entries, source_type, container_type, container_id) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"original_id" => source_id} when is_integer(source_id) and source_id > 0 ->
        [{{source_type, source_id}, {container_type, container_id}}]

      _invalid ->
        []
    end)
  end

  defp nested_source_locations(_entries, _source_type, _container_type, _container_id), do: []

  defp safe_source_type("flow_node"), do: :flow_node
  defp safe_source_type("block"), do: :block
  defp safe_source_type("sheet"), do: :sheet
  defp safe_source_type(_source_type), do: nil

  # -- Shared -------------------------------------------------------------

  defp root_entries(project_snapshot, collection) do
    case project_snapshot[collection] do
      entries when is_list(entries) ->
        Enum.flat_map(entries, fn
          %{"id" => id, "snapshot" => snapshot}
          when is_integer(id) and id > 0 and is_map(snapshot) ->
            [%{id: id, snapshot: snapshot}]

          _invalid ->
            []
        end)

      _invalid ->
        []
    end
  end

  defp issue(code, entity_type, entity_id, source_field, container_type, container_id) do
    %{
      code: code,
      severity: :warning,
      entity_type: entity_type,
      entity_id: entity_id,
      source_field: source_field,
      impact: :restore_blocked,
      container_type: container_type,
      container_id: container_id
    }
  end

  defp positive_id?(value), do: is_integer(value) and value > 0

  defp issue_sort_key(issue) do
    {
      Atom.to_string(issue.code),
      Atom.to_string(issue.container_type),
      issue.container_id,
      Atom.to_string(issue.entity_type),
      issue.entity_id,
      issue.source_field || ""
    }
  end
end

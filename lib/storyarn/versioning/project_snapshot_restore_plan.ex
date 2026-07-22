defmodule Storyarn.Versioning.ProjectSnapshotRestorePlan do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @entity_specs %{
    sheets: %{key: "sheets", schema: Sheet},
    flows: %{key: "flows", schema: Flow},
    scenes: %{key: "scenes", schema: Scene}
  }

  @project_fields ~w(
    description project_type project_subtype project_type_other settings
    auto_snapshots_enabled auto_version_flows auto_version_scenes
    auto_version_sheets
  )

  @type t :: %{
          entries: %{required(atom()) => [map()]},
          ids: %{required(atom()) => MapSet.t(integer())},
          ordered: %{required(atom()) => [map()]},
          tree: %{required(atom()) => [map()]},
          blocks: [map()],
          project_attrs: map()
        }

  @spec build(map()) :: {:ok, t()} | {:error, term()}
  def build(snapshot) when is_map(snapshot) do
    with {:ok, entries} <- validate_root_entries(snapshot),
         :ok <- validate_main_flow(entries.flows),
         ids = Map.new(entries, fn {type, type_entries} -> {type, MapSet.new(type_entries, & &1["id"])} end),
         {:ok, blocks} <- validate_sheet_blocks(entries.sheets),
         {:ok, sheet_order} <- order_sheets(entries.sheets, blocks),
         {:ok, flow_order} <- order_flows(entries.flows, ids.flows),
         {:ok, tree} <- validate_tree(snapshot["tree"], ids),
         {:ok, project_attrs} <- validate_project_attrs(snapshot["project"]) do
      {:ok,
       %{
         entries: entries,
         ids: ids,
         ordered: %{
           sheets: sheet_order,
           flows: flow_order,
           scenes: entries.scenes
         },
         tree: tree,
         blocks: blocks,
         project_attrs: project_attrs
       }}
    end
  end

  def build(_snapshot), do: {:error, :invalid_project_snapshot_envelope}

  defp validate_main_flow(entries) do
    main_flow_ids =
      entries
      |> Enum.filter(&(&1["snapshot"]["is_main"] == true))
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    case main_flow_ids do
      [] -> :ok
      [_flow_id] -> :ok
      ids -> {:error, {:multiple_project_snapshot_main_flows, ids}}
    end
  end

  @spec prepare(integer(), t()) :: {:ok, map()} | {:error, term()}
  def prepare(project_id, plan) do
    with :ok <- validate_root_ownership(project_id, plan),
         :ok <- validate_block_ownership(plan.blocks),
         :ok <- validate_main_flow_conflicts(project_id, plan),
         :ok <- validate_current_only_flow_cross_project_callers(project_id, plan),
         {:ok, removed} <- reconcile_roots(project_id, plan),
         :ok <- reconcile_sheet_blocks(plan) do
      {:ok, %{removed: removed}}
    end
  end

  @spec apply_tree(integer(), t()) :: :ok | {:error, term()}
  def apply_tree(project_id, plan) do
    Enum.reduce_while(@entity_specs, :ok, fn {type, %{schema: schema}}, :ok ->
      case apply_entity_tree(schema, project_id, plan.tree[type]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec restore_project_metadata(Project.t(), t()) ::
          {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def restore_project_metadata(%Project{} = project, plan) do
    project
    |> Project.update_changeset(plan.project_attrs)
    |> Repo.update()
  end

  defp validate_root_entries(snapshot) do
    Enum.reduce_while(@entity_specs, {:ok, %{}}, fn {type, %{key: key}}, {:ok, acc} ->
      case validate_entity_entries(snapshot[key], type) do
        {:ok, entries} -> {:cont, {:ok, Map.put(acc, type, entries)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entity_entries(entries, type) when is_list(entries) do
    with :ok <- validate_each_root_entry(entries, type),
         :ok <- validate_unique_ids(Enum.map(entries, & &1["id"]), {:duplicate_project_snapshot_root, type}) do
      {:ok, entries}
    end
  end

  defp validate_entity_entries(_entries, type), do: {:error, {:invalid_project_snapshot_collection, type}}

  defp validate_each_root_entry(entries, type) do
    Enum.reduce_while(entries, :ok, fn
      %{"id" => id, "snapshot" => %{"original_id" => id}} = _entry, :ok
      when is_integer(id) and id > 0 ->
        {:cont, :ok}

      %{"id" => id, "snapshot" => %{"original_id" => snapshot_id}}, :ok ->
        {:halt, {:error, {:project_snapshot_root_id_mismatch, type, id, snapshot_id}}}

      entry, :ok ->
        {:halt, {:error, {:invalid_project_snapshot_entry, type, entry}}}
    end)
  end

  defp validate_sheet_blocks(sheet_entries) do
    result =
      Enum.reduce_while(sheet_entries, {:ok, []}, fn entry, {:ok, acc} ->
        case tagged_sheet_blocks(entry) do
          {:ok, tagged} ->
            {:cont, {:ok, tagged ++ acc}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)

    with {:ok, blocks} <- result,
         :ok <- validate_block_ids(blocks) do
      {:ok, Enum.reverse(blocks)}
    end
  end

  defp tagged_sheet_blocks(entry) do
    case entry["snapshot"]["blocks"] do
      blocks when is_list(blocks) ->
        {:ok,
         Enum.map(
           blocks,
           &Map.put(&1, "__restore_owner_sheet_id", entry["id"])
         )}

      invalid ->
        {:error, {:invalid_project_snapshot_blocks, entry["id"], invalid}}
    end
  end

  defp validate_block_ids(blocks) do
    ids = Enum.map(blocks, & &1["original_id"])

    if Enum.any?(ids, &(not (is_integer(&1) and &1 > 0))) do
      {:error, :invalid_project_snapshot_block_id}
    else
      validate_unique_ids(ids, :duplicate_project_snapshot_block_id)
    end
  end

  defp validate_unique_ids(ids, error) do
    if length(ids) == MapSet.size(MapSet.new(ids)), do: :ok, else: {:error, error}
  end

  defp order_sheets(entries, blocks) do
    owner_by_block =
      Map.new(blocks, fn block ->
        {block["original_id"], block["__restore_owner_sheet_id"]}
      end)

    result =
      Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, dependencies} ->
        sheet_id = entry["id"]

        referenced_block_ids =
          Enum.map(entry["snapshot"]["blocks"], & &1["inherited_from_block_id"]) ++
            (entry["snapshot"]["hidden_inherited_block_ids"] || [])

        case referenced_block_owners(referenced_block_ids, owner_by_block, sheet_id) do
          {:ok, owners} ->
            {:cont, {:ok, Map.put(dependencies, sheet_id, owners)}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, dependencies} -> order_entries(entries, dependencies, :sheet)
      {:error, _reason} = error -> error
    end
  end

  defp referenced_block_owners(ids, owner_by_block, sheet_id) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn block_id, {:ok, owners} ->
      case Map.fetch(owner_by_block, block_id) do
        {:ok, ^sheet_id} ->
          {:cont, {:ok, owners}}

        {:ok, owner_sheet_id} ->
          {:cont, {:ok, MapSet.put(owners, owner_sheet_id)}}

        :error ->
          {:halt, {:error, {:missing_project_snapshot_block_reference, sheet_id, block_id}}}
      end
    end)
    |> case do
      {:ok, owners} -> {:ok, MapSet.to_list(owners)}
      {:error, _reason} = error -> error
    end
  end

  defp order_flows(entries, flow_ids) do
    dependencies =
      Map.new(entries, fn entry ->
        refs =
          entry["snapshot"]["nodes"]
          |> List.wrap()
          |> Enum.flat_map(&flow_node_references/1)
          |> Enum.uniq()

        {entry["id"], refs}
      end)

    case Enum.find(dependencies, fn {_id, refs} ->
           Enum.any?(refs, &(not MapSet.member?(flow_ids, &1)))
         end) do
      nil ->
        order_entries(entries, dependencies, :flow)

      {flow_id, refs} ->
        missing = Enum.find(refs, &(not MapSet.member?(flow_ids, &1)))
        {:error, {:missing_project_snapshot_flow_reference, flow_id, missing}}
    end
  end

  defp flow_node_references(%{"type" => "subflow", "data" => data}) when is_map(data),
    do: positive_reference(data["referenced_flow_id"])

  defp flow_node_references(%{"type" => "exit", "data" => %{"exit_mode" => "flow_reference"} = data}),
    do: positive_reference(data["referenced_flow_id"])

  defp flow_node_references(_node), do: []

  defp positive_reference(id) when is_integer(id) and id > 0, do: [id]
  defp positive_reference(nil), do: []
  defp positive_reference(id), do: [id]

  defp order_entries(entries, dependencies, type) do
    entry_by_id = Map.new(entries, &{&1["id"], &1})

    case topological_order(Map.keys(entry_by_id), dependencies, type) do
      {:ok, ordered_ids} -> {:ok, Enum.map(ordered_ids, &Map.fetch!(entry_by_id, &1))}
      {:error, _reason} = error -> error
    end
  end

  defp topological_order(ids, dependencies, type) do
    ids
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{temporary: MapSet.new(), permanent: MapSet.new(), order: []}}, fn id, {:ok, state} ->
      case visit(id, dependencies, type, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, state} -> {:ok, Enum.reverse(state.order)}
      {:error, _reason} = error -> error
    end
  end

  defp visit(id, dependencies, type, state) do
    cond do
      MapSet.member?(state.permanent, id) ->
        {:ok, state}

      MapSet.member?(state.temporary, id) ->
        {:error, {:project_snapshot_dependency_cycle, type, id}}

      true ->
        state = %{state | temporary: MapSet.put(state.temporary, id)}
        visit_dependencies(id, dependencies, type, state)
    end
  end

  defp visit_dependencies(id, dependencies, type, state) do
    dependencies
    |> Map.get(id, [])
    |> Enum.sort()
    |> Enum.reduce_while(
      {:ok, state},
      &visit_dependency(&1, &2, dependencies, type)
    )
    |> complete_visit(id)
  end

  defp visit_dependency(dependency_id, {:ok, current}, dependencies, type) do
    case visit(dependency_id, dependencies, type, current) do
      {:ok, next} -> {:cont, {:ok, next}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp complete_visit({:ok, current}, id) do
    {:ok,
     %{
       current
       | temporary: MapSet.delete(current.temporary, id),
         permanent: MapSet.put(current.permanent, id),
         order: [id | current.order]
     }}
  end

  defp complete_visit({:error, _reason} = error, _id), do: error

  defp validate_tree(tree, ids) when is_map(tree) do
    Enum.reduce_while(@entity_specs, {:ok, %{}}, fn {type, %{key: key}}, {:ok, acc} ->
      case validate_entity_tree(tree[key], ids[type], type) do
        {:ok, entries} -> {:cont, {:ok, Map.put(acc, type, entries)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_tree(_tree, _ids), do: {:error, :invalid_project_snapshot_tree}

  defp validate_entity_tree(entries, target_ids, type) when is_list(entries) do
    with :ok <- validate_tree_entries(entries, target_ids, type),
         entry_ids = MapSet.new(entries, & &1["id"]),
         true <- MapSet.equal?(entry_ids, target_ids),
         dependencies = Map.new(entries, &{&1["id"], List.wrap(&1["parent_id"])}),
         {:ok, _order} <- topological_order(MapSet.to_list(target_ids), dependencies, {:tree, type}) do
      {:ok, entries}
    else
      false -> {:error, {:project_snapshot_tree_manifest_mismatch, type}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_entity_tree(_entries, _target_ids, type), do: {:error, {:invalid_project_snapshot_tree, type}}

  defp validate_tree_entries(entries, target_ids, type) do
    ids = Enum.map(entries, & &1["id"])

    with :ok <- validate_unique_ids(ids, {:duplicate_project_snapshot_tree_id, type}) do
      Enum.reduce_while(
        entries,
        :ok,
        &reduce_valid_tree_entry(&1, &2, target_ids, type)
      )
    end
  end

  defp reduce_valid_tree_entry(entry, :ok, target_ids, type) do
    case validate_tree_entry(entry, target_ids, type) do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp validate_tree_entry(entry, target_ids, type) do
    id = entry["id"]
    parent_id = entry["parent_id"]
    position = entry["position"]

    cond do
      not (is_integer(id) and id > 0) ->
        {:error, {:invalid_project_snapshot_tree_id, type, id}}

      invalid_tree_parent?(parent_id, target_ids) ->
        {:error, {:invalid_project_snapshot_tree_parent, type, id, parent_id}}

      parent_id == id ->
        {:error, {:project_snapshot_tree_cycle, type, id}}

      not (is_integer(position) and position >= 0) ->
        {:error, {:invalid_project_snapshot_tree_position, type, id, position}}

      true ->
        :ok
    end
  end

  defp invalid_tree_parent?(nil, _target_ids), do: false

  defp invalid_tree_parent?(parent_id, target_ids) do
    not (is_integer(parent_id) and parent_id > 0 and
           MapSet.member?(target_ids, parent_id))
  end

  defp validate_project_attrs(project) when is_map(project) do
    missing = Enum.reject(@project_fields, &Map.has_key?(project, &1))

    if missing == [] do
      {:ok,
       Map.new(@project_fields, fn field ->
         {String.to_existing_atom(field), project[field]}
       end)}
    else
      {:error, {:missing_project_snapshot_fields, missing}}
    end
  end

  defp validate_project_attrs(_project), do: {:error, :invalid_project_snapshot_project}

  defp validate_root_ownership(project_id, plan) do
    Enum.reduce_while(@entity_specs, :ok, fn {type, %{schema: schema}}, :ok ->
      ids = MapSet.to_list(plan.ids[type])

      conflict =
        Repo.one(
          from(row in schema,
            where: row.id in ^ids and row.project_id != ^project_id,
            select: {row.id, row.project_id},
            limit: 1
          )
        )

      if is_nil(conflict),
        do: {:cont, :ok},
        else: {:halt, {:error, {:project_snapshot_root_ownership_conflict, type, conflict}}}
    end)
  end

  defp validate_block_ownership(blocks) do
    expected = Map.new(blocks, &{&1["original_id"], &1["__restore_owner_sheet_id"]})
    ids = Map.keys(expected)

    conflict =
      from(block in Block, where: block.id in ^ids, select: {block.id, block.sheet_id})
      |> Repo.all()
      |> Enum.find(fn {block_id, sheet_id} -> expected[block_id] != sheet_id end)

    if is_nil(conflict),
      do: :ok,
      else: {:error, {:project_snapshot_block_ownership_conflict, conflict}}
  end

  defp validate_main_flow_conflicts(project_id, plan) do
    case target_main_flow_id(plan.entries.flows) do
      nil ->
        :ok

      target_main_id ->
        conflict_ids =
          Repo.all(
            from(flow in Flow,
              where:
                flow.project_id == ^project_id and flow.is_main == true and not is_nil(flow.deleted_at) and
                  flow.id != ^target_main_id,
              order_by: [asc: flow.id],
              select: flow.id
            )
          )

        if conflict_ids == [] do
          :ok
        else
          {:error, {:project_snapshot_main_flow_conflict_in_trash, target_main_id, conflict_ids}}
        end
    end
  end

  defp target_main_flow_id(flow_entries) do
    Enum.find_value(flow_entries, fn entry ->
      if entry["snapshot"]["is_main"] == true, do: entry["id"]
    end)
  end

  defp validate_current_only_flow_cross_project_callers(project_id, plan) do
    current_only_flow_ids = current_only_flow_ids(project_id, plan.ids.flows)

    conflicts =
      if current_only_flow_ids == [] do
        []
      else
        referenced_flow_ids = Enum.map(current_only_flow_ids, &Integer.to_string/1)
        flow_id_by_string = Map.new(current_only_flow_ids, &{Integer.to_string(&1), &1})

        from(node in FlowNode,
          join: source_flow in Flow,
          on: source_flow.id == node.flow_id,
          where: source_flow.project_id != ^project_id,
          where: fragment("?->>'referenced_flow_id'", node.data) in ^referenced_flow_ids,
          order_by: [asc: source_flow.project_id, asc: source_flow.id, asc: node.id],
          select:
            {node.id, source_flow.id, source_flow.project_id, node.deleted_at,
             fragment("?->>'referenced_flow_id'", node.data)}
        )
        |> Repo.all()
        |> Enum.map(fn {node_id, source_flow_id, source_project_id, deleted_at, referenced_flow_id} ->
          %{
            node_id: node_id,
            source_flow_id: source_flow_id,
            source_project_id: source_project_id,
            referenced_flow_id: Map.fetch!(flow_id_by_string, referenced_flow_id),
            source_in_trash: not is_nil(deleted_at)
          }
        end)
      end

    if conflicts == [] do
      :ok
    else
      {:error, {:project_snapshot_cross_project_flow_reference_conflict, conflicts}}
    end
  end

  defp current_only_flow_ids(project_id, target_flow_ids) do
    target_flow_ids = MapSet.to_list(target_flow_ids)

    query =
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [asc: flow.id],
        select: flow.id
      )

    if target_flow_ids == [],
      do: Repo.all(query),
      else: Repo.all(from(flow in query, where: flow.id not in ^target_flow_ids))
  end

  defp reconcile_roots(project_id, plan) do
    now = TimeHelpers.now()

    Enum.reduce_while(@entity_specs, {:ok, %{}}, fn {type, %{schema: schema}}, {:ok, removed} ->
      target_ids = MapSet.to_list(plan.ids[type])
      entries = plan.entries[type]

      with {:ok, removed_count} <- soft_delete_absent_roots(schema, project_id, target_ids, now),
           :ok <- neutralize_existing_roots(schema, project_id, target_ids, now),
           :ok <- insert_missing_roots(schema, project_id, entries, now) do
        {:cont, {:ok, Map.put(removed, type, removed_count)}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp soft_delete_absent_roots(Flow, project_id, target_ids, now) do
    query =
      from(flow in Flow,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [asc: flow.id],
        lock: "FOR UPDATE"
      )

    flows =
      if target_ids == [],
        do: Repo.all(query),
        else: Repo.all(from(flow in query, where: flow.id not in ^target_ids))

    Enum.reduce_while(flows, {:ok, 0}, fn flow, {:ok, count} ->
      case soft_delete_absent_flow(flow, now) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp soft_delete_absent_roots(schema, project_id, target_ids, now) do
    query =
      from(row in schema,
        where: row.project_id == ^project_id and is_nil(row.deleted_at)
      )

    query =
      if target_ids == [],
        do: query,
        else: from(row in query, where: row.id not in ^target_ids)

    {count, _rows} =
      Repo.update_all(query,
        set: [deleted_at: now, updated_at: now]
      )

    {:ok, count}
  end

  defp soft_delete_absent_flow(flow, now) do
    case flow
         |> Ecto.Changeset.change(%{deleted_at: now})
         |> Repo.update() do
      {:ok, deleted_flow} ->
        case Flows.sweep_project_flow_references(flow.project_id, flow.id) do
          {:ok, _swept_count} ->
            neutralize_soft_deleted_flow(deleted_flow, now)

          {:error, reason} ->
            {:error, {:project_snapshot_flow_reference_sweep_failed, flow.id, reason}}
        end

      {:error, reason} ->
        {:error, {:project_snapshot_flow_soft_delete_failed, flow.id, reason}}
    end
  end

  defp neutralize_soft_deleted_flow(flow, now) do
    case Repo.update_all(
           from(current in Flow, where: current.id == ^flow.id),
           set: [is_main: false, updated_at: now]
         ) do
      {1, _rows} ->
        :ok

      {updated_count, _rows} ->
        {:error, {:project_snapshot_flow_soft_delete_count_mismatch, flow.id, updated_count}}
    end
  end

  defp neutralize_existing_roots(Flow, _project_id, target_ids, now) do
    update_target_flow_roots(target_ids, now)
  end

  defp neutralize_existing_roots(schema, _project_id, target_ids, now), do: update_target_roots(schema, target_ids, now)

  defp update_target_roots(_schema, [], _now), do: :ok

  defp update_target_roots(schema, target_ids, now) do
    Repo.update_all(
      from(row in schema, where: row.id in ^target_ids),
      set: [
        deleted_at: nil,
        parent_id: nil,
        position: 0,
        shortcut: nil,
        updated_at: now
      ]
    )

    :ok
  end

  defp update_target_flow_roots([], _now), do: :ok

  defp update_target_flow_roots(target_ids, now) do
    Repo.update_all(
      from(flow in Flow, where: flow.id in ^target_ids),
      set: [
        deleted_at: nil,
        parent_id: nil,
        position: 0,
        shortcut: nil,
        is_main: false,
        updated_at: now
      ]
    )

    :ok
  end

  defp insert_missing_roots(schema, project_id, entries, now) do
    existing_ids =
      from(row in schema,
        where: row.id in ^Enum.map(entries, & &1["id"]),
        select: row.id
      )
      |> Repo.all()
      |> MapSet.new()

    entries
    |> Enum.reject(&MapSet.member?(existing_ids, &1["id"]))
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      case insert_root(schema, project_id, entry, now) do
        {:ok, _root} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:project_snapshot_root_insert_failed, schema, entry["id"], reason}}}
      end
    end)
  end

  defp insert_root(Sheet, project_id, entry, now) do
    snapshot = entry["snapshot"]

    %Sheet{
      id: entry["id"],
      project_id: project_id,
      name: snapshot["name"],
      shortcut: nil,
      description: snapshot["description"],
      color: snapshot["color"],
      position: 0,
      hidden_inherited_block_ids: [],
      inserted_at: now,
      updated_at: now
    }
    |> Ecto.Changeset.change()
    |> Repo.insert()
  end

  defp insert_root(Flow, project_id, entry, now) do
    snapshot = entry["snapshot"]

    %Flow{
      id: entry["id"],
      project_id: project_id,
      name: snapshot["name"],
      shortcut: nil,
      description: snapshot["description"],
      position: 0,
      is_main: false,
      settings: %{},
      inserted_at: now,
      updated_at: now
    }
    |> Ecto.Changeset.change()
    |> Repo.insert()
  end

  defp insert_root(Scene, project_id, entry, now) do
    snapshot = entry["snapshot"]

    %Scene{
      id: entry["id"],
      project_id: project_id,
      name: snapshot["name"],
      shortcut: nil,
      description: snapshot["description"],
      width: snapshot["width"],
      height: snapshot["height"],
      position: 0,
      inserted_at: now,
      updated_at: now
    }
    |> Ecto.Changeset.change()
    |> Repo.insert()
  end

  defp reconcile_sheet_blocks(plan) do
    sheet_ids = MapSet.to_list(plan.ids.sheets)
    target_ids = Enum.map(plan.blocks, & &1["original_id"])
    now = TimeHelpers.now()

    if sheet_ids != [] do
      absent_query =
        from(block in Block,
          where: block.sheet_id in ^sheet_ids and is_nil(block.deleted_at)
        )

      absent_query =
        if target_ids == [],
          do: absent_query,
          else: from(block in absent_query, where: block.id not in ^target_ids)

      Repo.update_all(absent_query, set: [deleted_at: now, updated_at: now])
    end

    if target_ids != [] do
      Repo.update_all(
        from(block in Block, where: block.id in ^target_ids),
        set: [
          deleted_at: nil,
          inherited_from_block_id: nil,
          variable_name: nil,
          updated_at: now
        ]
      )
    end

    insert_missing_blocks(plan.blocks, now)
  end

  defp insert_missing_blocks(blocks, now) do
    ids = Enum.map(blocks, & &1["original_id"])
    existing = from(block in Block, where: block.id in ^ids, select: block.id) |> Repo.all() |> MapSet.new()

    blocks
    |> Enum.reject(&MapSet.member?(existing, &1["original_id"]))
    |> Enum.reduce_while(:ok, &insert_missing_block(&1, &2, now))
  end

  defp insert_missing_block(block, :ok, now) do
    attrs = missing_block_attrs(block, now)

    case Repo.insert(Ecto.Changeset.change(struct(Block, attrs))) do
      {:ok, _block} ->
        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, {:project_snapshot_block_insert_failed, block["original_id"], reason}}}
    end
  end

  defp missing_block_attrs(block, now) do
    %{
      id: block["original_id"],
      sheet_id: block["__restore_owner_sheet_id"],
      type: block["type"],
      position: block["position"],
      config: block["config"] || %{},
      value: block["value"] || %{},
      is_constant: block["is_constant"] || false,
      variable_name: nil,
      scope: block["scope"] || "self",
      inherited_from_block_id: nil,
      detached: block["detached"] || false,
      required: block["required"] || false,
      column_group_id: block["column_group_id"],
      column_index: block["column_index"] || 0,
      word_count: 0,
      deleted_at: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  defp apply_entity_tree(_schema, _project_id, []), do: :ok

  defp apply_entity_tree(schema, project_id, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      {count, _rows} =
        Repo.update_all(
          from(row in schema,
            where:
              row.id == ^entry["id"] and row.project_id == ^project_id and
                is_nil(row.deleted_at)
          ),
          set: [parent_id: entry["parent_id"], position: entry["position"]]
        )

      if count == 1,
        do: {:cont, :ok},
        else: {:halt, {:error, {:project_snapshot_tree_update_failed, schema, entry["id"], count}}}
    end)
  end
end

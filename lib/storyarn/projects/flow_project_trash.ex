defmodule Storyarn.Projects.FlowProjectTrash do
  @moduledoc "Project-owned Flow trash lifecycle and exact replacement support."

  import Ecto.Query, warn: false

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Projects.FlowEntityTrashReferences
  alias Storyarn.Projects.FlowLocalizationProjection
  alias Storyarn.Projects.FlowReferenceIntegrity
  alias Storyarn.Projects.Persistence.FlowEntityTrashReferenceRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @restore_sources_locked_event [
    :storyarn,
    :projects,
    :flow_restore,
    :sources_locked
  ]

  @trash_reference_target_fields [
    :target_sheet_id,
    :target_asset_id,
    :target_flow_id,
    :target_flow_node_id,
    :target_sheet_avatar_id
  ]

  @doc "Restores a Flow through the Project-owned lifecycle boundary."
  @spec restore(pos_integer(), pos_integer()) :: {:ok, FlowRecord.t()} | {:error, term()}
  def restore(project_id, flow_id)
      when is_integer(project_id) and project_id > 0 and is_integer(flow_id) and flow_id > 0 do
    restore(project_id, flow_id, &FlowLocalizationProjection.extract_flow_nodes/1)
  end

  def restore(_project_id, _flow_id), do: {:error, :flow_not_found}

  @doc false
  def restore(project_id, flow_id, extract_flow_nodes)
      when is_integer(project_id) and project_id > 0 and is_integer(flow_id) and flow_id > 0 and
             is_function(extract_flow_nodes, 1) do
    result =
      Repo.transaction(fn ->
        restored_flow = restore_flow_transaction(project_id, flow_id)
        extract_restored_flow!(restored_flow, extract_flow_nodes)
      end)

    broadcast_restored_flow(result, project_id)
  end

  def restore(_project_id, _flow_id, _extract_flow_nodes), do: {:error, :flow_not_found}

  defp extract_restored_flow!(restored_flow, extract_flow_nodes) do
    case extract_flow_nodes.(restored_flow.id) do
      :ok -> restored_flow
      {:error, reason} -> Repo.rollback(reason)
      unexpected -> Repo.rollback({:unexpected_localization_extraction_result, unexpected})
    end
  end

  defp broadcast_restored_flow({:ok, _restored_flow} = result, project_id) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_restored_flow(error, _project_id), do: error

  def delete_subtree_in_transaction(%FlowRecord{} = flow) do
    case FlowReferenceIntegrity.lock_active_flow_for_write(flow) do
      {:ok, %{flow: locked_flow}} ->
        affected_flow_ids =
          FlowEntityTrashReferences.list_affected_flow_ids(
            locked_flow.project_id,
            locked_flow.id
          )

        case FlowEntityTrashReferences.sweep_project_flow_references(
               locked_flow.project_id,
               locked_flow.id
             ) do
          {:ok, _swept_count} ->
            locked_flow
            |> soft_delete_locked_without_global_sweep()
            |> Map.put(:affected_flow_ids, affected_flow_ids)

          {:error, reason} ->
            Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  def hard_delete(%FlowRecord{} = flow) do
    Repo.transaction(fn ->
      project_id =
        Repo.one(from(candidate in FlowRecord, where: candidate.id == ^flow.id, select: candidate.project_id)) ||
          Repo.rollback(:flow_not_found)

      case Repo.one(
             from(project in Project, where: project.id == ^project_id and is_nil(project.deleted_at), lock: "FOR UPDATE")
           ) do
        nil -> Repo.rollback(:project_not_active)
        %Project{} -> :ok
      end

      locked_flow =
        Repo.one(
          from(candidate in FlowRecord,
            where: candidate.id == ^flow.id and candidate.project_id == ^project_id,
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:flow_not_found)

      node_ids = Repo.all(from(node in FlowNodeRecord, where: node.flow_id == ^locked_flow.id, select: node.id))
      FlowLocalizationProjection.purge_texts_for_sources("flow_node", node_ids)

      case Repo.delete(locked_flow) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Permanently deletes a trashed Flow scoped to its Project."
  def hard_delete(project_id, flow_id)
      when is_integer(project_id) and project_id > 0 and is_integer(flow_id) and flow_id > 0 do
    case Repo.one(
           from(flow in FlowRecord,
             where: flow.id == ^flow_id and flow.project_id == ^project_id
           )
         ) do
      %FlowRecord{} = flow -> hard_delete(flow)
      nil -> {:error, :flow_not_found}
    end
  end

  def hard_delete(_project_id, _flow_id), do: {:error, :flow_not_found}

  defp restore_flow_transaction(project_id, flow_id) do
    lock_restore_project!(project_id)
    locked_flow = lock_deleted_flow!(flow_id, project_id)
    restored_nodes = lock_flow_nodes_for_restore(flow_id)
    trash_refs = lock_flow_trash_refs(flow_id)

    with :ok <- validate_no_pending_node_trash_refs(restored_nodes),
         :ok <- validate_flow_trash_refs(trash_refs),
         :ok <-
           Assets.lock_active_asset_references_for_restore(project_id,
             flow_node_ids: Enum.map(restored_nodes, & &1.id)
           ),
         {:ok, source_nodes} <-
           lock_flow_trash_source_rows(trash_refs, project_id, flow_id),
         :ok <- emit_restore_sources_locked(flow_id, trash_refs, source_nodes),
         changeset = flow_restore_changeset(locked_flow),
         :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           FlowReferenceIntegrity.lock_flow_parent(
             project_id,
             locked_flow.id,
             locked_flow.parent_id
           ),
         {:ok, scene_id} <-
           FlowReferenceIntegrity.lock_flow_scene(project_id, locked_flow.scene_id),
         {:ok, restored_flow} <-
           changeset
           |> Ecto.Changeset.put_change(:parent_id, parent_id)
           |> Ecto.Changeset.put_change(:scene_id, scene_id)
           |> Ecto.Changeset.put_change(:deleted_at, nil)
           |> Repo.update(),
         {:ok, _restore_meta} <-
           FlowEntityTrashReferences.restore_locked_flow_refs(
             trash_refs,
             source_nodes,
             restored_flow.id
           ),
         :ok <- validate_restored_flow_nodes(restored_nodes, project_id),
         :ok <-
           validate_restored_flow_sources(
             source_nodes,
             restored_nodes,
             restored_flow,
             project_id
           ) do
      restored_flow
    else
      {:error, reason} -> Repo.rollback(flow_restore_error(locked_flow, reason))
    end
  end

  defp lock_restore_project!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and is_nil(project.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> Repo.rollback(:project_not_active)
      %Project{} -> :ok
    end
  end

  defp lock_deleted_flow!(flow_id, project_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.id == ^flow_id and flow.project_id == ^project_id and
            not is_nil(flow.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:flow_not_deleted)
  end

  defp lock_flow_nodes_for_restore(flow_id) do
    Repo.all(
      from(node in FlowNodeRecord,
        where: node.flow_id == ^flow_id and is_nil(node.deleted_at),
        order_by: [asc: node.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp validate_no_pending_node_trash_refs([]), do: :ok

  defp validate_no_pending_node_trash_refs(nodes) do
    node_by_id = Map.new(nodes, &{&1.id, &1})
    node_ids = Map.keys(node_by_id)

    pending_ref =
      from(ref in FlowEntityTrashReferenceRecord,
        where:
          ref.source_type == "flow_node" and
            ref.source_id in ^node_ids,
        order_by: [asc: ref.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Enum.find(fn ref ->
        case Map.fetch(node_by_id, ref.source_id) do
          {:ok, node} -> trash_ref_would_restore?(ref, node)
          :error -> false
        end
      end)

    case pending_ref do
      nil -> :ok
      ref -> {:error, {:invalid_project_reference, trash_ref_context(ref), trash_ref_target_id(ref)}}
    end
  end

  defp trash_ref_would_restore?(%FlowEntityTrashReferenceRecord{source_field: "data." <> key}, %FlowNodeRecord{data: data})
       when is_map(data), do: Map.get(data, key) == nil

  defp trash_ref_would_restore?(_ref, _node), do: true

  defp trash_ref_context(%FlowEntityTrashReferenceRecord{source_field: "data." <> key}) do
    case key do
      "speaker_sheet_id" -> :speaker_sheet_id
      "location_sheet_id" -> :location_sheet_id
      "referenced_flow_id" -> :referenced_flow_id
      "audio_asset_id" -> :audio_asset_id
      "avatar_id" -> :avatar_id
      _other -> {:flow_node_trash_reference, key}
    end
  end

  defp trash_ref_context(%FlowEntityTrashReferenceRecord{source_field: source_field}),
    do: {:flow_node_trash_reference, source_field}

  defp trash_ref_target_id(ref) do
    Enum.find_value(@trash_reference_target_fields, &Map.get(ref, &1))
  end

  defp lock_flow_trash_refs(flow_id) do
    Repo.all(
      from(ref in FlowEntityTrashReferenceRecord,
        where: ref.target_flow_id == ^flow_id,
        order_by: [asc: ref.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp validate_flow_trash_refs(refs) do
    case Enum.find(
           refs,
           &(&1.source_type != "flow_node" or
               &1.source_field != "data.referenced_flow_id")
         ) do
      nil -> :ok
      ref -> {:error, {:invalid_flow_trash_reference, ref.id}}
    end
  end

  defp lock_flow_trash_source_rows([], _project_id, _target_flow_id), do: {:ok, []}

  defp lock_flow_trash_source_rows(refs, project_id, target_flow_id) do
    source_ids = refs |> Enum.map(& &1.source_id) |> Enum.uniq() |> Enum.sort()

    source_flow_ids =
      from(node in FlowNodeRecord,
        where: node.id in ^source_ids,
        order_by: [asc: node.id],
        select: node.flow_id
      )
      |> Repo.all()
      |> Enum.uniq()
      |> Enum.sort()

    locked_flows =
      Repo.all(
        from(flow in FlowRecord,
          where: flow.id in ^source_flow_ids,
          order_by: [asc: flow.id],
          lock: "FOR UPDATE"
        )
      )

    locked_nodes =
      Repo.all(
        from(node in FlowNodeRecord,
          where: node.id in ^source_ids,
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    flow_by_id = Map.new(locked_flows, &{&1.id, &1})

    case Enum.find(locked_nodes, &invalid_locked_flow_source?(&1, flow_by_id, project_id)) do
      nil -> {:ok, locked_nodes}
      _foreign_source -> {:error, {:invalid_project_reference, :referenced_flow_id, target_flow_id}}
    end
  end

  defp invalid_locked_flow_source?(node, flow_by_id, project_id) do
    case Map.get(flow_by_id, node.flow_id) do
      %FlowRecord{project_id: ^project_id} -> false
      _missing_or_foreign -> true
    end
  end

  defp emit_restore_sources_locked(flow_id, refs, source_nodes) do
    :telemetry.execute(
      @restore_sources_locked_event,
      %{reference_count: length(refs), source_count: length(source_nodes)},
      %{flow_id: flow_id}
    )

    :ok
  end

  defp flow_restore_changeset(flow) do
    FlowRecord.update_changeset(flow, %{
      name: flow.name,
      shortcut: flow.shortcut,
      description: flow.description,
      is_main: flow.is_main,
      settings: flow.settings,
      parent_id: flow.parent_id,
      position: flow.position,
      scene_id: flow.scene_id
    })
  end

  defp validate_restore_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp validate_restore_changeset(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp validate_restored_flow_nodes(nodes, project_id) do
    with :ok <- validate_restored_flow_node_set(nodes) do
      normalize_restored_flow_nodes(nodes, project_id)
    end
  end

  defp validate_restored_flow_node_set(nodes) do
    entry_count = Enum.count(nodes, &(&1.type == "entry"))
    exit_count = Enum.count(nodes, &(&1.type == "exit"))

    cond do
      entry_count == 0 -> {:error, :entry_node_missing}
      entry_count > 1 -> {:error, :entry_node_exists}
      exit_count == 0 -> {:error, :exit_node_missing}
      true -> :ok
    end
  end

  defp validate_restored_flow_sources(source_nodes, restored_nodes, restored_flow, project_id) do
    restored_node_ids = MapSet.new(restored_nodes, & &1.id)
    source_nodes = Enum.map(source_nodes, &Repo.get!(FlowNodeRecord, &1.id))
    active_source_flow_ids = active_flow_ids_for_nodes(source_nodes)

    source_nodes
    |> Enum.filter(
      &restored_source_node?(
        &1,
        restored_node_ids,
        active_source_flow_ids,
        restored_flow.id
      )
    )
    |> normalize_restored_flow_nodes(project_id)
  end

  defp active_flow_ids_for_nodes(nodes) do
    flow_ids = nodes |> Enum.map(& &1.flow_id) |> Enum.uniq()

    FlowRecord
    |> where([flow], flow.id in ^flow_ids and is_nil(flow.deleted_at))
    |> select([flow], flow.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp restored_source_node?(source_node, restored_node_ids, active_source_flow_ids, restored_flow_id) do
    is_nil(source_node.deleted_at) and
      MapSet.member?(active_source_flow_ids, source_node.flow_id) and
      source_node.data["referenced_flow_id"] == restored_flow_id and
      not MapSet.member?(restored_node_ids, source_node.id)
  end

  defp normalize_restored_flow_nodes(nodes, project_id) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case normalize_restored_flow_node(node, project_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp normalize_restored_flow_node(node_hint, project_id) do
    node = Repo.get!(FlowNodeRecord, node_hint.id)

    changeset =
      FlowNodeRecord.update_changeset(node, %{
        type: node.type,
        data: node.data,
        parent_id: node.parent_id
      })

    type = Ecto.Changeset.get_field(changeset, :type)
    data = Ecto.Changeset.get_field(changeset, :data) || %{}
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    with :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           FlowReferenceIntegrity.lock_node_parent(node.flow_id, parent_id, node.id),
         {:ok, data} <-
           FlowReferenceIntegrity.lock_and_normalize_node_references(
             project_id,
             node.flow_id,
             type,
             data
           ),
         :ok <- validate_restored_node_identity(node, type, data),
         {:ok, normalized_node} <-
           changeset
           |> Ecto.Changeset.put_change(:parent_id, parent_id)
           |> Ecto.Changeset.put_change(:data, data)
           |> Repo.update() do
      rebuild_node_references(normalized_node, project_id)
    end
  end

  defp validate_restored_node_identity(node, "hub", data) do
    hub_id = data["hub_id"]

    cond do
      not is_binary(hub_id) or String.trim(hub_id) == "" ->
        {:error, :hub_id_required}

      hub_id_exists?(node.flow_id, hub_id, node.id) ->
        {:error, :hub_id_not_unique}

      true ->
        :ok
    end
  end

  defp validate_restored_node_identity(node, "entry", _data) do
    if Repo.exists?(
         from(other in FlowNodeRecord,
           where:
             other.flow_id == ^node.flow_id and other.id != ^node.id and
               other.type == "entry" and is_nil(other.deleted_at)
         )
       ) do
      {:error, :entry_node_exists}
    else
      :ok
    end
  end

  defp validate_restored_node_identity(_node, _type, _data), do: :ok

  defp hub_id_exists?(flow_id, hub_id, exclude_id) do
    Repo.exists?(
      from(node in FlowNodeRecord,
        where:
          node.flow_id == ^flow_id and node.type == "hub" and
            fragment("?->>'hub_id' = ?", node.data, ^hub_id) and
            node.id != ^exclude_id and is_nil(node.deleted_at)
      )
    )
  end

  defp rebuild_node_references(node, project_id) do
    with :ok <-
           normalize_reference_rebuild_result(
             References.update_flow_node_entity_references(
               node,
               project_id: project_id
             )
           ) do
      normalize_reference_rebuild_result(References.update_flow_node_variable_references(node))
    end
  end

  defp normalize_reference_rebuild_result(:ok), do: :ok
  defp normalize_reference_rebuild_result({:error, _reason} = error), do: error

  defp normalize_reference_rebuild_result(result), do: {:error, {:unexpected_reference_rebuild_result, result}}

  defp flow_restore_error(flow, :cyclic_parent) do
    flow_reference_changeset(flow, %{}, :cyclic_parent)
  end

  defp flow_restore_error(flow, {:invalid_project_reference, context, _value} = reason)
       when context in [:parent_id, :scene_id] do
    flow_reference_changeset(flow, %{}, reason)
  end

  defp flow_restore_error(_flow, reason), do: reason

  defp flow_reference_changeset(flow, attrs, reason) do
    changeset = FlowRecord.update_changeset(flow, attrs)

    {field, message} =
      case reason do
        {:invalid_project_reference, :scene_id, _value} ->
          {:scene_id, "map not found in project"}

        {:invalid_project_reference, :parent_id, _value} ->
          {:parent_id, "parent flow not found in project"}

        :cyclic_parent ->
          {:parent_id, "cannot create a circular hierarchy"}

        _other ->
          {:parent_id, "contains an invalid project reference"}
      end

    Ecto.Changeset.add_error(changeset, field, message)
  end

  defp soft_delete_descendants(project_id, parent_id) do
    children =
      Repo.all(
        from(flow in FlowRecord,
          where:
            flow.project_id == ^project_id and flow.parent_id == ^parent_id and
              is_nil(flow.deleted_at),
          order_by: [asc: flow.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.flat_map(children, fn child ->
      FlowLocalizationProjection.delete_flow_node_texts_for_flows([child.id])

      Repo.update_all(
        from(flow in FlowRecord, where: flow.id == ^child.id and is_nil(flow.deleted_at)),
        set: [deleted_at: TimeHelpers.now()]
      )

      case FlowEntityTrashReferences.sweep_flow_references(child.id) do
        {:ok, _swept_count} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      [child.id | soft_delete_descendants(project_id, child.id)]
    end)
  end

  defp soft_delete_locked_without_global_sweep(locked_flow) do
    FlowLocalizationProjection.delete_flow_node_texts_for_flows([locked_flow.id])
    deleted = soft_delete!(locked_flow)
    child_ids = soft_delete_descendants(locked_flow.project_id, locked_flow.id)

    %{entity: deleted, deleted_ids: [deleted.id | child_ids]}
  end

  defp soft_delete!(flow) do
    flow
    |> Ecto.Changeset.change(%{deleted_at: TimeHelpers.now()})
    |> Repo.update()
    |> case do
      {:ok, deleted} -> deleted
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end

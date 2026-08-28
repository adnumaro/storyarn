defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor.Commands.ItemCapacity
  alias Storyarn.Flows.Editor.Projections.ProjectRecord
  alias Storyarn.Flows.Editor.Queries.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.FlowTrash
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.References
  alias Storyarn.Flows.ShortcutGenerator
  alias Storyarn.Platform
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @restore_sources_locked_event [
    :storyarn,
    :flows,
    :flow_restore,
    :sources_locked
  ]

  defdelegate list_flows(project_id), to: Flows, as: :list
  defdelegate list_flows_tree(project_id), to: Flows, as: :list_tree
  defdelegate default_search_limit(), to: Flows
  defdelegate search_flows(project_id, query, opts \\ []), to: Flows, as: :search

  defdelegate search_flows_in_projects(project_ids, query, opts \\ []),
    to: Flows,
    as: :search_in_projects

  defdelegate search_flows_deep(project_id, query, opts \\ []),
    to: Flows,
    as: :search_deep

  defdelegate get_flow(project_id, flow_id), to: Flows, as: :get
  defdelegate get_flow_brief(project_id, flow_id), to: Flows, as: :get_brief
  def get_flow!(project_id, flow_id, _opts \\ []), do: Flows.get!(project_id, flow_id)
  defdelegate get_flow_including_deleted(project_id, flow_id), to: Flows, as: :get_including_deleted

  @doc """
  Creates a child flow and assigns it to a node's referenced_flow_id.
  Used by exit (flow_reference mode) and subflow nodes.
  Returns `{:ok, %{flow: flow, node: node}}` or `{:error, step, reason, changes}`.
  """
  def create_linked_flow(project, %Flow{} = parent_flow, %FlowNode{} = node) do
    create_linked_flow(project, parent_flow, node, [])
  end

  def create_linked_flow(%{user: %{id: actor_id}} = actor_scope, project, %Flow{} = parent_flow, %FlowNode{} = node)
      when is_integer(actor_id) and actor_id > 0 do
    create_linked_flow_for_actor(actor_scope, project, parent_flow, node, [])
  end

  def create_linked_flow(project, %Flow{} = parent_flow, %FlowNode{} = node, opts) when is_list(opts) do
    create_linked_flow_for_actor(nil, project, parent_flow, node, opts)
  end

  def create_linked_flow(%{user: %{id: actor_id}} = actor_scope, project, %Flow{} = parent_flow, %FlowNode{} = node, opts)
      when is_integer(actor_id) and actor_id > 0 and is_list(opts) do
    create_linked_flow_for_actor(actor_scope, project, parent_flow, node, opts)
  end

  defp create_linked_flow_for_actor(actor_scope, project, parent_flow, node, opts) do
    project_id = project_id!(project)
    name = opts[:name] || derive_linked_flow_name(parent_flow, node)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:source, fn _repo, _changes ->
        lock_linked_flow_source(project_id, parent_flow, node)
      end)
      |> Ecto.Multi.run(:flow, fn _repo, _ ->
        create_linked_flow_record(project_id, parent_flow, name)
      end)
      |> Ecto.Multi.run(:node, fn _repo, %{flow: new_flow, source: %{node: locked_node}} ->
        link_node_to_new_flow(locked_node, new_flow)
      end)

    multi =
      case actor_scope do
        %{user: %{id: actor_id}} when is_integer(actor_id) and actor_id > 0 ->
          Ecto.Multi.run(multi, :notification, fn _repo, %{flow: flow} ->
            Platform.deliver_content_activity(actor_scope, project_id, :created, "flow", flow)
          end)

        nil ->
          multi
      end

    result =
      multi
      |> Repo.transaction()
      |> case do
        {:error, :flow, {:limit_reached, details}, _changes} ->
          {:error, :limit_reached, details}

        result ->
          result
      end

    publish_linked_flow_notification(result)

    result
    |> strip_linked_flow_notification()
    |> broadcast_flow_dashboard_result(project_id)
  end

  defp lock_linked_flow_source(project_id, parent_flow, node) do
    with {:ok, %{flow: locked_parent}} <-
           References.lock_active_flow_for_write(parent_flow),
         true <- locked_parent.project_id == project_id,
         {:ok, %{node: locked_node}} <-
           References.lock_active_node_for_write(node),
         true <- locked_node.flow_id == locked_parent.id do
      {:ok, %{parent: locked_parent, node: locked_node}}
    else
      false -> {:error, :source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_linked_flow_record(project_id, parent_flow, name) do
    case do_create_flow(project_id, %{name: name, parent_id: parent_flow.id}) do
      {:ok, flow} -> {:ok, flow}
      {:error, :limit_reached, details} -> {:error, {:limit_reached, details}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp link_node_to_new_flow(locked_node, new_flow) do
    new_data =
      locked_node.data
      |> Map.put("referenced_flow_id", new_flow.id)
      |> maybe_put_flow_reference_mode(locked_node.type)

    # The surrounding Ecto.Multi owns the commit and the single dashboard
    # invalidation. Publishing from this nested write would notify subscribers
    # before the outer transaction commits and duplicate the final event.
    case NodeCrud.update_node_data_without_dashboard_broadcast(locked_node, new_data) do
      {:ok, updated_node, _meta} -> {:ok, updated_node}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_flow_reference_mode(data, "exit"), do: Map.put(data, "exit_mode", "flow_reference")
  defp maybe_put_flow_reference_mode(data, _node_type), do: data

  defp derive_linked_flow_name(parent_flow, node) do
    label = node.data["label"]
    if label && label != "", do: label, else: "#{parent_flow.name} - Sub"
  end

  def create_flow(%{user: %{id: actor_id}} = actor_scope, project, attrs) when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)

    result =
      fn ->
        flow = create_flow_in_transaction(project_id, attrs)
        {flow, deliver_content_activity!(actor_scope, project_id, :created, flow)}
      end
      |> Repo.transaction()
      |> normalize_item_limit_result()

    case result do
      {:ok, {flow, notification_outcome}} ->
        Platform.publish_notification_delivery(notification_outcome)
        Collaboration.broadcast_dashboard_change(project_id, :flows)
        {:ok, flow}

      other ->
        other
    end
  end

  def create_flow(project, attrs) do
    project_id = project_id!(project)

    project
    |> do_create_flow(attrs)
    |> broadcast_flow_dashboard_result(project_id)
  end

  defp do_create_flow(project, attrs) do
    fn -> create_flow_in_transaction(project, attrs) end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  @doc false
  def create_flow_in_transaction(project, attrs) do
    project_id = project_id!(project)

    locked_project =
      Repo.one!(
        from candidate in ProjectRecord,
          where: candidate.id == ^project_id,
          lock: "FOR UPDATE"
      )

    if not is_nil(locked_project.deleted_at),
      do: Repo.rollback(:project_not_active)

    # A flow consumes quota for the flow plus its entry and exit nodes.
    case ItemCapacity.can_create_items?(locked_project, 3) do
      :ok -> :ok
      {:error, reason, details} -> Repo.rollback({reason, details})
    end

    attrs = stringify_keys(attrs)
    attrs = maybe_generate_shortcut(attrs, locked_project.id, nil)

    with {:ok, parent_id} <-
           References.lock_flow_parent(locked_project.id, nil, attrs["parent_id"]),
         {:ok, scene_id} <-
           References.lock_flow_scene(locked_project.id, attrs["scene_id"]) do
      attrs =
        attrs
        |> Map.put("parent_id", parent_id)
        |> Map.put("scene_id", scene_id)
        |> maybe_assign_position(locked_project.id, parent_id)

      insert_flow_with_default_nodes(locked_project.id, attrs)
    else
      {:error, reason} ->
        Repo.rollback(flow_reference_changeset(%Flow{project_id: locked_project.id}, attrs, reason))
    end
  end

  @doc false
  def create_flow_in_transaction(%{user: %{id: actor_id}} = actor_scope, project, attrs)
      when is_integer(actor_id) and actor_id > 0 do
    project_id = project_id!(project)
    flow = create_flow_in_transaction(project, attrs)
    {flow, deliver_content_activity!(actor_scope, project_id, :created, flow)}
  end

  defp insert_flow_with_default_nodes(project_id, attrs) do
    case %Flow{project_id: project_id}
         |> Flow.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, flow} ->
        insert_default_node!(flow.id, "entry", 100.0, 300.0, NodeTypes.default_data("entry"))
        insert_default_node!(flow.id, "exit", 500.0, 300.0, NodeTypes.default_data("exit"))
        flow

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp normalize_item_limit_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_item_limit_result(result), do: result

  def update_flow(%Flow{} = flow, attrs) do
    fn -> update_flow_transaction(flow, attrs) end
    |> Repo.transaction()
    |> broadcast_flow_dashboard_result(flow.project_id)
  end

  defp update_flow_transaction(flow, attrs) do
    case References.lock_active_flow_for_write(flow) do
      {:ok, %{flow: locked_flow, project_id: project_id}} ->
        update_locked_flow(locked_flow, project_id, attrs)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp update_locked_flow(locked_flow, project_id, attrs) do
    attrs = maybe_generate_shortcut_on_update(locked_flow, attrs)
    changeset = Flow.update_changeset(locked_flow, attrs)
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)
    scene_id = Ecto.Changeset.get_field(changeset, :scene_id)

    with {:ok, parent_id} <-
           References.lock_flow_parent(project_id, locked_flow.id, parent_id),
         {:ok, scene_id} <-
           References.lock_flow_scene(project_id, scene_id) do
      changeset
      |> Ecto.Changeset.put_change(:parent_id, parent_id)
      |> Ecto.Changeset.put_change(:scene_id, scene_id)
      |> update_flow_or_rollback()
    else
      {:error, reason} ->
        Repo.rollback(flow_reference_changeset(locked_flow, attrs, reason))
    end
  end

  defp update_flow_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, updated_flow} -> updated_flow
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp flow_reference_changeset(flow, attrs, reason) do
    changeset =
      if flow.id do
        Flow.update_changeset(flow, attrs)
      else
        Flow.create_changeset(flow, attrs)
      end

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

  defp insert_default_node!(flow_id, type, x, y, data) do
    case %FlowNode{flow_id: flow_id}
         |> FlowNode.create_changeset(%{type: type, position_x: x, position_y: y, data: data})
         |> Repo.insert() do
      {:ok, _} -> :ok
      {:error, cs} -> Repo.rollback(cs)
    end
  end

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children recursively.

  Inbound refs (`flow_nodes.data["referenced_flow_id"]` from subflow + exit
  nodes) are swept to the Flow-owned entity trash refs table for the root and
  every cascade-soft-deleted descendant.
  """
  def delete_flow(%Flow{} = flow) do
    with {:ok, %{entity: entity}} <- delete_flow_subtree(flow), do: {:ok, entity}
  end

  def delete_flow(%{user: %{id: actor_id}} = actor_scope, %Flow{} = flow) when is_integer(actor_id) and actor_id > 0 do
    with {:ok, %{entity: entity}} <- delete_flow_subtree(actor_scope, flow), do: {:ok, entity}
  end

  @doc """
  Same soft-delete as `delete_flow/1`, additionally returning `deleted_ids` —
  the committed cascade set, collected by the deletion itself under the same
  lock. Callers that broadcast about the deletion MUST use these ids: a
  separate pre-delete traversal can desync from concurrent tree changes.
  """
  def delete_flow_subtree(%Flow{} = flow) do
    result =
      Repo.transaction(fn -> delete_flow_subtree_in_transaction(flow) end)

    case result do
      {:ok, %{entity: deleted_flow, affected_flow_ids: affected_flow_ids}} ->
        # Notify open canvases that have subflow nodes referencing this flow
        broadcast_flow_refreshes(affected_flow_ids)
        Collaboration.broadcast_dashboard_change(deleted_flow.project_id, :flows)

      _ ->
        :ok
    end

    result
  end

  def delete_flow_subtree(%{user: %{id: actor_id}} = actor_scope, %Flow{} = flow)
      when is_integer(actor_id) and actor_id > 0 do
    result = Repo.transaction(fn -> delete_flow_subtree_in_transaction(actor_scope, flow) end)

    case result do
      {:ok,
       %{
         entity: deleted_flow,
         affected_flow_ids: affected_flow_ids,
         notification_outcome: notification_outcome
       } = deleted} ->
        Platform.publish_notification_delivery(notification_outcome)
        broadcast_flow_refreshes(affected_flow_ids)
        Collaboration.broadcast_dashboard_change(deleted_flow.project_id, :flows)
        {:ok, Map.delete(deleted, :notification_outcome)}

      _ ->
        result
    end
  end

  @doc false
  def delete_flow_subtree_in_transaction(%Flow{} = flow) do
    delete_flow_transaction(flow)
  end

  @doc false
  def delete_flow_subtree_in_transaction(%{user: %{id: actor_id}} = actor_scope, %Flow{} = flow)
      when is_integer(actor_id) and actor_id > 0 do
    deleted = delete_flow_subtree_in_transaction(flow)

    outcome =
      deliver_content_activity!(
        actor_scope,
        deleted.entity.project_id,
        :deleted,
        deleted.entity
      )

    Map.put(deleted, :notification_outcome, outcome)
  end

  @doc false
  def delete_flow_subtree_by_id_in_transaction(%{user: %{id: actor_id}} = actor_scope, project_id, flow_id)
      when is_integer(actor_id) and actor_id > 0 do
    case get_flow_brief(project_id, flow_id) do
      %Flow{} = flow -> delete_flow_subtree_in_transaction(actor_scope, flow)
      nil -> Repo.rollback(:not_found)
    end
  end

  defp delete_flow_transaction(flow) do
    case References.lock_active_flow_for_write(flow) do
      {:ok, %{flow: locked_flow}} ->
        affected_flow_ids =
          locked_flow.id
          |> NodeCrud.list_subflow_nodes_referencing(locked_flow.project_id)
          |> Enum.map(& &1.flow_id)
          |> Enum.uniq()

        locked_flow
        |> soft_delete_locked_flow()
        |> Map.put(:affected_flow_ids, affected_flow_ids)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp soft_delete_locked_flow(locked_flow) do
    Localization.delete_flow_node_texts_for_flows([locked_flow.id])

    case soft_delete_flow_and_sweep_references(locked_flow) do
      {:ok, deleted_flow} ->
        child_ids =
          FlowTrash.soft_delete_descendants(locked_flow.project_id, locked_flow.id)

        %{entity: deleted_flow, deleted_ids: [deleted_flow.id | child_ids]}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp soft_delete_flow_and_sweep_references(flow) do
    with {:ok, deleted_flow} <-
           flow
           |> Ecto.Changeset.change(%{deleted_at: TimeHelpers.now()})
           |> Repo.update(),
         {:ok, _swept_count} <-
           References.sweep_trash_jsonb_field(
             FlowNode,
             "flow_node",
             :data,
             "referenced_flow_id",
             :flow,
             deleted_flow.id
           ) do
      {:ok, deleted_flow}
    end
  end

  @doc """
  Permanently deletes a flow from the database.
  Use with caution - this cannot be undone.
  """
  def hard_delete_flow(%Flow{} = flow) do
    fn ->
      project_id =
        Repo.one(from(candidate in Flow, where: candidate.id == ^flow.id, select: candidate.project_id)) ||
          Repo.rollback(:flow_not_found)

      lock_restore_project!(project_id)

      locked_flow =
        Repo.one(
          from(candidate in Flow,
            where: candidate.id == ^flow.id and candidate.project_id == ^project_id,
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:flow_not_found)

      node_ids = Repo.all(from(n in FlowNode, where: n.flow_id == ^locked_flow.id, select: n.id))
      Localization.purge_texts_for_sources("flow_node", node_ids)

      case Repo.delete(locked_flow) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> broadcast_flow_dashboard_result(flow.project_id)
  end

  @doc """
  Restores a soft-deleted flow. Its hierarchy references and every pending
  `referenced_flow_id` reinjection are validated under the same project and
  flow locks used by active writers.
  """
  def restore_flow(%Flow{id: flow_id}) when is_integer(flow_id) do
    restore_flow_with_localization(%Flow{id: flow_id}, &Localization.extract_flow_nodes/1)
  end

  def restore_flow(_flow), do: {:error, :flow_not_found}

  @doc false
  def restore_flow(%Flow{id: flow_id}, extract_flow_nodes)
      when is_integer(flow_id) and is_function(extract_flow_nodes, 1) do
    restore_flow_with_localization(%Flow{id: flow_id}, extract_flow_nodes)
  end

  def restore_flow(_flow, _extract_flow_nodes), do: {:error, :flow_not_found}

  defp restore_flow_with_localization(%Flow{id: flow_id}, extract_flow_nodes) do
    result =
      Repo.transaction(fn ->
        restored_flow = restore_flow_transaction(flow_id)

        case extract_flow_nodes.(restored_flow.id) do
          :ok -> restored_flow
          {:error, reason} -> Repo.rollback(reason)
          unexpected -> Repo.rollback({:unexpected_localization_extraction_result, unexpected})
        end
      end)

    case result do
      {:ok, restored_flow} ->
        broadcast_flow_dashboard_result(result, restored_flow.project_id)

      _ ->
        result
    end
  end

  defp restore_flow_transaction(flow_id) do
    project_id =
      Repo.one(from(flow in Flow, where: flow.id == ^flow_id, select: flow.project_id)) ||
        Repo.rollback(:flow_not_found)

    lock_restore_project!(project_id)
    locked_flow = lock_deleted_flow!(flow_id, project_id)
    restored_nodes = lock_flow_nodes_for_restore(flow_id)
    trash_refs = lock_flow_trash_refs(flow_id)

    with :ok <- validate_no_pending_node_trash_refs(restored_nodes),
         :ok <- validate_flow_trash_refs(trash_refs),
         :ok <-
           References.lock_active_asset_references_for_restore(project_id,
             flow_node_ids: Enum.map(restored_nodes, & &1.id)
           ),
         {:ok, source_nodes} <-
           lock_flow_trash_source_rows(trash_refs, project_id, flow_id),
         :ok <- emit_restore_sources_locked(flow_id, trash_refs, source_nodes),
         changeset = flow_restore_changeset(locked_flow),
         :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           References.lock_flow_parent(
             project_id,
             locked_flow.id,
             locked_flow.parent_id
           ),
         {:ok, scene_id} <-
           References.lock_flow_scene(project_id, locked_flow.scene_id),
         {:ok, restored_flow} <-
           changeset
           |> Ecto.Changeset.put_change(:parent_id, parent_id)
           |> Ecto.Changeset.put_change(:scene_id, scene_id)
           |> Ecto.Changeset.put_change(:deleted_at, nil)
           |> Repo.update(),
         {:ok, _restore_meta} <-
           References.restore_locked_flow_refs(
             trash_refs,
             source_nodes,
             restored_flow.id
           ),
         :ok <-
           validate_restored_flow_nodes(
             restored_nodes,
             project_id
           ),
         :ok <-
           validate_restored_flow_sources(
             source_nodes,
             restored_nodes,
             restored_flow,
             project_id
           ) do
      restored_flow
    else
      {:error, reason} ->
        Repo.rollback(flow_restore_error(locked_flow, reason))
    end
  end

  defp lock_restore_project!(project_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id and is_nil(project.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      nil -> Repo.rollback(:project_not_active)
      %ProjectRecord{} -> :ok
    end
  end

  defp lock_deleted_flow!(flow_id, project_id) do
    Repo.one(
      from(flow in Flow,
        where:
          flow.id == ^flow_id and flow.project_id == ^project_id and
            not is_nil(flow.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:flow_not_deleted)
  end

  defp lock_flow_nodes_for_restore(flow_id) do
    Repo.all(
      from(node in FlowNode,
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
      from(ref in EntityTrashRef,
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
      nil ->
        :ok

      ref ->
        {:error, {:invalid_project_reference, trash_ref_context(ref), trash_ref_target_id(ref)}}
    end
  end

  defp trash_ref_would_restore?(%EntityTrashRef{source_field: "data." <> key}, %FlowNode{data: data}) when is_map(data) do
    Map.get(data, key) == nil
  end

  defp trash_ref_would_restore?(_ref, _node), do: true

  defp trash_ref_context(%EntityTrashRef{source_field: "data." <> key}) do
    case key do
      "speaker_sheet_id" -> :speaker_sheet_id
      "location_sheet_id" -> :location_sheet_id
      "referenced_flow_id" -> :referenced_flow_id
      "audio_asset_id" -> :audio_asset_id
      "avatar_id" -> :avatar_id
      _other -> {:flow_node_trash_reference, key}
    end
  end

  defp trash_ref_context(%EntityTrashRef{source_field: source_field}) do
    {:flow_node_trash_reference, source_field}
  end

  defp trash_ref_target_id(ref) do
    Enum.find_value(EntityTrashRef.target_fields(), &Map.get(ref, &1))
  end

  defp lock_flow_trash_refs(flow_id) do
    Repo.all(
      from(ref in EntityTrashRef,
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
    source_ids =
      refs
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Enum.sort()

    source_flow_ids =
      from(node in FlowNode,
        where: node.id in ^source_ids,
        order_by: [asc: node.id],
        select: node.flow_id
      )
      |> Repo.all()
      |> Enum.uniq()
      |> Enum.sort()

    locked_flows =
      Repo.all(
        from(flow in Flow,
          where: flow.id in ^source_flow_ids,
          order_by: [asc: flow.id],
          lock: "FOR UPDATE"
        )
      )

    locked_nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^source_ids,
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    flow_by_id = Map.new(locked_flows, &{&1.id, &1})

    case Enum.find(
           locked_nodes,
           &invalid_locked_flow_source?(&1, flow_by_id, project_id)
         ) do
      nil ->
        {:ok, locked_nodes}

      _foreign_source ->
        {:error, {:invalid_project_reference, :referenced_flow_id, target_flow_id}}
    end
  end

  defp invalid_locked_flow_source?(node, flow_by_id, project_id) do
    case Map.get(flow_by_id, node.flow_id) do
      %Flow{project_id: ^project_id} -> false
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
    Flow.update_changeset(flow, %{
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
    source_nodes = Enum.map(source_nodes, &Repo.get!(FlowNode, &1.id))
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

    Flow
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
      normalize_restored_flow_node_result(node, project_id)
    end)
  end

  defp normalize_restored_flow_node_result(node, project_id) do
    case normalize_restored_flow_node(node, project_id) do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp normalize_restored_flow_node(node_hint, project_id) do
    node = Repo.get!(FlowNode, node_hint.id)

    changeset =
      FlowNode.update_changeset(node, %{
        type: node.type,
        data: node.data,
        parent_id: node.parent_id
      })

    type = Ecto.Changeset.get_field(changeset, :type)
    data = Ecto.Changeset.get_field(changeset, :data) || %{}
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    with :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           References.lock_node_parent(node.flow_id, parent_id, node.id),
         {:ok, data} <-
           References.lock_and_normalize_node_references(
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

      NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) ->
        {:error, :hub_id_not_unique}

      true ->
        :ok
    end
  end

  defp validate_restored_node_identity(node, "entry", _data) do
    if Repo.exists?(
         from(other in FlowNode,
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

  defp rebuild_node_references(node, project_id) do
    with :ok <-
           normalize_reference_rebuild_result(
             References.update_entity_references(
               node,
               project_id: project_id
             )
           ) do
      normalize_reference_rebuild_result(References.update_variable_references(node))
    end
  end

  defp normalize_reference_rebuild_result(:ok), do: :ok
  defp normalize_reference_rebuild_result({:error, _reason} = error), do: error

  defp normalize_reference_rebuild_result(result) do
    {:error, {:unexpected_reference_rebuild_result, result}}
  end

  defp flow_restore_error(flow, :cyclic_parent) do
    flow_reference_changeset(flow, %{}, :cyclic_parent)
  end

  defp flow_restore_error(flow, {:invalid_project_reference, context, _value} = reason)
       when context in [:parent_id, :scene_id] do
    flow_reference_changeset(flow, %{}, reason)
  end

  defp flow_restore_error(_flow, reason), do: reason

  @doc """
  Lists all soft-deleted flows for a project (trash).
  """
  def list_deleted_flows(project_id), do: FlowTrash.list_deleted(project_id)

  @doc false
  def broadcast_flow_refreshes(affected_flow_ids) when is_list(affected_flow_ids) do
    Enum.each(affected_flow_ids, fn flow_id ->
      Collaboration.broadcast_change({:flow, flow_id}, :flow_refresh, %{
        user_id: 0,
        user_email: "System",
        user_color: "#666"
      })
    end)
  end

  @doc """
  Updates only the scene_id of a flow.
  Used to associate a flow with a map as its scene backdrop.
  Validates that the map belongs to the same project.
  """
  def update_flow_scene(%Flow{} = flow, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    fn ->
      with {:ok, %{flow: locked_flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow),
           {:ok, scene_id} <-
             References.lock_flow_scene(project_id, attrs["scene_id"]) do
        persist_flow_scene(locked_flow, project_id, scene_id)
      else
        {:error, :flow_not_found} ->
          Repo.rollback(:flow_not_found)

        {:error, reason} ->
          Repo.rollback(flow_reference_changeset(flow, attrs, reason))
      end
    end
    |> Repo.transaction()
    |> broadcast_flow_scene_result()
  end

  defp persist_flow_scene(locked_flow, project_id, scene_id) do
    changeset = Flow.scene_changeset(locked_flow, %{"scene_id" => scene_id})

    if map_size(changeset.changes) == 0 do
      {locked_flow, project_id, false}
    else
      {update_flow_or_rollback(changeset), project_id, true}
    end
  end

  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.update_changeset(flow, attrs)
  end

  def set_main_flow(%Flow{} = flow) do
    flow
    |> set_main_flow_transaction_result()
    |> broadcast_set_main_flow_result()
  end

  defp set_main_flow_transaction_result(flow) do
    Repo.transaction(fn -> set_main_flow_transaction(flow) end)
  end

  defp set_main_flow_transaction(flow) do
    case References.lock_active_flow_for_write(flow) do
      {:ok, %{project_id: project_id, flow: locked_flow}} ->
        {replace_main_flow(locked_flow, project_id), project_id}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp replace_main_flow(locked_flow, project_id) do
    Repo.update_all(
      from(candidate in Flow,
        where:
          candidate.project_id == ^project_id and
            candidate.id != ^locked_flow.id and
            candidate.is_main == true and is_nil(candidate.deleted_at)
      ),
      set: [is_main: false]
    )

    case locked_flow
         |> Ecto.Changeset.change(is_main: true)
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_flow_id) do
    attrs
    |> stringify_keys()
    |> ShortcutGenerator.prepare_create(project_id, exclude_flow_id)
  end

  defp maybe_generate_shortcut_on_update(%Flow{} = flow, attrs) do
    ShortcutGenerator.prepare_update(
      flow,
      attrs,
      fn -> References.count_entity_backlinks("flow", flow.id) > 0 end
    )
  end

  defp stringify_keys(map), do: MapAccess.stringify_keys(map)

  defp project_id!(%{id: project_id}), do: project_id!(project_id)
  defp project_id!(project_id) when is_integer(project_id) and project_id > 0, do: project_id

  defp project_id!(project) do
    raise ArgumentError, "expected a Flow project identity, got: #{inspect(project)}"
  end

  defp deliver_content_activity!(actor_scope, project_id, action, flow) do
    case Platform.deliver_content_activity(actor_scope, project_id, action, "flow", flow) do
      {:ok, outcome} -> outcome
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp publish_linked_flow_notification({:ok, %{notification: outcome}}) do
    Platform.publish_notification_delivery(outcome)
  end

  defp publish_linked_flow_notification(_result), do: :ok

  defp strip_linked_flow_notification({:ok, changes}) do
    {:ok, Map.delete(changes, :notification)}
  end

  defp strip_linked_flow_notification(result), do: result

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutGenerator.assign_position(attrs, project_id, parent_id)
  end

  defdelegate count_flows(project_id), to: Flows, as: :count
  defdelegate count_nodes_for_project(project_id), to: Flows, as: :count_nodes

  defp broadcast_flow_dashboard_result({:ok, _value} = result, project_id) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_flow_dashboard_result(result, _project_id), do: result

  defp broadcast_flow_scene_result({:ok, {flow, project_id, true}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, flow}
  end

  defp broadcast_flow_scene_result({:ok, {flow, _project_id, false}}), do: {:ok, flow}
  defp broadcast_flow_scene_result(result), do: result

  defp broadcast_set_main_flow_result({:ok, {flow, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, flow}
  end

  defp broadcast_set_main_flow_result(result), do: result
end

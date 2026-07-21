defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.EntityTrashRefs
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Flows.TreeOperations
  alias Storyarn.Localization
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.ImportHelpers
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Shared.ShortcutHelpers
  alias Storyarn.Shared.SoftDelete
  alias Storyarn.Shared.Trashable
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets
  alias Storyarn.Shortcuts

  @doc """
  Lists all non-deleted flows for a project.
  Returns flows ordered by is_main (descending) then name.
  """
  def list_flows(project_id) do
    Repo.all(
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        order_by: [desc: f.is_main, asc: f.name]
      )
    )
  end

  @doc """
  Lists flows as a tree structure.
  Returns root-level flows with their children preloaded (up to 5 levels deep).
  """
  def list_flows_tree(project_id) do
    all_flows =
      Repo.all(
        from(f in Flow,
          where: f.project_id == ^project_id and is_nil(f.deleted_at),
          order_by: [asc: f.position, asc: f.name]
        )
      )

    SharedTree.build_tree_from_flat_list(all_flows)
  end

  @default_search_limit 25

  @doc "Returns the default search limit used by search_flows/3 and search_flows_deep/3."
  def default_search_limit, do: @default_search_limit

  @doc """
  Searches flows by name or shortcut for reference selection.
  Excludes soft-deleted flows.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
    - `:exclude_id` - Flow ID to exclude from results (e.g., current flow)
  """
  def search_flows(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    exclude_id = Keyword.get(opts, :exclude_id)
    query_str = String.trim(query)

    base =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at)
      )

    base = maybe_exclude_flow(base, exclude_id)

    if query_str == "" do
      Repo.all(from(f in base, order_by: [desc: f.updated_at], limit: ^limit, offset: ^offset))
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(f in base,
          where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
          order_by: [asc: f.name],
          limit: ^limit,
          offset: ^offset
        )
      )
    end
  end

  defp maybe_exclude_flow(query, nil), do: query
  defp maybe_exclude_flow(query, id), do: from(f in query, where: f.id != ^id)

  @doc """
  Searches flows by name or shortcut across a pre-authorized set of projects.

  Callers OWN the authorization of `project_ids` (see `Storyarn.GlobalSearch`);
  this function never widens the set. Empty queries list the most recently
  updated flows — pickers browse before typing.
  """
  @spec search_flows_in_projects([integer()], String.t(), keyword()) :: [Flow.t()]
  def search_flows_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    query_str = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query_str == "" ->
        Repo.all(
          from(f in Flow,
            where: f.project_id in ^project_ids and is_nil(f.deleted_at),
            order_by: [desc: f.updated_at],
            limit: ^limit
          )
        )

      true ->
        search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

        Repo.all(
          from(f in Flow,
            where: f.project_id in ^project_ids and is_nil(f.deleted_at),
            where: ilike(f.name, ^search_term) or ilike(f.shortcut, ^search_term),
            order_by: [asc: f.name],
            limit: ^limit
          )
        )
    end
  end

  @doc """
  Deep search: searches flow names/shortcuts AND node content (dialogue text,
  labels, technical IDs, hub IDs, expressions, stage directions, menu text, locations).

  Uses JSONB text search on the flow_nodes.data column via a subquery.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
    - `:exclude_id` - Flow ID to exclude from results
  """
  def search_flows_deep(project_id, query, opts \\ []) when is_binary(query) do
    query_str = String.trim(query)

    if query_str == "" do
      search_flows(project_id, query_str, opts)
    else
      limit = Keyword.get(opts, :limit, @default_search_limit)
      offset = Keyword.get(opts, :offset, 0)
      exclude_id = Keyword.get(opts, :exclude_id)

      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where:
          ilike(f.name, ^search_term) or
            ilike(f.shortcut, ^search_term) or
            f.id in subquery(node_content_subquery(project_id, search_term)),
        order_by: [asc: f.name],
        limit: ^limit,
        offset: ^offset
      )
      |> maybe_exclude_flow(exclude_id)
      |> Repo.all()
    end
  end

  # Subquery matching node JSONB data fields against a search term.
  @searchable_jsonb_keys ~w(text label technical_id hub_id expression stage_directions menu_text location)
  defp node_content_subquery(project_id, search_term) do
    conditions =
      Enum.reduce(@searchable_jsonb_keys, dynamic(false), fn key, acc ->
        dynamic([n], ^acc or ilike(fragment("?->>?", n.data, ^key), ^search_term))
      end)

    from(n in FlowNode,
      join: fl in Flow,
      on: n.flow_id == fl.id,
      where: fl.project_id == ^project_id and is_nil(fl.deleted_at) and is_nil(n.deleted_at),
      where: ^conditions,
      select: n.flow_id
    )
  end

  def get_flow(project_id, flow_id) do
    active_nodes_query =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    Repo.one(
      from(f in Flow,
        where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
        preload: [:connections, nodes: ^active_nodes_query]
      )
    )
  end

  @doc """
  Gets a flow with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  def get_flow_brief(project_id, flow_id) do
    Repo.one(from(f in Flow, where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at)))
  end

  def get_flow!(project_id, flow_id, _opts \\ []) do
    active_nodes_query =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    Repo.one!(
      from(f in Flow,
        where: f.project_id == ^project_id and f.id == ^flow_id and is_nil(f.deleted_at),
        preload: [:connections, nodes: ^active_nodes_query]
      )
    )
  end

  @doc """
  Gets a flow including soft-deleted ones (for trash/restore).
  """
  def get_flow_including_deleted(project_id, flow_id) do
    Repo.one(from(f in Flow, where: f.project_id == ^project_id and f.id == ^flow_id, preload: [:nodes, :connections]))
  end

  @doc """
  Creates a child flow and assigns it to a node's referenced_flow_id.
  Used by exit (flow_reference mode) and subflow nodes.
  Returns `{:ok, %{flow: flow, node: node}}` or `{:error, step, reason, changes}`.
  """
  def create_linked_flow(%Project{} = project, %Flow{} = parent_flow, %FlowNode{} = node, opts \\ []) do
    name = opts[:name] || derive_linked_flow_name(parent_flow, node)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:source, fn _repo, _changes ->
      lock_linked_flow_source(project, parent_flow, node)
    end)
    |> Ecto.Multi.run(:flow, fn _repo, _ ->
      create_linked_flow_record(project, parent_flow, name)
    end)
    |> Ecto.Multi.run(:node, fn _repo, %{flow: new_flow, source: %{node: locked_node}} ->
      link_node_to_new_flow(locked_node, new_flow)
    end)
    |> Repo.transaction()
    |> case do
      {:error, :flow, {:limit_reached, details}, _changes} ->
        {:error, :limit_reached, details}

      result ->
        result
    end
    |> broadcast_flow_dashboard_result(project.id)
  end

  defp lock_linked_flow_source(project, parent_flow, node) do
    with {:ok, %{flow: locked_parent}} <-
           ReferenceIntegrity.lock_active_flow_for_write(parent_flow),
         true <- locked_parent.project_id == project.id,
         {:ok, %{node: locked_node}} <-
           ReferenceIntegrity.lock_active_node_for_write(node),
         true <- locked_node.flow_id == locked_parent.id do
      {:ok, %{parent: locked_parent, node: locked_node}}
    else
      false -> {:error, :source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_linked_flow_record(project, parent_flow, name) do
    case do_create_flow(project, %{name: name, parent_id: parent_flow.id}) do
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

    case NodeCrud.update_node_data(locked_node, new_data) do
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

  def create_flow(%Project{} = project, attrs) do
    project
    |> do_create_flow(attrs)
    |> broadcast_flow_dashboard_result(project.id)
  end

  defp do_create_flow(%Project{} = project, attrs) do
    fn ->
      locked_project = Repo.one!(from(p in Project, where: p.id == ^project.id, lock: "FOR UPDATE"))

      if not is_nil(locked_project.deleted_at),
        do: Repo.rollback(:project_not_active)

      # A flow consumes quota for the flow plus its entry and exit nodes.
      case Billing.can_create_items?(locked_project, 3) do
        :ok -> :ok
        {:error, reason, details} -> Repo.rollback({reason, details})
      end

      attrs = stringify_keys(attrs)
      attrs = maybe_generate_shortcut(attrs, project.id, nil)

      with {:ok, parent_id} <-
             ReferenceIntegrity.lock_flow_parent(project.id, nil, attrs["parent_id"]),
           {:ok, scene_id} <-
             ReferenceIntegrity.lock_flow_scene(project.id, attrs["scene_id"]) do
        attrs =
          attrs
          |> Map.put("parent_id", parent_id)
          |> Map.put("scene_id", scene_id)
          |> maybe_assign_position(project.id, parent_id)

        insert_flow_with_default_nodes(project.id, attrs)
      else
        {:error, reason} ->
          Repo.rollback(flow_reference_changeset(%Flow{project_id: project.id}, attrs, reason))
      end
    end
    |> Repo.transaction()
    |> normalize_item_limit_result()
  end

  defp insert_flow_with_default_nodes(project_id, attrs) do
    case %Flow{project_id: project_id}
         |> Flow.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, flow} ->
        insert_default_node!(flow.id, "entry", 100.0, 300.0, %{})
        insert_default_node!(flow.id, "exit", 500.0, 300.0, default_exit_data())
        flow

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp normalize_item_limit_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_item_limit_result(result), do: result

  def update_flow(%Flow{} = flow, attrs) do
    Repo.transaction(fn -> update_flow_transaction(flow, attrs) end)
  end

  defp update_flow_transaction(flow, attrs) do
    case ReferenceIntegrity.lock_active_flow_for_write(flow) do
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
           ReferenceIntegrity.lock_flow_parent(project_id, locked_flow.id, parent_id),
         {:ok, scene_id} <-
           ReferenceIntegrity.lock_flow_scene(project_id, scene_id) do
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

  defp default_exit_data do
    %{
      "label" => "",
      "technical_id" => "",
      "outcome_tags" => [],
      "outcome_color" => "#22c55e",
      "exit_mode" => "terminal",
      "referenced_flow_id" => nil
    }
  end

  @doc """
  Soft-deletes a flow by setting deleted_at.
  Also soft-deletes all children recursively.

  Inbound refs (`flow_nodes.data["referenced_flow_id"]` from subflow + exit
  nodes) are swept to the entity trash refs table via `Trashable.soft_delete/1`.
  Note: cascade-soft-deleted children do NOT get their own inbound refs swept
  — that requires recursion through Trashable, tracked as follow-up.
  """
  def delete_flow(%Flow{} = flow) do
    result =
      Repo.transaction(fn -> delete_flow_transaction(flow) end)

    case result do
      {:ok, deleted_flow} ->
        # Notify open canvases that have subflow nodes referencing this flow
        notify_affected_subflows(deleted_flow.id, deleted_flow.project_id)
        Collaboration.broadcast_dashboard_change(deleted_flow.project_id, :flows)

      _ ->
        :ok
    end

    result
  end

  defp delete_flow_transaction(flow) do
    case ReferenceIntegrity.lock_active_flow_for_write(flow) do
      {:ok, %{flow: locked_flow}} -> soft_delete_locked_flow(locked_flow)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp soft_delete_locked_flow(locked_flow) do
    Localization.delete_flow_node_texts_for_flows([locked_flow.id])

    case Trashable.soft_delete(locked_flow) do
      {:ok, deleted_flow} ->
        SoftDelete.soft_delete_children(Flow, locked_flow.project_id, locked_flow.id,
          pre_delete: &Localization.delete_flow_node_texts_for_flows([&1.id])
        )

        deleted_flow

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Permanently deletes a flow from the database.
  Use with caution - this cannot be undone.
  """
  def hard_delete_flow(%Flow{} = flow) do
    fn ->
      node_ids = Repo.all(from(n in FlowNode, where: n.flow_id == ^flow.id, select: n.id))
      Localization.purge_texts_for_sources("flow_node", node_ids)

      case Repo.delete(flow) do
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
    result =
      Repo.transaction(fn -> restore_flow_transaction(flow_id) end)

    case result do
      {:ok, restored_flow} ->
        Localization.extract_flow_nodes(restored_flow.id)
        broadcast_flow_dashboard_result(result, restored_flow.project_id)

      _ ->
        result
    end
  end

  def restore_flow(_flow), do: {:error, :flow_not_found}

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
         {:ok, source_nodes} <-
           lock_flow_trash_source_rows(trash_refs, project_id, flow_id),
         changeset = flow_restore_changeset(locked_flow),
         :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           ReferenceIntegrity.lock_flow_parent(
             project_id,
             locked_flow.id,
             locked_flow.parent_id
           ),
         {:ok, scene_id} <-
           ReferenceIntegrity.lock_flow_scene(project_id, locked_flow.scene_id),
         {:ok, restored_flow} <-
           changeset
           |> Ecto.Changeset.put_change(:parent_id, parent_id)
           |> Ecto.Changeset.put_change(:scene_id, scene_id)
           |> Ecto.Changeset.put_change(:deleted_at, nil)
           |> Repo.update(),
         {:ok, _restore_meta} <- EntityTrashRefs.restore(:flow, restored_flow.id),
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

    source_flow_scopes =
      Repo.all(
        from(flow in Flow,
          where: flow.id in ^source_flow_ids,
          order_by: [asc: flow.id],
          select: %{id: flow.id, project_id: flow.project_id}
        )
      )

    case Enum.find(source_flow_scopes, &(&1.project_id != project_id)) do
      nil ->
        Repo.all(
          from(flow in Flow,
            where: flow.id in ^source_flow_ids,
            order_by: [asc: flow.id],
            lock: "FOR UPDATE"
          )
        )

        {:ok,
         Repo.all(
           from(node in FlowNode,
             where: node.id in ^source_ids,
             order_by: [asc: node.id],
             lock: "FOR UPDATE"
           )
         )}

      _foreign_flow ->
        {:error, {:invalid_project_reference, :referenced_flow_id, target_flow_id}}
    end
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

    source_nodes
    |> Enum.map(&Repo.get!(FlowNode, &1.id))
    |> Enum.filter(&restored_source_node?(&1, restored_node_ids, restored_flow.id))
    |> normalize_restored_flow_nodes(project_id)
  end

  defp restored_source_node?(source_node, restored_node_ids, restored_flow_id) do
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
           ReferenceIntegrity.lock_node_parent(node.flow_id, parent_id, node.id),
         {:ok, data} <-
           ReferenceIntegrity.lock_and_normalize_node_references(
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
  def list_deleted_flows(project_id), do: SoftDelete.list_deleted(Flow, project_id)

  defp notify_affected_subflows(deleted_flow_id, project_id) do
    affected = NodeCrud.list_subflow_nodes_referencing(deleted_flow_id, project_id)

    affected
    |> Enum.map(& &1.flow_id)
    |> Enum.uniq()
    |> Enum.each(fn flow_id ->
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
    attrs = MapUtils.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, %{flow: locked_flow, project_id: project_id}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow),
           {:ok, scene_id} <-
             ReferenceIntegrity.lock_flow_scene(project_id, attrs["scene_id"]) do
        locked_flow
        |> Flow.scene_changeset(%{"scene_id" => scene_id})
        |> update_flow_or_rollback()
      else
        {:error, :flow_not_found} ->
          Repo.rollback(:flow_not_found)

        {:error, reason} ->
          Repo.rollback(flow_reference_changeset(flow, attrs, reason))
      end
    end)
  end

  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.update_changeset(flow, attrs)
  end

  def set_main_flow(%Flow{} = flow) do
    Repo.transaction(fn -> set_main_flow_transaction(flow) end)
  end

  defp set_main_flow_transaction(flow) do
    case ReferenceIntegrity.lock_active_flow_for_write(flow) do
      {:ok, %{project_id: project_id, flow: locked_flow}} ->
        replace_main_flow(locked_flow, project_id)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp replace_main_flow(locked_flow, project_id) do
    Repo.update_all(
      from(candidate in Flow,
        where:
          candidate.project_id == ^project_id and
            candidate.is_main == true
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
    |> ShortcutHelpers.maybe_generate_shortcut(
      project_id,
      exclude_flow_id,
      &Shortcuts.generate_flow_shortcut/3
    )
  end

  defp maybe_generate_shortcut_on_update(%Flow{} = flow, attrs) do
    ShortcutHelpers.maybe_generate_shortcut_on_update(
      flow,
      attrs,
      &Shortcuts.generate_flow_shortcut/3,
      check_backlinks_fn: &(Sheets.count_backlinks("flow", &1.id) > 0)
    )
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

  defp maybe_assign_position(attrs, project_id, parent_id) do
    ShortcutHelpers.maybe_assign_position(
      attrs,
      project_id,
      parent_id,
      &TreeOperations.next_position/2
    )
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Returns the project_id for a flow by its ID.
  Used by the Localization TextExtractor to resolve project scope.
  """
  def get_flow_project_id(flow_id) do
    Repo.one(from(f in Flow, where: f.id == ^flow_id, select: f.project_id))
  end

  @doc """
  Lists all non-deleted flows for a project with nodes and connections preloaded.
  Used by the export DataCollector and Validator.
  """
  def list_flows_for_export(project_id, opts \\ []) do
    nodes_query =
      from(n in FlowNode,
        where: is_nil(n.deleted_at),
        order_by: [asc: n.id],
        preload: [:sequence_config]
      )

    filter_ids = Keyword.get(opts, :filter_ids, :all)

    query =
      from(f in Flow,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        preload: [nodes: ^nodes_query, connections: []],
        order_by: [asc: f.position, asc: f.name]
      )

    query
    |> maybe_filter_export_ids(filter_ids)
    |> Repo.all()
  end

  @doc """
  Counts non-deleted flows for a project.
  """
  def count_flows(project_id) do
    Repo.aggregate(from(f in Flow, where: f.project_id == ^project_id and is_nil(f.deleted_at)), :count)
  end

  @doc """
  Counts non-deleted flow nodes across all non-deleted flows in a project.
  """
  def count_nodes_for_project(project_id) do
    Repo.aggregate(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at)
      ),
      :count
    )
  end

  @doc """
  Lists all non-deleted nodes for the given flow IDs.
  Used by the Localization TextExtractor for bulk extraction.
  """
  def list_nodes_for_flow_ids(flow_ids) do
    Repo.all(from(n in FlowNode, where: n.flow_id in ^flow_ids and is_nil(n.deleted_at)))
  end

  @doc """
  Lists flow nodes using a specific asset (audio_asset_id in data).
  Used by the Assets context for usage tracking.
  Returns a list of maps with node and flow info.
  """
  def list_nodes_using_asset(project_id, asset_id) do
    asset_id_str = to_string(asset_id)

    Repo.all(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id,
        where: is_nil(n.deleted_at),
        where: fragment("?->>'audio_asset_id' = ?", n.data, ^asset_id_str),
        order_by: [asc: f.name],
        select: %{node_id: n.id, node_type: n.type, flow_id: f.id, flow_name: f.name}
      )
    )
  end

  @doc """
  Resolves flow node source info for entity reference backlinks.
  Joins entity_references with flow_nodes and flows to return enriched backlink data.
  Used by the Sheets.ReferenceTracker to avoid cross-context schema queries.
  """
  def query_flow_node_backlinks(target_type, target_id, project_id) do
    alias Storyarn.Sheets.EntityReference

    from(r in EntityReference,
      join: n in FlowNode,
      on: r.source_type == "flow_node" and r.source_id == n.id,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: r.target_type == ^target_type and r.target_id == ^target_id,
      where: f.project_id == ^project_id,
      select: %{
        id: r.id,
        source_type: r.source_type,
        source_id: r.source_id,
        context: r.context,
        inserted_at: r.inserted_at,
        node_type: n.type,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut
      },
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn ref ->
      %{
        id: ref.id,
        source_type: "flow_node",
        source_id: ref.source_id,
        context: ref.context,
        inserted_at: ref.inserted_at,
        source_info: %{
          type: :flow,
          flow_id: ref.flow_id,
          flow_name: ref.flow_name,
          flow_shortcut: ref.flow_shortcut,
          node_type: ref.node_type
        }
      }
    end)
  end

  @doc """
  Lists sheet IDs referenced by flow nodes as speakers, across all active flows.
  Used by the export Validator for orphan sheet detection.
  """
  def list_speaker_sheet_ids(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at),
      where: fragment("?->>'speaker_sheet_id' ~ '^[0-9]+$'", n.data),
      select: fragment("(?->>'speaker_sheet_id')::integer", n.data)
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists sheet IDs referenced through variable_references in a project.
  Delegates to the Sheets context to avoid cross-context schema queries.
  """
  def list_variable_referenced_sheet_ids(project_id) do
    Sheets.list_variable_referenced_sheet_ids(project_id)
  end

  @doc """
  Lists existing shortcuts of the given schema type for a project.
  Used by the import parser for conflict detection.
  """
  def list_shortcuts(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      select: f.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Detects shortcut conflicts between imported flows and existing ones.
  Returns a list of conflicting shortcuts.
  """
  def detect_shortcut_conflicts(project_id, shortcuts) when is_list(shortcuts) do
    ImportHelpers.detect_shortcut_conflicts(Flow, project_id, shortcuts)
  end

  @doc """
  Soft-deletes existing entities with the given shortcut (for overwrite import strategy).
  """
  def soft_delete_by_shortcut(project_id, shortcut) do
    ImportHelpers.soft_delete_by_shortcut(Flow, project_id, shortcut)
  end

  @doc """
  Bulk-inserts flow connections from a list of attr maps.
  Returns the inserted records.
  """
  def bulk_import_connections(attrs_list) do
    ImportHelpers.bulk_insert(Storyarn.Flows.FlowConnection, attrs_list)
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a flow for import. Raw insert — no auto-shortcut, no auto-position,
  no auto-entry/exit nodes. Returns `{:ok, flow}` or `{:error, changeset}`.
  """
  def import_flow(project_id, attrs) do
    %Flow{project_id: project_id}
    |> Flow.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a flow node for import. Raw insert — no entry-node uniqueness check,
  no hub_id generation, no subflow validation.
  Returns `{:ok, node}` or `{:error, changeset}`.
  """
  def import_node(flow_id, attrs) do
    type = attrs[:type] || attrs["type"]
    data = attrs[:data] || attrs["data"]

    %FlowNode{flow_id: flow_id}
    |> FlowNode.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:word_count, WordCount.for_node_data(type, data))
    |> Repo.insert()
  end

  @doc """
  Updates a flow's parent_id after import (two-pass parent linking).
  """
  def link_import_parent(%Flow{} = flow, parent_id) do
    flow
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end

  @doc """
  Updates a node's data map after import (deferred ID remapping).
  Used for flow-to-flow references that can't be resolved until all flows are imported.
  """
  def link_node_import_data(node_id, data) do
    Repo.update_all(from(n in FlowNode, where: n.id == ^node_id), set: [data: data])
  end

  defp maybe_filter_export_ids(query, :all), do: query

  defp maybe_filter_export_ids(query, ids) when is_list(ids) do
    from(q in query, where: q.id in ^ids)
  end

  defp broadcast_flow_dashboard_result({:ok, _value} = result, project_id) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    result
  end

  defp broadcast_flow_dashboard_result(result, _project_id), do: result
end

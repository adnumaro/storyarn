defmodule Storyarn.Screenplays.FlowSync do
  @moduledoc """
  Manages the relationship between screenplays and flows.

  Provides operations to link/unlink screenplays to flows, create flows
  from screenplays, and sync screenplay content to flow nodes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Screenplays.ElementCrud
  alias Storyarn.Screenplays.FlowLayout
  alias Storyarn.Screenplays.FlowTraversal
  alias Storyarn.Screenplays.LinkedPageCrud
  alias Storyarn.Screenplays.PageTreeBuilder
  alias Storyarn.Screenplays.ReverseNodeMapping
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.ScreenplayCrud
  alias Storyarn.Screenplays.ScreenplayElement

  @max_tree_depth 20

  @doc """
  Returns the linked flow, creating one if the screenplay is unlinked.

  When creating a new flow, auto-links it to the screenplay.
  Returns `{:ok, flow}` or `{:error, reason}`.
  """
  def ensure_flow(%Screenplay{id: screenplay_id, project_id: project_id}) do
    result =
      with_locked_screenplay(project_id, screenplay_id, fn project, screenplay ->
        created? = is_nil(screenplay.linked_flow_id)
        {ensure_flow_in_transaction(screenplay, project), created?}
      end)

    case result do
      {:ok, {flow, true}} ->
        Collaboration.broadcast_dashboard_result({:ok, flow}, project_id, :flows)

      {:ok, {flow, false}} ->
        {:ok, flow}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Links a screenplay to an existing flow.

  Validates the flow exists and belongs to the same project.
  Returns `{:ok, screenplay}` or `{:error, changeset}`.
  """
  def link_to_flow(%Screenplay{id: screenplay_id, project_id: project_id}, flow_id) do
    with_locked_screenplay(project_id, screenplay_id, fn _project, screenplay ->
      flow = lock_active_flow_in_project!(project_id, flow_id)
      link_locked_screenplay!(screenplay, flow.id)
    end)
  end

  @doc """
  Unlinks a screenplay from its flow.

  Clears `linked_flow_id` on the screenplay and `linked_node_id` on all elements.
  Does NOT delete the flow or its nodes.
  Returns `{:ok, screenplay}` or `{:ok, screenplay}` if already unlinked.
  """
  def unlink_flow(%Screenplay{id: screenplay_id, project_id: project_id}) do
    with_locked_screenplay(project_id, screenplay_id, fn _project, screenplay ->
      link_locked_screenplay!(screenplay, nil)
    end)
  end

  defp link_locked_screenplay!(screenplay, linked_flow_id) do
    previous_flow_id = screenplay.linked_flow_id

    cond do
      previous_flow_id == linked_flow_id and not is_nil(linked_flow_id) ->
        screenplay

      previous_flow_id == linked_flow_id ->
        clear_direct_element_links!(screenplay.id)
        screenplay

      true ->
        clear_previous_element_links!(
          screenplay.project_id,
          screenplay.id,
          previous_flow_id
        )

        screenplay
        |> Screenplay.link_flow_changeset(%{linked_flow_id: linked_flow_id})
        |> Repo.update()
        |> case do
          {:ok, updated_screenplay} -> updated_screenplay
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp clear_previous_element_links!(_project_id, screenplay_id, nil) do
    clear_direct_element_links!(screenplay_id)
  end

  defp clear_previous_element_links!(project_id, screenplay_id, previous_flow_id) do
    screenplay_ids = screenplay_subtree_ids(project_id, screenplay_id)

    previous_flow_node_ids =
      from(node in FlowNode,
        where: node.flow_id == ^previous_flow_id,
        select: node.id
      )

    Repo.update_all(
      from(element in ScreenplayElement,
        where:
          element.screenplay_id in ^screenplay_ids and
            element.linked_node_id in subquery(previous_flow_node_ids)
      ),
      set: [linked_node_id: nil]
    )
  end

  defp clear_direct_element_links!(screenplay_id) do
    Repo.update_all(
      from(element in ScreenplayElement,
        where:
          element.screenplay_id == ^screenplay_id and
            not is_nil(element.linked_node_id)
      ),
      set: [linked_node_id: nil]
    )
  end

  defp screenplay_subtree_ids(project_id, screenplay_id) do
    anchor =
      from(screenplay in "screenplays",
        where:
          screenplay.id == ^screenplay_id and
            screenplay.project_id == ^project_id,
        select: %{id: screenplay.id}
      )

    recursion =
      from(screenplay in "screenplays",
        join: ancestor in "screenplay_subtree",
        on: screenplay.parent_id == ancestor.id,
        where: screenplay.project_id == ^project_id,
        select: %{id: screenplay.id}
      )

    subtree = union(anchor, ^recursion)

    from("screenplay_subtree")
    |> recursive_ctes(true)
    |> with_cte("screenplay_subtree", as: ^subtree)
    |> select([screenplay], screenplay.id)
    |> Repo.all()
  end

  @doc """
  Syncs screenplay elements to the linked flow.

  Groups elements, converts to node attributes, and diffs against existing
  synced nodes. Creates/updates/deletes nodes, creates sequential connections,
  and updates element `linked_node_id`s.

  Returns `{:ok, flow}` or `{:error, reason}`.
  """
  def sync_to_flow(%Screenplay{id: id, project_id: project_id}) do
    project_id
    |> sync_to_flow_with_project_lock(id, :key_share)
    |> retry_sync_with_project_update(project_id, id)
    |> Collaboration.broadcast_dashboard_result(project_id, :flows)
  end

  defp sync_to_flow_with_project_lock(project_id, screenplay_id, project_lock_mode) do
    with_locked_screenplay(
      project_id,
      screenplay_id,
      project_lock_mode,
      fn project, screenplay ->
        if project_lock_mode == :key_share and is_nil(screenplay.linked_flow_id),
          do: Repo.rollback(:requires_project_update)

        flow = ensure_flow_in_transaction(screenplay, project)
        {flow, all_nodes} = lock_flow_nodes!(flow)

        page_tree =
          screenplay
          |> load_page_tree_data(flow.id)
          |> PageTreeBuilder.build()

        %{all_node_attrs: all_node_attrs, connections: connections, screenplay_ids: screenplay_ids} =
          PageTreeBuilder.flatten(page_tree)

        do_sync_in_transaction(
          screenplay,
          flow,
          all_nodes,
          all_node_attrs,
          connections,
          screenplay_ids,
          page_tree,
          project_lock_mode
        )
      end
    )
  end

  defp retry_sync_with_project_update({:error, :requires_project_update}, project_id, screenplay_id) do
    sync_to_flow_with_project_lock(project_id, screenplay_id, :update)
  end

  defp retry_sync_with_project_update(result, _project_id, _screenplay_id), do: result

  @doc """
  Syncs flow nodes into the screenplay (reverse direction).

  Traverses the flow graph via DFS, reverse-maps nodes to element attrs,
  diffs against existing elements, and applies creates/updates/deletes.
  Non-mappeable elements (notes, sections, page_breaks) are preserved.

  Returns `{:ok, screenplay}` or `{:error, reason}`.
  """
  def sync_from_flow(%Screenplay{id: id, project_id: project_id}) do
    with_locked_screenplay(
      project_id,
      id,
      :key_share,
      fn _project, screenplay ->
        flow = lock_linked_flow_for_reverse_sync!(screenplay)
        sync_from_flow_in_transaction!(screenplay, flow)
      end
    )
  end

  defp sync_from_flow_in_transaction!(screenplay, flow) do
    nodes = Flows.list_nodes(flow.id)
    connections = Flows.list_connections(flow.id)

    case FlowTraversal.linearize_tree(nodes, connections) do
      {:error, :no_entry_node} ->
        Repo.rollback(:no_entry_node)

      {:ok, tree_result} ->
        sync_page_from_tree!(
          screenplay,
          tree_result,
          flow.id,
          MapSet.new([screenplay.id])
        )

        Repo.get!(Screenplay, screenplay.id)
    end
  end

  # ---------------------------------------------------------------------------
  # sync_from_flow internals
  # ---------------------------------------------------------------------------

  defp sync_page_from_tree!(screenplay, tree_result, flow_id, visited_screenplay_ids, depth \\ 0)

  defp sync_page_from_tree!(_screenplay, _tree_result, _flow_id, visited_screenplay_ids, depth)
       when depth > @max_tree_depth, do: visited_screenplay_ids

  defp sync_page_from_tree!(screenplay, tree_result, flow_id, visited_screenplay_ids, depth) do
    new_attrs = ReverseNodeMapping.nodes_to_element_attrs(tree_result.nodes)
    sync_page_elements!(screenplay, new_attrs)

    nodes_by_id = Map.new(tree_result.nodes, &{&1.id, &1})
    branch_choice_ids = MapSet.new(tree_result.branches, & &1.choice_id)

    visited_screenplay_ids =
      Enum.reduce(
        tree_result.branches,
        visited_screenplay_ids,
        fn branch, visited_ids ->
          source_node = Map.get(nodes_by_id, branch.source_node_id)

          sync_branch_from_tree!(
            screenplay,
            branch,
            source_node,
            flow_id,
            visited_ids,
            depth
          )
        end
      )

    cleanup_orphaned_links!(screenplay.id, tree_result.nodes, branch_choice_ids)
    visited_screenplay_ids
  end

  defp sync_page_elements!(screenplay, new_attrs) do
    non_mappeable = ScreenplayElement.non_mappeable_types()
    existing = ElementCrud.list_elements(screenplay.id)
    non_mappeable_anchored = extract_non_mappeable_with_anchors(existing, non_mappeable)
    mappeable_existing = Enum.reject(existing, &(&1.type in non_mappeable))

    {result_elements, orphaned} = diff_elements(screenplay, new_attrs, mappeable_existing)

    orphan_ids = Enum.map(orphaned, & &1.id)

    if orphan_ids != [] do
      Repo.delete_all(from(e in ScreenplayElement, where: e.id in ^orphan_ids))
    end

    final_order = insert_non_mappeable(result_elements, non_mappeable_anchored)
    recompact_positions!(final_order)
  end

  defp sync_branch_from_tree!(parent, branch, source_node, flow_id, visited_screenplay_ids, depth) do
    linked_id = get_choice_field(source_node, branch.choice_id, "linked_screenplay_id")

    child =
      case lock_owned_child(parent, linked_id, flow_id) do
        %Screenplay{} = owned_child ->
          owned_child

        nil ->
          create_branch_child!(parent, branch.choice_id, source_node)
      end

    if MapSet.member?(visited_screenplay_ids, child.id),
      do: Repo.rollback({:reused_screenplay_branch, child.id})

    sync_page_from_tree!(
      child,
      branch.subtree,
      flow_id,
      MapSet.put(visited_screenplay_ids, child.id),
      depth + 1
    )
  end

  defp create_branch_child!(parent, choice_id, source_node) do
    project = Storyarn.Projects.get_project!(parent.project_id)
    text = get_choice_field(source_node, choice_id, "text") || ""
    name = if text == "", do: "Untitled Branch", else: text

    {:ok, child} = ScreenplayCrud.create_screenplay(project, %{name: name, parent_id: parent.id})
    set_choice_linked_id!(parent.id, source_node.id, choice_id, child.id)
    child
  end

  defp lock_owned_child(parent, child_id, flow_id) when is_integer(child_id) and is_integer(flow_id) do
    Repo.one(
      from(child in Screenplay,
        where:
          child.id == ^child_id and
            child.parent_id == ^parent.id and
            child.project_id == ^parent.project_id and
            is_nil(child.deleted_at) and
            (is_nil(child.linked_flow_id) or child.linked_flow_id == ^flow_id),
        lock: "FOR NO KEY UPDATE"
      )
    )
  end

  defp lock_owned_child(_parent, _child_id, _flow_id), do: nil

  defp get_choice_field(node, choice_id, field) do
    responses = (node.data || %{})["responses"] || []

    case Enum.find(responses, &(&1["id"] == choice_id)) do
      nil -> nil
      choice -> choice[field]
    end
  end

  defp set_choice_linked_id!(screenplay_id, source_node_id, choice_id, child_id) do
    case find_response_element(screenplay_id, source_node_id) do
      nil ->
        raise "Response element not found for screenplay #{screenplay_id}, node #{source_node_id}"

      element ->
        {:ok, _} =
          LinkedPageCrud.update_choice(element, choice_id, fn c ->
            Map.put(c, "linked_screenplay_id", child_id)
          end)

        :ok
    end
  end

  defp find_response_element(screenplay_id, source_node_id) do
    Repo.one(
      from(e in ScreenplayElement,
        where:
          e.screenplay_id == ^screenplay_id and e.type == "response" and
            e.linked_node_id == ^source_node_id
      )
    )
  end

  defp cleanup_orphaned_links!(screenplay_id, nodes, branch_choice_ids) do
    for node <- nodes,
        node.type == "dialogue",
        resp_id <- FlowTraversal.response_ids(node),
        not MapSet.member?(branch_choice_ids, resp_id),
        get_choice_field(node, resp_id, "linked_screenplay_id") != nil do
      set_choice_linked_id!(screenplay_id, node.id, resp_id, nil)
    end
  end

  defp extract_non_mappeable_with_anchors(elements, non_mappeable) do
    elements
    |> Enum.with_index()
    |> Enum.filter(fn {el, _idx} -> el.type in non_mappeable end)
    |> Enum.map(fn {el, idx} -> {el, find_anchor(elements, idx, non_mappeable)} end)
  end

  defp find_anchor(elements, idx, non_mappeable) do
    elements
    |> Enum.drop(idx + 1)
    |> Enum.find(fn e -> e.type not in non_mappeable end)
    |> case do
      nil -> :end
      %{linked_node_id: nil, id: id} -> {:element_id, id}
      %{linked_node_id: node_id} -> node_id
    end
  end

  defp diff_elements(screenplay, new_attrs, mappeable_existing) do
    # Group existing by linked_node_id
    existing_by_node = Enum.group_by(mappeable_existing, & &1.linked_node_id)

    # Process each new attr in order, collecting results via prepend (O(1) per item)
    {reversed_elements, used_existing_ids} =
      Enum.reduce(new_attrs, {[], MapSet.new()}, fn attr, {acc, used} ->
        existing_for_node = Map.get(existing_by_node, attr.source_node_id, [])

        # Find first unused existing element matching by type
        match =
          Enum.find(existing_for_node, fn el ->
            el.type == attr.type and not MapSet.member?(used, el.id)
          end)

        case match do
          nil ->
            element = create_element_from_attr!(screenplay, attr)
            {[element | acc], used}

          existing ->
            element = update_element_from_attr!(existing, attr)
            {[element | acc], MapSet.put(used, existing.id)}
        end
      end)

    result_elements = Enum.reverse(reversed_elements)

    # Orphaned = all existing mappeable elements that were not matched
    orphaned =
      Enum.filter(mappeable_existing, fn el ->
        not MapSet.member?(used_existing_ids, el.id)
      end)

    {result_elements, orphaned}
  end

  defp element_attrs_from(attr) do
    %{type: attr.type, content: attr.content || "", data: attr.data || %{}}
  end

  defp create_element_from_attr!(screenplay, attr) do
    %ScreenplayElement{screenplay_id: screenplay.id}
    |> ScreenplayElement.create_changeset(Map.put(element_attrs_from(attr), :position, 0))
    |> Ecto.Changeset.put_change(:linked_node_id, attr.source_node_id)
    |> Repo.insert!()
  end

  defp update_element_from_attr!(element, attr) do
    element
    |> ScreenplayElement.update_changeset(element_attrs_from(attr))
    |> Ecto.Changeset.put_change(:linked_node_id, attr.source_node_id)
    |> Repo.update!()
  end

  defp insert_non_mappeable(result_elements, non_mappeable_anchored) do
    # Group non-mappeable by anchor
    by_anchor = Enum.group_by(non_mappeable_anchored, fn {_el, anchor} -> anchor end)

    # Build final list: for each result element, prepend any anchored non-mappeable
    # Anchors can be: node_id (integer), {:element_id, id}, or :end
    final =
      Enum.flat_map(result_elements, fn el ->
        by_node = Map.get(by_anchor, el.linked_node_id, [])
        by_elem = Map.get(by_anchor, {:element_id, el.id}, [])
        non_map_els = Enum.map(by_node ++ by_elem, fn {nme, _anchor} -> nme end)
        non_map_els ++ [el]
      end)

    # Append any non-mappeable anchored to :end
    tail = by_anchor |> Map.get(:end, []) |> Enum.map(fn {nme, _} -> nme end)
    final ++ tail
  end

  defp recompact_positions!(elements) do
    elements
    |> Enum.with_index()
    |> Enum.each(fn {el, idx} ->
      if el.position != idx do
        el
        |> Ecto.Changeset.change(%{position: idx})
        |> Repo.update!()
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # sync_to_flow internals
  # ---------------------------------------------------------------------------

  defp do_sync_in_transaction(
         screenplay,
         flow,
         all_nodes,
         all_node_attrs,
         connection_specs,
         screenplay_ids,
         page_tree,
         project_lock_mode
       ) do
    synced_nodes = Enum.filter(all_nodes, &(&1.source == "screenplay_sync"))
    entry_node = Enum.find(all_nodes, &(&1.type == "entry"))

    # Build lookups across ALL screenplay pages
    element_to_node = build_element_to_node_lookup(screenplay_ids)
    synced_by_id = Map.new(synced_nodes, &{&1.id, &1})

    resolved_nodes =
      Enum.map(all_node_attrs, fn attrs ->
        {attrs, find_existing_node(attrs, element_to_node, synced_by_id, entry_node)}
      end)

    matched_ids = matched_node_ids(resolved_nodes)

    if project_lock_mode == :key_share and
         (Enum.any?(resolved_nodes, fn {_attrs, existing} -> is_nil(existing) end) or
            Enum.any?(synced_nodes, &(not MapSet.member?(matched_ids, &1.id)))),
       do: Repo.rollback(:requires_project_update)

    # Delete orphans before certification. Deleting a hub clears its jumps, so
    # certifying first would leave a stale "current" decision for those nodes.
    delete_orphaned_nodes!(synced_nodes, matched_ids, flow.project_id)

    {hub_mutations, remaining_nodes} =
      resolved_nodes
      |> Enum.with_index()
      |> Enum.split_with(&hub_mutation?/1)

    # Hub writes can cascade into jump data. Apply every hub mutation as one
    # phase, then certify the remaining nodes against that final hub state.
    hub_results = upsert_sync_node_group(hub_mutations, flow)
    remaining_results = upsert_sync_node_group(remaining_nodes, flow)

    result_nodes =
      (hub_results ++ remaining_results)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    # Reconcile only changed connections between result nodes.
    reconcile_connections!(flow, result_nodes, connection_specs)

    # Position new nodes using tree-aware layout
    positions = FlowLayout.compute_positions(page_tree, result_nodes)
    apply_positions!(result_nodes, positions, matched_ids)

    # Update element links across all pages
    update_element_links!(all_node_attrs, result_nodes, element_to_node)

    Flows.get_flow!(screenplay.project_id, flow.id)
  end

  defp lock_flow_nodes!(flow) do
    case Flows.lock_flow_nodes_for_update(flow) do
      {:ok, locked_flow_and_nodes} -> locked_flow_and_nodes
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp matched_node_ids(resolved_nodes) do
    resolved_nodes
    |> Enum.flat_map(fn
      {_attrs, %FlowNode{id: id}} -> [id]
      {_attrs, nil} -> []
    end)
    |> MapSet.new()
  end

  defp hub_mutation?({{attrs, existing}, _index}) do
    attrs.type == "hub" or match?(%FlowNode{type: "hub"}, existing)
  end

  defp upsert_sync_node_group([], _flow), do: []

  defp upsert_sync_node_group(indexed_resolved_nodes, flow) do
    current_node_ids =
      indexed_resolved_nodes
      |> Enum.flat_map(fn
        {{attrs, %FlowNode{type: type, source: "screenplay_sync"} = node}, _index}
        when type == attrs.type ->
          [{node, attrs.data}]

        {_missing_or_stale_node, _index} ->
          []
      end)
      |> Flows.node_data_and_derivatives_current_ids(flow.project_id)

    Enum.map(indexed_resolved_nodes, fn {{attrs, existing}, index} ->
      {index, upsert_sync_node(attrs, existing, flow, current_node_ids)}
    end)
  end

  defp upsert_sync_node(attrs, existing, flow, current_node_ids) do
    case existing do
      nil ->
        create_sync_node!(flow, attrs)

      existing ->
        update_sync_node!(existing, attrs, current_node_ids)
    end
  end

  defp find_existing_node(%{type: "entry"}, _element_to_node, _synced_by_id, entry_node) do
    entry_node
  end

  defp find_existing_node(attrs, element_to_node, synced_by_id, _entry_node) do
    Enum.find_value(attrs.element_ids, fn elem_id ->
      with node_id when not is_nil(node_id) <- Map.get(element_to_node, elem_id),
           %FlowNode{} = node <- Map.get(synced_by_id, node_id) do
        node
      else
        _ -> nil
      end
    end)
  end

  defp build_element_to_node_lookup(screenplay_ids) when is_list(screenplay_ids) do
    from(e in ScreenplayElement,
      where: e.screenplay_id in ^screenplay_ids and not is_nil(e.linked_node_id),
      select: {e.id, e.linked_node_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp create_sync_node!(flow, attrs) do
    case Flows.create_node_without_dashboard_broadcast(flow, %{
           type: attrs.type,
           data: attrs.data,
           source: "screenplay_sync"
         }) do
      {:ok, node} -> node
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp update_sync_node!(existing, attrs, current_node_ids) do
    if sync_node_current?(existing, attrs, current_node_ids) do
      existing
    else
      case Flows.update_node_without_dashboard_broadcast(existing, %{
             type: attrs.type,
             data: attrs.data
           }) do
        {:ok, node} -> ensure_screenplay_sync_source!(node)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp sync_node_current?(existing, attrs, current_node_ids) do
    existing.type == attrs.type and
      existing.source == "screenplay_sync" and
      MapSet.member?(current_node_ids, existing.id)
  end

  defp ensure_screenplay_sync_source!(%FlowNode{source: "screenplay_sync"} = node), do: node

  defp ensure_screenplay_sync_source!(node) do
    case node
         |> Ecto.Changeset.change(source: "screenplay_sync")
         |> Repo.update() do
      {:ok, node} -> node
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp delete_orphaned_nodes!(synced_nodes, matched_ids, project_id) do
    orphaned = Enum.reject(synced_nodes, &MapSet.member?(matched_ids, &1.id))
    orphaned_ids = Enum.map(orphaned, & &1.id)

    # Clear element links to orphaned nodes
    if orphaned_ids != [] do
      Repo.update_all(
        from(element in ScreenplayElement,
          join: screenplay in Screenplay,
          on: screenplay.id == element.screenplay_id,
          where:
            screenplay.project_id == ^project_id and
              element.linked_node_id in ^orphaned_ids
        ),
        set: [linked_node_id: nil]
      )
    end

    deleted_node_ids =
      Enum.reduce(orphaned, [], fn node, deleted_ids ->
        case Flows.delete_node_in_transaction_without_dashboard_broadcast(node) do
          {:ok, deleted_node, _meta} -> [deleted_node.id | deleted_ids]
          {:error, :cannot_delete_entry_node} -> deleted_ids
          {:error, :cannot_delete_last_exit} -> deleted_ids
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    delete_connections_incident_to_nodes!(deleted_node_ids)
  end

  defp delete_connections_incident_to_nodes!([]), do: :ok

  defp delete_connections_incident_to_nodes!(node_ids) do
    Repo.delete_all(
      from(connection in FlowConnection,
        where:
          connection.source_node_id in ^node_ids or
            connection.target_node_id in ^node_ids
      )
    )

    :ok
  end

  defp reconcile_connections!(flow, result_nodes, connection_specs) do
    desired_connections = build_desired_connections(result_nodes, connection_specs)
    desired_by_key = Map.new(desired_connections, &{connection_key(&1), &1})
    existing_connections = list_internal_connections_for_update(flow.id, result_nodes)

    {current_keys, stale_ids} =
      Enum.reduce(existing_connections, {MapSet.new(), []}, fn connection, {current, stale} ->
        key = connection_key(connection)

        if Map.has_key?(desired_by_key, key) do
          {MapSet.put(current, key), stale}
        else
          {current, [connection.id | stale]}
        end
      end)

    delete_connections!(stale_ids)

    desired_connections
    |> Enum.reject(&MapSet.member?(current_keys, connection_key(&1)))
    |> Enum.each(&create_connection!(flow, &1))
  end

  defp build_desired_connections(result_nodes, connection_specs) do
    connection_specs
    |> Enum.reduce([], fn spec, connections ->
      source = Enum.at(result_nodes, spec.source_index)
      target = Enum.at(result_nodes, spec.target_index)

      if source && target do
        [
          %{
            source_node_id: source.id,
            target_node_id: target.id,
            source_pin: spec.source_pin,
            target_pin: spec.target_pin
          }
          | connections
        ]
      else
        connections
      end
    end)
    |> Enum.reverse()
    |> ensure_unique_connection_keys!()
  end

  defp ensure_unique_connection_keys!(connections) do
    case Enum.reduce_while(connections, MapSet.new(), &track_connection_key/2) do
      {:duplicate, key} -> Repo.rollback({:duplicate_connection_spec, key})
      _seen -> connections
    end
  end

  defp track_connection_key(connection, seen) do
    key = connection_key(connection)

    if MapSet.member?(seen, key),
      do: {:halt, {:duplicate, key}},
      else: {:cont, MapSet.put(seen, key)}
  end

  defp list_internal_connections_for_update(_flow_id, []), do: []

  defp list_internal_connections_for_update(flow_id, result_nodes) do
    node_ids = Enum.map(result_nodes, & &1.id)

    Repo.all(
      from(connection in FlowConnection,
        where:
          connection.flow_id == ^flow_id and
            connection.source_node_id in ^node_ids and
            connection.target_node_id in ^node_ids,
        lock: "FOR UPDATE"
      )
    )
  end

  defp delete_connections!([]), do: :ok

  defp delete_connections!(connection_ids) do
    Repo.delete_all(from(connection in FlowConnection, where: connection.id in ^connection_ids))
    :ok
  end

  defp create_connection!(flow, attrs) do
    case Flows.create_connection_without_dashboard_broadcast(flow, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp connection_key(connection) do
    {
      connection.source_node_id,
      connection.source_pin,
      connection.target_node_id,
      connection.target_pin
    }
  end

  defp apply_positions!(result_nodes, positions, matched_ids) do
    Enum.each(result_nodes, &apply_node_position(&1, positions, matched_ids))
  end

  defp apply_node_position(node, positions, matched_ids) do
    with false <- MapSet.member?(matched_ids, node.id),
         {x, y} <- Map.get(positions, node.id) do
      node
      |> Ecto.Changeset.change(%{position_x: x, position_y: y})
      |> Repo.update!()
    end
  end

  defp update_element_links!(node_attrs_list, result_nodes, element_to_node) do
    node_attrs_list
    |> Enum.zip(result_nodes)
    |> Enum.each(fn {attrs, node} ->
      stale_element_ids =
        Enum.reject(attrs.element_ids, &(Map.get(element_to_node, &1) == node.id))

      if stale_element_ids != [] do
        Repo.update_all(
          from(e in ScreenplayElement, where: e.id in ^stale_element_ids),
          set: [linked_node_id: node.id]
        )
      end
    end)
  end

  defp load_page_tree_data(screenplay, flow_id) do
    elements = ElementCrud.list_elements(screenplay.id)
    children = load_descendant_data(screenplay.project_id, screenplay.id, flow_id)
    %{screenplay_id: screenplay.id, elements: elements, children: children}
  end

  defp load_descendant_data(project_id, parent_id, flow_id, depth \\ 0)

  defp load_descendant_data(_project_id, _parent_id, _flow_id, depth) when depth > @max_tree_depth, do: []

  defp load_descendant_data(project_id, parent_id, flow_id, depth) do
    from(s in Screenplay,
      where:
        s.project_id == ^project_id and
          s.parent_id == ^parent_id and
          is_nil(s.deleted_at) and
          (is_nil(s.linked_flow_id) or s.linked_flow_id == ^flow_id),
      order_by: [asc: s.position]
    )
    |> Repo.all()
    |> Enum.map(fn child ->
      elements = ElementCrud.list_elements(child.id)
      children = load_descendant_data(project_id, child.id, flow_id, depth + 1)
      %{screenplay_id: child.id, elements: elements, children: children}
    end)
  end

  defp ensure_flow_in_transaction(%Screenplay{linked_flow_id: nil} = screenplay, project) do
    flow = Flows.create_flow_in_transaction(project, %{name: screenplay.name})
    link_locked_screenplay!(screenplay, flow.id)
    flow
  end

  defp ensure_flow_in_transaction(%Screenplay{linked_flow_id: flow_id, project_id: project_id}, _project) do
    lock_active_flow_in_project!(project_id, flow_id)
  end

  defp lock_linked_flow_for_reverse_sync!(%Screenplay{linked_flow_id: nil}) do
    Repo.rollback(:not_linked)
  end

  defp lock_linked_flow_for_reverse_sync!(%Screenplay{linked_flow_id: flow_id, project_id: project_id}) do
    lock_active_flow_in_project!(project_id, flow_id)
  end

  defp with_locked_screenplay(project_id, screenplay_id, operation) do
    with_locked_screenplay(project_id, screenplay_id, :update, operation)
  end

  defp with_locked_screenplay(project_id, screenplay_id, project_lock_mode, operation) do
    Repo.transaction(fn ->
      project = lock_active_project!(project_id, project_lock_mode)
      screenplay = lock_active_screenplay!(project.id, screenplay_id)
      operation.(project, screenplay)
    end)
  end

  defp lock_active_project!(project_id, project_lock_mode) do
    case ProjectReferenceIntegrity.lock_active_project(
           project_id,
           project_lock_mode
         ) do
      {:ok, project} -> project
      {:error, _reason} -> Repo.rollback(:project_not_active)
    end
  end

  defp lock_active_screenplay!(project_id, screenplay_id) do
    Repo.one(
      from(screenplay in Screenplay,
        where:
          screenplay.id == ^screenplay_id and
            screenplay.project_id == ^project_id and
            is_nil(screenplay.deleted_at),
        lock: "FOR NO KEY UPDATE"
      )
    ) || Repo.rollback(:screenplay_not_found)
  end

  defp lock_active_flow_in_project!(project_id, flow_id) do
    Repo.one(
      from(flow in Flow,
        where:
          flow.id == ^flow_id and
            flow.project_id == ^project_id and
            is_nil(flow.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:flow_not_found)
  end
end

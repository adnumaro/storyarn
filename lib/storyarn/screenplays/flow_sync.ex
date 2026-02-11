defmodule Storyarn.Screenplays.FlowSync do
  @moduledoc """
  Manages the relationship between screenplays and flows.

  Provides operations to link/unlink screenplays to flows, create flows
  from screenplays, and sync screenplay content to flow nodes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Repo

  alias Storyarn.Screenplays.{
    ElementCrud,
    FlowLayout,
    FlowTraversal,
    LinkedPageCrud,
    PageTreeBuilder,
    ReverseNodeMapping,
    Screenplay,
    ScreenplayCrud,
    ScreenplayElement
  }

  @max_tree_depth 20

  @doc """
  Returns the linked flow, creating one if the screenplay is unlinked.

  When creating a new flow, auto-links it to the screenplay.
  Returns `{:ok, flow}` or `{:error, reason}`.
  """
  def ensure_flow(%Screenplay{linked_flow_id: nil, project_id: project_id} = screenplay) do
    project = Storyarn.Projects.get_project!(project_id)

    case Flows.create_flow(project, %{name: screenplay.name}) do
      {:ok, flow} ->
        case link_to_flow(screenplay, flow.id) do
          {:ok, _screenplay} -> {:ok, flow}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_flow(%Screenplay{linked_flow_id: flow_id, project_id: project_id}) do
    case Flows.get_flow(project_id, flow_id) do
      nil -> {:error, :flow_not_found}
      flow -> {:ok, flow}
    end
  end

  @doc """
  Links a screenplay to an existing flow.

  Validates the flow exists and belongs to the same project.
  Returns `{:ok, screenplay}` or `{:error, changeset}`.
  """
  def link_to_flow(%Screenplay{} = screenplay, flow_id) do
    case Flows.get_flow(screenplay.project_id, flow_id) do
      nil ->
        {:error, :flow_not_found}

      _flow ->
        screenplay
        |> Screenplay.link_flow_changeset(%{linked_flow_id: flow_id})
        |> Repo.update()
    end
  end

  @doc """
  Unlinks a screenplay from its flow.

  Clears `linked_flow_id` on the screenplay and `linked_node_id` on all elements.
  Does NOT delete the flow or its nodes.
  Returns `{:ok, screenplay}` or `{:ok, screenplay}` if already unlinked.
  """
  def unlink_flow(%Screenplay{linked_flow_id: nil} = screenplay) do
    {:ok, screenplay}
  end

  def unlink_flow(%Screenplay{} = screenplay) do
    Repo.transaction(fn ->
      # Clear linked_node_id on all elements
      from(e in ScreenplayElement,
        where: e.screenplay_id == ^screenplay.id and not is_nil(e.linked_node_id)
      )
      |> Repo.update_all(set: [linked_node_id: nil])

      # Clear linked_flow_id on screenplay
      screenplay
      |> Screenplay.link_flow_changeset(%{linked_flow_id: nil})
      |> Repo.update!()
    end)
  end

  @doc """
  Syncs screenplay elements to the linked flow.

  Groups elements, converts to node attributes, and diffs against existing
  synced nodes. Creates/updates/deletes nodes, creates sequential connections,
  and updates element `linked_node_id`s.

  Returns `{:ok, flow}` or `{:error, reason}`.
  """
  def sync_to_flow(%Screenplay{id: id, project_id: project_id}) do
    # Re-fetch to get latest linked_flow_id
    screenplay = Repo.get!(Screenplay, id)

    page_data = load_page_tree_data(screenplay)
    page_tree = PageTreeBuilder.build(page_data)

    %{all_node_attrs: all_node_attrs, connections: connections, screenplay_ids: screenplay_ids} =
      PageTreeBuilder.flatten(page_tree)

    with {:ok, flow} <- ensure_flow(screenplay) do
      do_sync(%{screenplay | project_id: project_id}, flow, all_node_attrs, connections, screenplay_ids, page_tree)
    end
  end

  @doc """
  Syncs flow nodes into the screenplay (reverse direction).

  Traverses the flow graph via DFS, reverse-maps nodes to element attrs,
  diffs against existing elements, and applies creates/updates/deletes.
  Non-mappeable elements (notes, sections, page_breaks) are preserved.

  Returns `{:ok, screenplay}` or `{:error, reason}`.
  """
  def sync_from_flow(%Screenplay{id: id}) do
    # Re-fetch to get latest linked_flow_id
    screenplay = Repo.get!(Screenplay, id)

    if is_nil(screenplay.linked_flow_id) do
      {:error, :not_linked}
    else
      sync_from_flow_linked(screenplay)
    end
  end

  defp sync_from_flow_linked(screenplay) do
    case ensure_flow(screenplay) do
      {:error, reason} -> {:error, reason}
      {:ok, flow} -> sync_from_flow_tree(screenplay, flow)
    end
  end

  defp sync_from_flow_tree(screenplay, flow) do
    nodes = Flows.list_nodes(flow.id)
    connections = Flows.list_connections(flow.id)

    case FlowTraversal.linearize_tree(nodes, connections) do
      {:error, :no_entry_node} ->
        {:error, :no_entry_node}

      {:ok, tree_result} ->
        Repo.transaction(fn ->
          sync_page_from_tree!(screenplay, tree_result)
          Repo.get!(Screenplay, screenplay.id)
        end)
    end
  end

  # ---------------------------------------------------------------------------
  # sync_from_flow internals
  # ---------------------------------------------------------------------------

  defp sync_page_from_tree!(screenplay, tree_result, depth \\ 0)

  defp sync_page_from_tree!(_screenplay, _tree_result, depth) when depth > @max_tree_depth, do: :ok

  defp sync_page_from_tree!(screenplay, tree_result, depth) do
    new_attrs = ReverseNodeMapping.nodes_to_element_attrs(tree_result.nodes)
    sync_page_elements!(screenplay, new_attrs)

    nodes_by_id = Map.new(tree_result.nodes, &{&1.id, &1})
    branch_choice_ids = MapSet.new(tree_result.branches, & &1.choice_id)

    Enum.each(tree_result.branches, fn branch ->
      source_node = Map.get(nodes_by_id, branch.source_node_id)
      sync_branch_from_tree!(screenplay, branch, source_node, depth)
    end)

    cleanup_orphaned_links!(screenplay.id, tree_result.nodes, branch_choice_ids)
  end

  defp sync_page_elements!(screenplay, new_attrs) do
    non_mappeable = ScreenplayElement.non_mappeable_types()
    existing = ElementCrud.list_elements(screenplay.id)
    non_mappeable_anchored = extract_non_mappeable_with_anchors(existing, non_mappeable)
    mappeable_existing = Enum.reject(existing, &(&1.type in non_mappeable))

    {result_elements, orphaned} = diff_elements(screenplay, new_attrs, mappeable_existing)
    Enum.each(orphaned, &Repo.delete!/1)

    final_order = insert_non_mappeable(result_elements, non_mappeable_anchored)
    recompact_positions!(final_order)
  end

  defp sync_branch_from_tree!(parent, branch, source_node, depth) do
    linked_id = get_choice_field(source_node, branch.choice_id, "linked_screenplay_id")

    child =
      if linked_id && child_exists?(linked_id, parent.id) do
        Repo.get!(Screenplay, linked_id)
      else
        create_branch_child!(parent, branch.choice_id, source_node)
      end

    sync_page_from_tree!(child, branch.subtree, depth + 1)
  end

  defp create_branch_child!(parent, choice_id, source_node) do
    project = Storyarn.Projects.get_project!(parent.project_id)
    text = get_choice_field(source_node, choice_id, "text") || ""
    name = if text != "", do: text, else: "Untitled Branch"

    {:ok, child} = ScreenplayCrud.create_screenplay(project, %{name: name, parent_id: parent.id})
    set_choice_linked_id!(parent.id, source_node.id, choice_id, child.id)
    child
  end

  defp child_exists?(child_id, parent_id) do
    from(s in Screenplay,
      where: s.id == ^child_id and s.parent_id == ^parent_id and is_nil(s.deleted_at)
    )
    |> Repo.exists?()
  end

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
        :ok

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
    tail = Map.get(by_anchor, :end, []) |> Enum.map(fn {nme, _} -> nme end)
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

  defp do_sync(screenplay, flow, all_node_attrs, connection_specs, screenplay_ids, page_tree) do
    Repo.transaction(fn ->
      # Load existing state
      all_nodes = Flows.list_nodes(flow.id)
      synced_nodes = Enum.filter(all_nodes, &(&1.source == "screenplay_sync"))
      entry_node = Enum.find(all_nodes, &(&1.type == "entry"))

      # Build lookups across ALL screenplay pages
      element_to_node = build_element_to_node_lookup(screenplay_ids)
      synced_by_id = Map.new(synced_nodes, &{&1.id, &1})

      # Create or update nodes
      {result_nodes, matched_ids} =
        Enum.map_reduce(all_node_attrs, MapSet.new(), fn attrs, matched ->
          upsert_sync_node(attrs, element_to_node, synced_by_id, entry_node, flow, matched)
        end)

      # Delete orphaned synced nodes
      delete_orphaned_nodes!(synced_nodes, matched_ids)

      # Rebuild connections between result nodes
      delete_connections_between!(flow.id, result_nodes)
      create_connections_from_specs!(flow, result_nodes, connection_specs)

      # Position new nodes using tree-aware layout
      positions = FlowLayout.compute_positions(page_tree, result_nodes)
      apply_positions!(result_nodes, positions, matched_ids)

      # Update element links across all pages
      update_element_links!(all_node_attrs, result_nodes)

      Flows.get_flow!(screenplay.project_id, flow.id)
    end)
  end

  defp upsert_sync_node(attrs, element_to_node, synced_by_id, entry_node, flow, matched) do
    case find_existing_node(attrs, element_to_node, synced_by_id, entry_node) do
      nil ->
        node = create_sync_node!(flow, attrs)
        {node, matched}

      existing ->
        node = update_sync_node!(existing, attrs)
        {node, MapSet.put(matched, existing.id)}
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
    case Flows.create_node(flow, %{type: attrs.type, data: attrs.data, source: "screenplay_sync"}) do
      {:ok, node} -> node
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp update_sync_node!(existing, attrs) do
    existing
    |> Ecto.Changeset.change(%{data: attrs.data, source: "screenplay_sync"})
    |> Repo.update!()
  end

  defp delete_orphaned_nodes!(synced_nodes, matched_ids) do
    orphaned = Enum.reject(synced_nodes, &MapSet.member?(matched_ids, &1.id))
    orphaned_ids = Enum.map(orphaned, & &1.id)

    # Clear element links to orphaned nodes
    if orphaned_ids != [] do
      from(e in ScreenplayElement, where: e.linked_node_id in ^orphaned_ids)
      |> Repo.update_all(set: [linked_node_id: nil])
    end

    # Delete orphaned nodes (skip protected ones)
    Enum.each(orphaned, fn node ->
      case Flows.delete_node(node) do
        {:ok, _, _} -> :ok
        {:error, :cannot_delete_entry_node} -> :ok
        {:error, :cannot_delete_last_exit} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp delete_connections_between!(flow_id, result_nodes) do
    node_ids = Enum.map(result_nodes, & &1.id)

    if node_ids != [] do
      from(c in FlowConnection,
        where: c.flow_id == ^flow_id,
        where: c.source_node_id in ^node_ids and c.target_node_id in ^node_ids
      )
      |> Repo.delete_all()
    end
  end

  defp create_connections_from_specs!(flow, result_nodes, connection_specs) do
    Enum.each(connection_specs, fn spec ->
      source = Enum.at(result_nodes, spec.source_index)
      target = Enum.at(result_nodes, spec.target_index)

      if source && target do
        create_connection!(flow, source, target, spec.source_pin, spec.target_pin)
      end
    end)
  end

  defp create_connection!(flow, source, target, source_pin, target_pin) do
    case Flows.create_connection(flow, source, target, %{
           source_pin: source_pin,
           target_pin: target_pin
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
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

  defp update_element_links!(node_attrs_list, result_nodes) do
    Enum.zip(node_attrs_list, result_nodes)
    |> Enum.each(fn {attrs, node} ->
      from(e in ScreenplayElement, where: e.id in ^attrs.element_ids)
      |> Repo.update_all(set: [linked_node_id: node.id])
    end)
  end

  defp load_page_tree_data(screenplay) do
    elements = ElementCrud.list_elements(screenplay.id)
    children = load_descendant_data(screenplay.id)
    %{screenplay_id: screenplay.id, elements: elements, children: children}
  end

  defp load_descendant_data(parent_id, depth \\ 0)

  defp load_descendant_data(_parent_id, depth) when depth > @max_tree_depth, do: []

  defp load_descendant_data(parent_id, depth) do
    from(s in Screenplay,
      where: s.parent_id == ^parent_id and is_nil(s.deleted_at),
      order_by: [asc: s.position]
    )
    |> Repo.all()
    |> Enum.map(fn child ->
      elements = ElementCrud.list_elements(child.id)
      children = load_descendant_data(child.id, depth + 1)
      %{screenplay_id: child.id, elements: elements, children: children}
    end)
  end
end

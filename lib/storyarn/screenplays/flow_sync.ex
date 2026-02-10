defmodule Storyarn.Screenplays.FlowSync do
  @moduledoc """
  Manages the relationship between screenplays and flows.

  Provides operations to link/unlink screenplays to flows, create flows
  from screenplays, and sync screenplay content to flow nodes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Flows
  alias Storyarn.Flows.{FlowConnection, FlowNode}

  alias Storyarn.Screenplays.{
    ElementCrud,
    ElementGrouping,
    NodeMapping,
    Screenplay,
    ScreenplayElement
  }

  @layout_x 400.0
  @layout_y_start 100.0
  @layout_y_spacing 150.0

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

    elements = ElementCrud.list_elements(screenplay.id)
    groups = ElementGrouping.group_elements(elements)
    node_attrs_list = NodeMapping.groups_to_node_attrs(groups)

    with {:ok, flow} <- ensure_flow(screenplay) do
      do_sync(%{screenplay | project_id: project_id}, flow, node_attrs_list)
    end
  end

  # ---------------------------------------------------------------------------
  # Sync internals
  # ---------------------------------------------------------------------------

  defp do_sync(screenplay, flow, node_attrs_list) do
    Repo.transaction(fn ->
      # Load existing state
      all_nodes = Flows.list_nodes(flow.id)
      synced_nodes = Enum.filter(all_nodes, &(&1.source == "screenplay_sync"))
      entry_node = Enum.find(all_nodes, &(&1.type == "entry"))

      # Build lookups
      element_to_node = build_element_to_node_lookup(screenplay.id)
      synced_by_id = Map.new(synced_nodes, &{&1.id, &1})

      # Create or update nodes
      {result_nodes, matched_ids} =
        Enum.map_reduce(node_attrs_list, MapSet.new(), fn attrs, matched ->
          case find_existing_node(attrs, element_to_node, synced_by_id, entry_node) do
            nil ->
              node = create_sync_node!(flow, attrs)
              {node, matched}

            existing ->
              node = update_sync_node!(existing, attrs)
              {node, MapSet.put(matched, existing.id)}
          end
        end)

      # Delete orphaned synced nodes
      delete_orphaned_nodes!(synced_nodes, matched_ids)

      # Rebuild connections between result nodes
      delete_connections_between!(flow.id, result_nodes)
      create_sequential_connections!(flow, result_nodes)

      # Auto-layout new nodes in vertical stack
      auto_layout_new_nodes!(result_nodes, matched_ids)

      # Update element links
      update_element_links!(node_attrs_list, result_nodes)

      Flows.get_flow!(screenplay.project_id, flow.id)
    end)
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

  defp build_element_to_node_lookup(screenplay_id) do
    from(e in ScreenplayElement,
      where: e.screenplay_id == ^screenplay_id and not is_nil(e.linked_node_id),
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

  defp create_sequential_connections!(flow, result_nodes) do
    result_nodes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [source, target] ->
      unless source.type in ~w(exit jump) do
        if source.type == "condition" do
          create_connection!(flow, source, target, "true", "input")
          create_connection!(flow, source, target, "false", "input")
        else
          create_connection!(flow, source, target, "output", "input")
        end
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

  defp auto_layout_new_nodes!(result_nodes, matched_ids) do
    result_nodes
    |> Enum.with_index()
    |> Enum.each(fn {node, index} ->
      unless MapSet.member?(matched_ids, node.id) do
        node
        |> Ecto.Changeset.change(%{
          position_x: @layout_x,
          position_y: @layout_y_start + index * @layout_y_spacing
        })
        |> Repo.update!()
      end
    end)
  end

  defp update_element_links!(node_attrs_list, result_nodes) do
    Enum.zip(node_attrs_list, result_nodes)
    |> Enum.each(fn {attrs, node} ->
      from(e in ScreenplayElement, where: e.id in ^attrs.element_ids)
      |> Repo.update_all(set: [linked_node_id: node.id])
    end)
  end
end

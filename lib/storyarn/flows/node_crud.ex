defmodule Storyarn.Flows.NodeCrud do
  @moduledoc """
  Facade for node CRUD operations. Delegates to specialized sub-modules:
  - `NodeCreate` - create_node and hub/subflow creation helpers
  - `NodeUpdate` - update_node, update_node_data, update_node_position
  - `NodeDelete` - delete_node, restore_node
  Query helpers (list_nodes, get_node, hub queries, subflow resolution) remain here.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode, NodeCreate, NodeDelete, NodeUpdate}
  alias Storyarn.Repo

  # =============================================================================
  # Query helpers
  # =============================================================================

  def list_nodes(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and is_nil(n.deleted_at),
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  def get_node(flow_id, node_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.id == ^node_id and is_nil(n.deleted_at),
      preload: [:outgoing_connections, :incoming_connections]
    )
    |> Repo.one()
  end

  def get_node!(flow_id, node_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.id == ^node_id and is_nil(n.deleted_at),
      preload: [:outgoing_connections, :incoming_connections]
    )
    |> Repo.one!()
  end

  def get_node_by_id!(node_id) do
    Repo.get!(FlowNode, node_id)
  end

  @doc """
  Checks if a hub_id already exists in a flow (excluding a specific node).
  """
  def hub_id_exists?(flow_id, hub_id, exclude_node_id) do
    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub" and is_nil(n.deleted_at),
        where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
      )

    query =
      if exclude_node_id do
        where(query, [n], n.id != ^exclude_node_id)
      else
        query
      end

    Repo.exists?(query)
  end

  @doc """
  Lists all hub nodes in a flow with their hub_ids.
  Useful for populating Jump node target dropdown.
  """
  def list_hubs(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub" and is_nil(n.deleted_at),
      select: %{
        id: n.id,
        hub_id: fragment("?->>'hub_id'", n.data),
        label: fragment("?->>'label'", n.data)
      },
      order_by: [asc: fragment("?->>'hub_id'", n.data)]
    )
    |> Repo.all()
  end

  @doc """
  Finds a hub node in a flow by its hub_id.
  Returns nil if not found.
  """
  def get_hub_by_hub_id(flow_id, hub_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub" and is_nil(n.deleted_at),
      where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
    )
    |> Repo.one()
  end

  @doc """
  Lists jump nodes that reference a given hub_id within a flow.
  Returns a list of maps with :id and :label (or position info).
  """
  def list_referencing_jumps(flow_id, hub_id) when is_binary(hub_id) and hub_id != "" do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "jump" and is_nil(n.deleted_at),
      where: fragment("?->>'target_hub_id' = ?", n.data, ^hub_id),
      order_by: [asc: n.position_y, asc: n.position_x],
      select: %{id: n.id, position_x: n.position_x, position_y: n.position_y}
    )
    |> Repo.all()
  end

  def list_referencing_jumps(_flow_id, _hub_id), do: []

  @doc """
  Lists all dialogue nodes where a given sheet is the speaker, across a project.
  Returns nodes with their flow preloaded (for navigation links and display).
  """
  def list_dialogue_nodes_by_speaker(project_id, sheet_id) do
    sheet_id_str = to_string(sheet_id)

    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id,
      where: n.type == "dialogue",
      where: is_nil(n.deleted_at),
      where: fragment("?->>'speaker_sheet_id' = ?", n.data, ^sheet_id_str),
      preload: [flow: f],
      order_by: [asc: f.name, asc: n.inserted_at]
    )
    |> Repo.all()
  end

  def count_nodes_by_type(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and is_nil(n.deleted_at),
      group_by: n.type,
      select: {n.type, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Lists all Exit nodes for a given flow.
  Returns a list of maps with :id, :label, :outcome_tags, :outcome_color, and :exit_mode.
  Used by subflow nodes to generate dynamic output pins.
  """
  def list_exit_nodes_for_flow(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "exit" and is_nil(n.deleted_at),
      select: %{
        id: n.id,
        label: fragment("?->>'label'", n.data),
        outcome_tags: fragment("?->'outcome_tags'", n.data),
        outcome_color: fragment("coalesce(?->>'outcome_color', '#22c55e')", n.data),
        exit_mode: fragment("coalesce(?->>'exit_mode', 'terminal')", n.data)
      },
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all unique outcome tags used across exit nodes in a project.
  Used for autocomplete suggestions.
  """
  def list_outcome_tags_for_project(project_id) do
    from(n in FlowNode,
      join: f in assoc(n, :flow),
      where: f.project_id == ^project_id and n.type == "exit",
      where: fragment("jsonb_array_length(coalesce(?->'outcome_tags', '[]'::jsonb)) > 0", n.data),
      select: fragment("jsonb_array_elements_text(?->'outcome_tags')", n.data)
    )
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Finds all subflow nodes that reference a given flow within the same project.
  Used for stale detection when a flow is deleted or exits change.
  """
  def list_subflow_nodes_referencing(flow_id, project_id) do
    flow_id_str = to_string(flow_id)

    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id,
      where: n.type == "subflow",
      where: fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str),
      select: %{id: n.id, flow_id: n.flow_id}
    )
    |> Repo.all()
  end

  @doc """
  Finds all nodes (subflow and exit with flow_reference) that reference a given flow.
  Returns a list of maps with :node_id, :node_type, :flow_id, :flow_name, :flow_shortcut.
  Used by exit nodes to show "Referenced by" section.
  """
  def list_nodes_referencing_flow(flow_id, project_id) do
    flow_id_str = to_string(flow_id)

    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      where:
        (n.type == "subflow" and fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str)) or
          (n.type == "exit" and fragment("?->>'exit_mode'", n.data) == "flow_reference" and
             fragment("?->>'referenced_flow_id' = ?", n.data, ^flow_id_str)),
      select: %{
        node_id: n.id,
        node_type: n.type,
        flow_id: f.id,
        flow_name: f.name,
        flow_shortcut: f.shortcut
      },
      order_by: [asc: f.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists all interaction nodes that reference a given map.
  Used for "Used in N flows" backlinks in the map editor.
  """
  def list_interaction_nodes_for_map(map_id) do
    map_id_str = to_string(map_id)

    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where: n.type == "interaction",
      where: is_nil(n.deleted_at) and is_nil(f.deleted_at),
      where: fragment("?->>'map_id' = ?", n.data, ^map_id_str),
      select: %{
        node_id: n.id,
        flow_id: f.id,
        flow_name: f.name,
        project_id: f.project_id
      },
      order_by: [asc: f.name]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Subflow / exit data resolution
  # =============================================================================

  @doc """
  Pre-fetches all referenced flow data for subflow nodes in a single batch.
  Returns a map of %{flow_id => %{flow: flow, exit_labels: [...]}} for valid refs,
  or an empty map if there are no subflow nodes.
  """
  def batch_resolve_subflow_data(nodes) do
    ref_ids =
      nodes
      |> Enum.filter(&(&1.type == "subflow"))
      |> Enum.map(& &1.data["referenced_flow_id"])
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.map(&safe_to_integer/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ref_ids == [] do
      %{}
    else
      flows =
        from(f in Flow, where: f.id in ^ref_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      exits =
        from(n in FlowNode,
          where: n.flow_id in ^ref_ids and n.type == "exit",
          select: %{
            flow_id: n.flow_id,
            id: n.id,
            label: fragment("?->>'label'", n.data),
            outcome_tags: fragment("?->'outcome_tags'", n.data),
            outcome_color: fragment("coalesce(?->>'outcome_color', '#22c55e')", n.data),
            exit_mode: fragment("coalesce(?->>'exit_mode', 'terminal')", n.data)
          },
          order_by: [asc: n.inserted_at]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.flow_id)

      Map.new(ref_ids, fn id ->
        {id, %{flow: Map.get(flows, id), exit_labels: Map.get(exits, id, [])}}
      end)
    end
  end

  @doc """
  Pre-fetches all referenced map data for interaction nodes in a single batch.
  Returns %{map_id => %{map_name: name, event_zone_names: [...], event_zone_labels: %{...}}}
  """
  def batch_resolve_interaction_data(nodes) do
    map_ids =
      nodes
      |> Enum.filter(&(&1.type == "interaction"))
      |> Enum.map(& &1.data["map_id"])
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.map(&safe_to_integer/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if map_ids == [] do
      %{}
    else
      maps =
        from(m in Storyarn.Maps.Map,
          where: m.id in ^map_ids and is_nil(m.deleted_at),
          select: {m.id, m.name}
        )
        |> Repo.all()
        |> Map.new()

      zones =
        from(z in Storyarn.Maps.MapZone,
          where: z.map_id in ^map_ids and z.action_type == "event",
          select: %{map_id: z.map_id, action_data: z.action_data}
        )
        |> Repo.all()
        |> Enum.group_by(& &1.map_id)

      Map.new(map_ids, fn id ->
        zone_list = Map.get(zones, id, [])

        {id,
         %{
           map_name: Map.get(maps, id),
           event_zone_names: Enum.map(zone_list, & &1.action_data["event_name"]),
           event_zone_labels:
             Map.new(zone_list, fn z ->
               {z.action_data["event_name"],
                z.action_data["label"] || z.action_data["event_name"]}
             end)
         }}
      end)
    end
  end

  @doc """
  Resolves subflow node data by enriching it with referenced flow info.
  Uses pre-fetched cache from batch_resolve_subflow_data/1.
  """
  def resolve_subflow_data(data, subflow_cache) do
    case data["referenced_flow_id"] do
      nil ->
        data

      "" ->
        data

      ref_id ->
        case safe_to_integer(ref_id) do
          nil ->
            data

          int_id ->
            cached = Map.get(subflow_cache, int_id, :not_cached)
            resolve_subflow_from_cached(data, int_id, cached)
        end
    end
  end

  defp resolve_subflow_from_cached(data, int_id, :not_cached) do
    # Fallback for single-node resolution (no batch cache available)
    case Repo.get(Flow, int_id) do
      nil ->
        mark_stale_subflow(data)

      %Flow{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        mark_stale_subflow(data)

      flow ->
        exit_labels = list_exit_nodes_for_flow(flow.id)
        enrich_subflow_data(data, flow, exit_labels)
    end
  end

  defp resolve_subflow_from_cached(data, _int_id, %{flow: nil}),
    do: mark_stale_subflow(data)

  defp resolve_subflow_from_cached(data, _int_id, %{flow: %Flow{deleted_at: d}})
       when not is_nil(d),
       do: mark_stale_subflow(data)

  defp resolve_subflow_from_cached(data, _int_id, %{flow: flow, exit_labels: exit_labels}),
    do: enrich_subflow_data(data, flow, exit_labels)

  defp enrich_subflow_data(data, flow, exit_labels) do
    data
    |> Map.put("stale_reference", false)
    |> Map.put("referenced_flow_name", flow.name)
    |> Map.put("referenced_flow_shortcut", flow.shortcut)
    |> Map.put("exit_labels", exit_labels)
  end

  defp mark_stale_subflow(data) do
    data
    |> Map.put("stale_reference", true)
    |> Map.put("referenced_flow_name", nil)
    |> Map.put("referenced_flow_shortcut", nil)
    |> Map.put("exit_labels", [])
  end

  @doc """
  Resolves exit node data by enriching it with referenced flow info when exit_mode is flow_reference.
  """
  def resolve_exit_data(%{"exit_mode" => "flow_reference"} = data) do
    with ref_id when ref_id not in [nil, ""] <- data["referenced_flow_id"],
         int_id when is_integer(int_id) <- safe_to_integer(ref_id),
         %Flow{deleted_at: nil} = flow <- Repo.get(Flow, int_id) do
      data
      |> Map.put("stale_reference", false)
      |> Map.put("referenced_flow_name", flow.name)
      |> Map.put("referenced_flow_shortcut", flow.shortcut)
    else
      nil ->
        data

      "" ->
        data

      %Flow{} ->
        mark_stale_reference(data)

      _ ->
        mark_stale_reference(data)
    end
  end

  def resolve_exit_data(data), do: data

  defp mark_stale_reference(data) do
    data
    |> Map.put("stale_reference", true)
    |> Map.put("referenced_flow_name", nil)
    |> Map.put("referenced_flow_shortcut", nil)
  end

  @doc """
  Safely converts a string or integer to integer.
  Returns nil if the value cannot be parsed.
  """
  def safe_to_integer(value) when is_integer(value), do: value

  def safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def safe_to_integer(_), do: nil

  # =============================================================================
  # Delegated operations
  # =============================================================================

  defdelegate create_node(flow, attrs), to: NodeCreate
  defdelegate has_circular_reference?(source_flow_id, target_flow_id), to: NodeCreate

  defdelegate update_node(node, attrs), to: NodeUpdate
  defdelegate update_node_position(node, attrs), to: NodeUpdate
  defdelegate batch_update_positions(flow_id, positions), to: NodeUpdate
  defdelegate update_node_data(node, data), to: NodeUpdate
  defdelegate change_node(node, attrs \\ %{}), to: NodeUpdate

  defdelegate delete_node(node), to: NodeDelete
  defdelegate restore_node(flow_id, node_id), to: NodeDelete
end

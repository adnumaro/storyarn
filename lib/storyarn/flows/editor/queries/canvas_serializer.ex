defmodule Storyarn.Flows.Editor.Queries.CanvasSerializer do
  @moduledoc """
  Projects the authored Flow aggregate into the stable editor canvas contract.

  This projection is Flow-owned so full canvas loads and incremental node
  events resolve colors and editorial health flags identically.
  """

  alias Storyarn.Flows.Editor.Queries.Nodes
  alias Storyarn.Flows.Expressions
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Health
  alias Storyarn.Flows.HubColors
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.References
  alias Storyarn.Repo

  @spec serialize_editor_node(FlowNode.t(), pos_integer()) :: map()
  def serialize_editor_node(%FlowNode{type: "sequence"} = node, _project_id) do
    node = Repo.preload(node, :sequence_config)
    config = node.sequence_config

    %{
      id: node.id,
      type: node.type,
      parent_id: node.parent_id,
      position: %{x: node.position_x, y: node.position_y},
      data: %{
        "name" => config && config.name,
        "width" => config && config.width,
        "height" => config && config.height
      }
    }
  end

  def serialize_editor_node(%FlowNode{} = node, project_id) when is_integer(project_id) and project_id > 0 do
    variable_types =
      if node.type in ["instruction", "dialogue"] do
        project_id
        |> Expressions.list_referenceable_variables()
        |> Expressions.variable_type_map()
      else
        %{}
      end

    %{
      id: node.id,
      type: node.type,
      parent_id: node.parent_id,
      position: %{x: node.position_x, y: node.position_y},
      data:
        node.type
        |> resolve_node_colors(node.data || %{})
        |> Health.add_type_warning_health_flag(node.type, variable_types)
    }
  end

  @spec serialize_for_canvas(Flow.t(), keyword()) :: map()
  def serialize_for_canvas(%Flow{} = flow, opts \\ []) do
    stale_node_ids = References.list_stale_node_ids(flow.id)

    # Defaults to the FULL referenceable set, not just sheet blocks: a caller that
    # forgets the option would otherwise silently type-check against a smaller
    # vocabulary than the editor uses, and report different findings for it.
    # ONE map for the whole flow. Built per node this was 96% of the project
    # health sweep and a 15× penalty on flow open; the option still takes the
    # variable LIST because that is what callers already hold.
    project_variables =
      opts[:project_variables] || Expressions.list_referenceable_variables(flow.project_id)

    variable_types = Expressions.variable_type_map(project_variables)

    # Sequences now live in flow.nodes with type='sequence'. Preload their
    # 1:1 config to expose name/width/height alongside the base fields.
    nodes = Repo.preload(flow.nodes, :sequence_config)
    active_connections = active_graph_connections(nodes, flow.connections)

    subflow_cache = Nodes.batch_resolve_subflow_data(flow.nodes, flow.project_id)
    exit_cache = Nodes.batch_resolve_exit_data(flow.nodes, flow.project_id)
    referencing_flows = Nodes.list_nodes_referencing_flow(flow.id, flow.project_id)

    cache = %{subflow: subflow_cache, exit: exit_cache, project_id: flow.project_id}

    resolved_node_data =
      Map.new(nodes, fn node ->
        {node.id, resolve_node_colors(node.type, node.data, cache)}
      end)

    graph_nodes =
      Enum.map(nodes, &%{id: &1.id, type: &1.type, data: Map.fetch!(resolved_node_data, &1.id)})

    graph = Health.compute_structural_graph(graph_nodes, active_connections)

    %{
      id: flow.id,
      name: flow.name,
      nodes:
        Enum.map(nodes, fn node ->
          serialize_node(node, %{
            cache: cache,
            resolved_node_data: resolved_node_data,
            stale_node_ids: stale_node_ids,
            variable_types: variable_types,
            referencing_flows: referencing_flows,
            unreachable_ids: graph.unreachable_ids,
            dead_end_ids: graph.dead_end_ids,
            connected_output_pins: graph.connected_output_pins,
            invalid_output_pins: graph.invalid_output_pins,
            invalid_input_pins: graph.invalid_input_pins
          })
        end),
      connections:
        Enum.map(active_connections, fn connection ->
          %{
            id: connection.id,
            source_node_id: connection.source_node_id,
            source_pin: connection.source_pin,
            target_node_id: connection.target_node_id,
            target_pin: connection.target_pin,
            label: connection.label
          }
        end)
    }
  end

  @spec resolve_node_colors(String.t(), map()) :: map()
  def resolve_node_colors(type, data), do: resolve_node_colors(type, data, %{})

  @spec resolve_node_colors(String.t(), map(), map()) :: map()
  def resolve_node_colors("hub", data, _cache) do
    Map.put(data, "color_hex", HubColors.resolve(data["color"]))
  end

  def resolve_node_colors("subflow", data, cache) do
    subflow_cache = Map.get(cache, :subflow, %{})
    Nodes.resolve_subflow_data(data, subflow_cache)
  end

  def resolve_node_colors("exit", data, cache) do
    Nodes.resolve_exit_data(data, Map.get(cache, :project_id), Map.get(cache, :exit, %{}))
  end

  def resolve_node_colors(_type, data, _cache), do: data

  defp active_graph_connections(nodes, connections) do
    node_ids = MapSet.new(nodes, & &1.id)

    Enum.filter(connections, fn connection ->
      MapSet.member?(node_ids, connection.source_node_id) and
        MapSet.member?(node_ids, connection.target_node_id)
    end)
  end

  defp serialize_node(%FlowNode{type: "sequence"} = node, context) do
    config = node.sequence_config

    data =
      maybe_add_connection_pin_errors(
        %{
          "name" => config && config.name,
          "width" => config && config.width,
          "height" => config && config.height
        },
        Map.get(context.invalid_output_pins, node.id, []),
        Map.get(context.invalid_input_pins, node.id, [])
      )

    %{
      id: node.id,
      type: "sequence",
      position: %{x: node.position_x, y: node.position_y},
      data: data,
      parent_id: node.parent_id
    }
  end

  defp serialize_node(%FlowNode{} = node, context) do
    data =
      context.resolved_node_data
      |> Map.fetch!(node.id)
      |> Health.add_stale_health_flag(node.id, context.stale_node_ids)
      |> Health.add_type_warning_health_flag(node.type, context.variable_types)
      |> maybe_add_referencing_flows(node.type, context.referencing_flows)
      |> maybe_add_unreachable_flag(node.id, node.type, context.unreachable_ids)
      |> maybe_add_dead_end_flag(node.id, node.type, context.dead_end_ids)
      |> maybe_add_missing_output_pins(
        node.id,
        node.type,
        Map.get(context.connected_output_pins, node.id, MapSet.new())
      )
      |> maybe_add_connection_pin_errors(
        Map.get(context.invalid_output_pins, node.id, []),
        Map.get(context.invalid_input_pins, node.id, [])
      )

    %{
      id: node.id,
      type: node.type,
      position: %{x: node.position_x, y: node.position_y},
      data: data,
      parent_id: node.parent_id
    }
  end

  defp maybe_add_referencing_flows(data, "entry", referencing_flows) do
    references =
      Enum.map(referencing_flows, fn reference ->
        %{
          "flow_id" => reference.flow_id,
          "flow_name" => reference.flow_name,
          "flow_shortcut" => reference.flow_shortcut,
          "node_type" => to_string(reference.node_type)
        }
      end)

    Map.put(data, "referencing_flows", references)
  end

  defp maybe_add_referencing_flows(data, _type, _referencing_flows), do: data

  defp maybe_add_unreachable_flag(data, id, type, unreachable_ids) do
    if NodeConnectionRules.can_be_unreachable?(type) and MapSet.member?(unreachable_ids, id),
      do: Map.put(data, "unreachable", true),
      else: data
  end

  defp maybe_add_dead_end_flag(data, id, type, dead_end_ids) do
    if NodeConnectionRules.needs_outgoing_connection?(type) and MapSet.member?(dead_end_ids, id),
      do: Map.put(data, "dead_end", true),
      else: data
  end

  defp maybe_add_missing_output_pins(data, _id, type, _connected_pins) when type in ~w(exit jump annotation sequence),
    do: data

  defp maybe_add_missing_output_pins(data, _id, type, connected_pins) do
    missing_pins =
      type
      |> NodeConnectionRules.output_pins(data)
      |> Enum.reject(&MapSet.member?(connected_pins, &1))

    if missing_pins == [] do
      data
    else
      Map.put(data, "missing_output_pins", missing_pins)
    end
  end

  defp maybe_add_connection_pin_errors(data, [], []), do: data

  defp maybe_add_connection_pin_errors(data, invalid_output_pins, invalid_input_pins) do
    data
    |> maybe_put_non_empty("invalid_output_pins", invalid_output_pins)
    |> maybe_put_non_empty("invalid_input_pins", invalid_input_pins)
  end

  defp maybe_put_non_empty(data, _key, []), do: data
  defp maybe_put_non_empty(data, key, values), do: Map.put(data, key, values)
end

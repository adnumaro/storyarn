defmodule Storyarn.Flows.Editor.Commands.NodeRestore do
  @moduledoc false

  alias Storyarn.Flows.ConnectionCrud
  alias Storyarn.Flows.Editor.Queries.CanvasSerializer
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud

  @doc "Restores a node and returns the active graph fragment needed by the editor adapter."
  def restore_editor_node(%Flow{} = flow, node_id) do
    case NodeCrud.restore_node(flow.id, node_id) do
      {:ok, %FlowNode{} = node} ->
        connections =
          flow.id
          |> ConnectionCrud.list_connections()
          |> Enum.filter(&(&1.source_node_id == node.id or &1.target_node_id == node.id))
          |> Enum.map(fn connection ->
            %{
              id: connection.id,
              source_node_id: connection.source_node_id,
              source_pin: connection.source_pin,
              target_node_id: connection.target_node_id,
              target_pin: connection.target_pin,
              label: connection.label
            }
          end)

        {:ok,
         %{
           node: CanvasSerializer.serialize_editor_node(node, flow.project_id),
           connections: connections
         }}

      other ->
        other
    end
  end
end

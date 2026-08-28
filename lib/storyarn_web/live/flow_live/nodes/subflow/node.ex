defmodule StoryarnWeb.FlowLive.Nodes.Subflow.Node do
  @moduledoc """
  Subflow node type definition.

  References another flow in the project, creating visual and functional links
  between flows. Double-click navigates to the referenced flow. Dynamic output
  pins are generated from the referenced flow's Exit nodes.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "subflow"
  def icon_name, do: "box"
  def label, do: dgettext("flows", "Subflow")
  def description, do: dgettext("flows", "Embed another flow as a node")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  @doc "Loads available flows and exit nodes when a subflow node is selected."
  def on_select(node, socket) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id

    available_flows = Flows.search_flows(project_id, "", exclude_id: current_flow_id)

    exit_nodes =
      case node.data["referenced_flow_id"] do
        nil ->
          []

        "" ->
          []

        flow_id ->
          case Flows.safe_to_integer(flow_id) do
            nil -> []
            id -> Flows.list_exit_nodes_for_flow(id)
          end
      end

    socket
    |> assign(:available_flows, available_flows)
    |> assign(:subflow_exits, exit_nodes)
  end

  def on_double_click(_node), do: :toolbar

  @doc "Keep reference on duplicate."
  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)

  @doc "Handles updating the referenced flow from the sidebar dropdown."
  def handle_update_reference(ref_id, socket) do
    node = socket.assigns.selected_node

    if node do
      do_update_reference(node, ref_id, socket)
    else
      {:noreply, socket}
    end
  end

  defp do_update_reference(node, ref_id, socket) do
    persist_reference(node, ref_id, socket)
  end

  defp persist_reference(node, flow_id, socket) do
    case NodeHelpers.persist_node_update(socket, node.id, :put_subflow_reference, %{value: flow_id}) do
      {:noreply, updated_socket} ->
        current_flow_id = updated_socket.assigns.selected_node.data["referenced_flow_id"]
        exit_nodes = load_exit_nodes(current_flow_id)
        {:noreply, assign(updated_socket, :subflow_exits, exit_nodes)}

      other ->
        other
    end
  end

  defp load_exit_nodes(nil), do: []
  defp load_exit_nodes(id), do: Flows.list_exit_nodes_for_flow(id)
end

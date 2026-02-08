defmodule StoryarnWeb.FlowLive.Nodes.Subflow.Node do
  @moduledoc """
  Subflow node type definition.

  References another flow in the project, creating visual and functional links
  between flows. Double-click navigates to the referenced flow. Dynamic output
  pins are generated from the referenced flow's Exit nodes.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Flows
  alias Storyarn.Flows.NodeCrud
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "subflow"
  def icon_name, do: "box"
  def label, do: gettext("Subflow")

  def default_data, do: %{"referenced_flow_id" => nil}

  def extract_form_data(data) do
    %{"referenced_flow_id" => data["referenced_flow_id"]}
  end

  @doc "Loads available flows and exit nodes when a subflow node is selected."
  def on_select(node, socket) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id

    available_flows =
      Flows.list_flows(project_id)
      |> Enum.reject(&(&1.id == current_flow_id))

    exit_nodes =
      case node.data["referenced_flow_id"] do
        nil -> []
        "" -> []
        flow_id ->
          case NodeCrud.safe_to_integer(flow_id) do
            nil -> []
            id -> Flows.list_exit_nodes_for_flow(id)
          end
      end

    socket
    |> assign(:available_flows, available_flows)
    |> assign(:subflow_exits, exit_nodes)
  end

  @doc "Double-click navigates to the referenced flow, or opens sidebar if no reference."
  def on_double_click(node) do
    case node.data["referenced_flow_id"] do
      nil -> :sidebar
      "" -> :sidebar
      flow_id -> {:navigate, flow_id}
    end
  end

  @doc "Keep reference on duplicate."
  def duplicate_data_cleanup(data), do: data

  @doc "Handles updating the referenced flow from the sidebar dropdown."
  def handle_update_reference(ref_id, socket) do
    node = socket.assigns.selected_node

    if node do
      ref_id = if ref_id == "" || is_nil(ref_id), do: nil, else: ref_id
      current_flow_id = socket.assigns.flow.id
      parsed_ref_id = if ref_id, do: NodeCrud.safe_to_integer(ref_id)

      cond do
        ref_id && is_nil(parsed_ref_id) ->
          {:noreply, put_flash(socket, :error, gettext("Invalid flow reference."))}

        ref_id && parsed_ref_id == current_flow_id ->
          {:noreply, put_flash(socket, :error, gettext("A flow cannot reference itself."))}

        ref_id && Flows.has_circular_reference?(current_flow_id, parsed_ref_id) ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Circular reference detected. This flow is already referenced by the target.")
           )}

        true ->
          case NodeHelpers.persist_node_update(socket, node.id, fn data ->
                 Map.put(data, "referenced_flow_id", ref_id)
               end) do
            {:noreply, updated_socket} ->
              exit_nodes =
                case parsed_ref_id do
                  nil -> []
                  id -> Flows.list_exit_nodes_for_flow(id)
                end

              {:noreply, assign(updated_socket, :subflow_exits, exit_nodes)}

            other ->
              other
          end
      end
    else
      {:noreply, socket}
    end
  end
end

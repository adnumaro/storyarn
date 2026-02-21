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
  def label, do: dgettext("flows", "Subflow")

  def default_data, do: %{"referenced_flow_id" => nil}

  def extract_form_data(data) do
    %{"referenced_flow_id" => data["referenced_flow_id"]}
  end

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
          case NodeCrud.safe_to_integer(flow_id) do
            nil -> []
            id -> Flows.list_exit_nodes_for_flow(id)
          end
      end

    socket
    |> assign(:available_flows, available_flows)
    |> assign(:subflow_exits, exit_nodes)
  end

  @doc "Double-click navigates to the referenced flow, or shows toolbar if no reference."
  def on_double_click(node) do
    case node.data["referenced_flow_id"] do
      nil -> :toolbar
      "" -> :toolbar
      flow_id -> {:navigate, flow_id}
    end
  end

  @doc "Keep reference on duplicate."
  def duplicate_data_cleanup(data), do: data

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
    ref_id = if ref_id == "" || is_nil(ref_id), do: nil, else: ref_id

    case validate_reference(ref_id, socket.assigns.flow.id) do
      :ok -> persist_reference(node, ref_id, socket)
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp validate_reference(nil, _current_flow_id), do: :ok

  defp validate_reference(ref_id, current_flow_id) do
    parsed = NodeCrud.safe_to_integer(ref_id)

    cond do
      is_nil(parsed) ->
        {:error, dgettext("flows", "Invalid flow reference.")}

      parsed == current_flow_id ->
        {:error, dgettext("flows", "A flow cannot reference itself.")}

      Flows.has_circular_reference?(current_flow_id, parsed) ->
        {:error,
         dgettext(
           "flows",
           "Circular reference detected. This flow is already referenced by the target."
         )}

      true ->
        :ok
    end
  end

  defp persist_reference(node, ref_id, socket) do
    parsed_ref_id = if ref_id, do: NodeCrud.safe_to_integer(ref_id)

    case NodeHelpers.persist_node_update(socket, node.id, fn data ->
           Map.put(data, "referenced_flow_id", ref_id)
         end) do
      {:noreply, updated_socket} ->
        exit_nodes = load_exit_nodes(parsed_ref_id)
        {:noreply, assign(updated_socket, :subflow_exits, exit_nodes)}

      other ->
        other
    end
  end

  defp load_exit_nodes(nil), do: []
  defp load_exit_nodes(id), do: Flows.list_exit_nodes_for_flow(id)
end

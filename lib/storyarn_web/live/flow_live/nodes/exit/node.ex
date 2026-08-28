defmodule StoryarnWeb.FlowLive.Nodes.Exit.Node do
  @moduledoc """
  Exit node type definition.

  Represents a flow endpoint with outcome tags, color, and exit mode
  (terminal, flow_reference, or caller_return).
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "exit"
  def icon_name, do: "arrow-right-to-line"
  def label, do: dgettext("flows", "Exit")
  def description, do: dgettext("flows", "End point of a flow")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  def on_select(node, socket) do
    project_id = socket.assigns.project.id
    flow_id = socket.assigns.flow.id

    existing_tags = Flows.list_outcome_tags_for_project(project_id)
    referencing_flows = Flows.list_nodes_referencing_flow(flow_id, project_id)

    socket =
      socket
      |> Phoenix.Component.assign(:outcome_tags_suggestions, existing_tags)
      |> Phoenix.Component.assign(:referencing_flows, referencing_flows)

    case node.data["exit_mode"] do
      "flow_reference" ->
        available_flows = Flows.search_flows(project_id, "", exclude_id: flow_id)
        Phoenix.Component.assign(socket, :available_flows, available_flows)

      "terminal" ->
        available_scenes = Flows.search_exit_target_scenes(project_id, "")
        available_flows = Flows.search_flows(project_id, "", exclude_id: flow_id)

        socket
        |> Phoenix.Component.assign(:available_scenes, available_scenes)
        |> Phoenix.Component.assign(:available_flows, available_flows)

      _ ->
        socket
    end
  end

  def on_double_click(_node), do: :toolbar

  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)

  # -- Exit-specific event handlers --

  @doc "Updates exit mode (terminal, flow_reference, caller_return)."
  def handle_update_exit_mode(mode, socket) do
    node = socket.assigns.selected_node
    validated_mode = Flows.exit_mode(mode)

    socket
    |> NodeHelpers.persist_node_update(node.id, :put_exit_mode, %{value: mode})
    |> then(fn {:noreply, socket} ->
      project_id = socket.assigns.project.id
      current_flow_id = socket.assigns.flow.id

      case validated_mode do
        "flow_reference" ->
          available_flows = Flows.search_flows(project_id, "", exclude_id: current_flow_id)
          {:noreply, Phoenix.Component.assign(socket, :available_flows, available_flows)}

        "terminal" ->
          available_scenes = Flows.search_exit_target_scenes(project_id, "")
          available_flows = Flows.search_flows(project_id, "", exclude_id: current_flow_id)

          {:noreply,
           socket
           |> Phoenix.Component.assign(:available_scenes, available_scenes)
           |> Phoenix.Component.assign(:available_flows, available_flows)}

        _ ->
          {:noreply, socket}
      end
    end)
  end

  @doc "Updates exit flow reference."
  def handle_update_exit_reference(flow_id_str, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :put_exit_flow_reference, %{
      value: flow_id_str
    })
  end

  @doc "Adds an outcome tag."
  def handle_add_outcome_tag(tag, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :add_exit_outcome_tag, %{value: tag})
  end

  @doc "Removes an outcome tag."
  def handle_remove_outcome_tag(tag, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :remove_exit_outcome_tag, %{value: tag})
  end

  @doc "Updates outcome color."
  def handle_update_outcome_color(color, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :put_exit_color, %{value: color})
  end

  @doc "Updates exit target (scene or flow transition on terminal exit)."
  def handle_update_exit_target(%{"target_type" => type, "target_id" => id}, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :put_exit_target, %{
      target_type: type,
      target_id: id
    })
  end

  @doc "Generates a technical ID for an exit node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, :generate_technical_id)
  end
end

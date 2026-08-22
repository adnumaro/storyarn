defmodule StoryarnWeb.FlowLive.Nodes.Condition.Node do
  @moduledoc """
  Condition node type definition.

  Evaluates conditions to route flow. Supports boolean (true/false) and
  switch mode (multiple labeled outputs).
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "condition"
  def icon_name, do: "git-branch"
  def label, do: dgettext("flows", "Condition")
  def description, do: dgettext("flows", "Branch based on variable conditions")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :builder
  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)

  # -- Condition-specific event handlers --

  @doc "Handles full-state push from the JS condition builder hook."
  def handle_update_condition_builder(%{"condition" => condition_data}, socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, :put_condition, %{
        condition: condition_data
      })
    else
      {:noreply, socket}
    end
  end

  def handle_update_condition_builder(_params, socket) do
    {:noreply, socket}
  end

  @doc "Handles full-state push from JS hook for response conditions."
  def handle_update_response_condition_builder(
        %{"condition" => condition_data, "response-id" => response_id, "node-id" => node_id},
        socket
      ) do
    if node_id && response_id do
      NodeHelpers.persist_node_update(socket, node_id, :put_response_condition_builder, %{
        response_id: response_id,
        condition: condition_data
      })
    else
      {:noreply, socket}
    end
  end

  def handle_update_response_condition_builder(_params, socket) do
    {:noreply, socket}
  end

  @doc "Toggles switch mode on a condition node."
  def handle_toggle_switch_mode(socket) do
    node = socket.assigns.selected_node

    if node && node.type == "condition" do
      NodeHelpers.persist_node_update(socket, node.id, :toggle_condition_switch_mode)
    else
      {:noreply, socket}
    end
  end
end

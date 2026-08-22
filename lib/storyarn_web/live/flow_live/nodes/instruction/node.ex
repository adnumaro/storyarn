defmodule StoryarnWeb.FlowLive.Nodes.Instruction.Node do
  @moduledoc """
  Instruction node type definition.

  Sets variable values when executed. Contains assignments and a description.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "instruction"
  def icon_name, do: "zap"
  def label, do: dgettext("flows", "Instruction")
  def description, do: dgettext("flows", "Set or modify variable values")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :builder
  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)

  # -- Instruction-specific event handlers --

  @doc "Handles updates from the instruction builder JS hook."
  def handle_update_instruction_builder(%{"assignments" => assignments}, socket) do
    node = socket.assigns.selected_node

    if node && node.type == "instruction" do
      NodeHelpers.persist_node_update(socket, node.id, :put_instruction_assignments, %{
        assignments: assignments
      })
    else
      {:noreply, socket}
    end
  end

  def handle_update_instruction_builder(_params, socket) do
    {:noreply, socket}
  end
end

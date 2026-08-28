defmodule StoryarnWeb.FlowLive.Nodes.Hub.Node do
  @moduledoc """
  Hub node type definition.

  A named target that Jump nodes can reference. Has a hub_id, label, and color.
  On selection, loads referencing jump nodes.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows

  def type, do: "hub"
  def icon_name, do: "log-in"
  def label, do: dgettext("flows", "Hub")
  def description, do: dgettext("flows", "Named junction for jump targets")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  @doc "Loads referencing jump nodes when a hub is selected."
  def on_select(node, socket) do
    referencing_jumps =
      Flows.list_referencing_jumps(socket.assigns.flow.id, node.data["hub_id"] || "")

    assign(socket, :referencing_jumps, referencing_jumps)
  end

  def on_double_click(_node), do: :toolbar

  @doc "Clears hub_id when duplicating (must be unique)."
  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)
end

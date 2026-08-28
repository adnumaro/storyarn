defmodule StoryarnWeb.FlowLive.Nodes.Jump.Node do
  @moduledoc """
  Jump node type definition.

  References a Hub node by target_hub_id to create non-linear flow paths.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows

  def type, do: "jump"
  def icon_name, do: "log-out"
  def label, do: dgettext("flows", "Jump")
  def description, do: dgettext("flows", "Jump to a hub in any flow")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :toolbar
  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)
end

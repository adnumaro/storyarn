defmodule StoryarnWeb.FlowLive.Nodes.Entry.Node do
  @moduledoc """
  Entry node type definition.

  The entry point of a flow. Cannot be deleted or duplicated.
  Auto-created with the flow.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  def type, do: "entry"
  def icon_name, do: "play"
  def label, do: gettext("Entry")
  def default_data, do: %{}

  def extract_form_data(_data), do: %{}

  @doc "Entry nodes have no special selection behavior."
  def on_select(_node, socket), do: socket

  @doc "Entry nodes open sidebar on double-click."
  def on_double_click(_node), do: :sidebar

  @doc "Entry nodes cannot be duplicated, but define cleanup for safety."
  def duplicate_data_cleanup(data), do: data
end

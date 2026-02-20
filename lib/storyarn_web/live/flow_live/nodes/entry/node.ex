defmodule StoryarnWeb.FlowLive.Nodes.Entry.Node do
  @moduledoc """
  Entry node type definition.

  The entry point of a flow. Cannot be deleted or duplicated.
  Auto-created with the flow.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows

  def type, do: "entry"
  def icon_name, do: "play"
  def label, do: dgettext("flows", "Entry")
  def default_data, do: %{}

  def extract_form_data(_data), do: %{}

  def on_select(_node, socket) do
    flow_id = socket.assigns.flow.id
    project_id = socket.assigns.project.id
    referencing_flows = Flows.list_nodes_referencing_flow(flow_id, project_id)

    Phoenix.Component.assign(socket, :referencing_flows, referencing_flows)
  end

  @doc "Entry nodes show toolbar on double-click."
  def on_double_click(_node), do: :toolbar

  @doc "Entry nodes cannot be duplicated, but define cleanup for safety."
  def duplicate_data_cleanup(data), do: data
end

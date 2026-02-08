defmodule StoryarnWeb.FlowLive.Nodes.Hub.Node do
  @moduledoc """
  Hub node type definition.

  A named target that Jump nodes can reference. Has a hub_id, label, and color.
  On selection, loads referencing jump nodes.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows

  def type, do: "hub"
  def icon_name, do: "log-in"
  def label, do: gettext("Hub")

  def default_data, do: %{"hub_id" => "", "label" => "", "color" => "#8b5cf6"}

  def extract_form_data(data) do
    %{
      "hub_id" => data["hub_id"] || "",
      "label" => data["label"] || "",
      "color" => data["color"] || "#8b5cf6"
    }
  end

  @doc "Loads referencing jump nodes when a hub is selected."
  def on_select(node, socket) do
    referencing_jumps =
      Flows.list_referencing_jumps(socket.assigns.flow.id, node.data["hub_id"] || "")

    assign(socket, :referencing_jumps, referencing_jumps)
  end

  def on_double_click(_node), do: :sidebar

  @doc "Clears hub_id when duplicating (must be unique)."
  def duplicate_data_cleanup(data) do
    Map.put(data, "hub_id", "")
  end
end

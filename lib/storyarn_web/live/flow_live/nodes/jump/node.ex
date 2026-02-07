defmodule StoryarnWeb.FlowLive.Nodes.Jump.Node do
  @moduledoc """
  Jump node type definition.

  References a Hub node by target_hub_id to create non-linear flow paths.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  def type, do: "jump"
  def icon_name, do: "log-out"
  def label, do: gettext("Jump")

  def default_data, do: %{"target_hub_id" => ""}

  def extract_form_data(data) do
    %{"target_hub_id" => data["target_hub_id"] || ""}
  end

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :sidebar
  def duplicate_data_cleanup(data), do: data
end

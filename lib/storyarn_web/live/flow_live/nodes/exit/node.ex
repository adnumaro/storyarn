defmodule StoryarnWeb.FlowLive.Nodes.Exit.Node do
  @moduledoc """
  Exit node type definition.

  Represents a flow endpoint. Has label, technical_id, and is_success flag.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  def type, do: "exit"
  def icon_name, do: "square"
  def label, do: gettext("Exit")

  def default_data do
    %{"label" => "", "technical_id" => "", "is_success" => true}
  end

  def extract_form_data(data) do
    %{
      "label" => data["label"] || "",
      "technical_id" => data["technical_id"] || "",
      "is_success" => data["is_success"] != false
    }
  end

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :sidebar

  def duplicate_data_cleanup(data) do
    Map.put(data, "technical_id", "")
  end

  # -- Exit-specific event handlers --

  @doc "Generates a technical ID for an exit node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node
    flow = socket.assigns.flow
    exit_count = count_exit_in_flow(flow, node.id)
    label = node.data["label"]
    technical_id = generate_exit_technical_id(flow.shortcut, label, exit_count)

    NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
  end

  # Private helpers

  defp count_exit_in_flow(flow, current_node_id) do
    flow = Repo.preload(flow, :nodes)

    exit_nodes =
      flow.nodes
      |> Enum.filter(&(&1.type == "exit"))
      |> Enum.sort_by(& &1.inserted_at)

    case Enum.find_index(exit_nodes, &(&1.id == current_node_id)) do
      nil -> length(exit_nodes) + 1
      index -> index + 1
    end
  end

  defp generate_exit_technical_id(flow_slug, label, exit_count) do
    flow_part = normalize_for_id(flow_slug || "")
    label_part = normalize_for_id(label || "")
    flow_part = if flow_part == "", do: "flow", else: flow_part
    label_part = if label_part == "", do: "exit", else: label_part
    "#{flow_part}_#{label_part}_#{exit_count}"
  end

  defp normalize_for_id(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_for_id(_), do: ""
end

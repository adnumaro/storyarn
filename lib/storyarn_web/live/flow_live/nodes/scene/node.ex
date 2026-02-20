defmodule StoryarnWeb.FlowLive.Nodes.Scene.Node do
  @moduledoc """
  Scene node type definition.

  A pass-through node (1 input, 1 output) that establishes location and time
  context — the screenplay concept of a slug line. References a location sheet
  via `location_sheet_id` and displays INT/EXT, sub-location, and time of day.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  # -- Type metadata --

  def type, do: "scene"
  def icon_name, do: "clapperboard"
  def label, do: dgettext("flows", "Scene")

  def default_data do
    %{
      "location_sheet_id" => nil,
      "int_ext" => "int",
      "sub_location" => "",
      "time_of_day" => "",
      "description" => "",
      "technical_id" => ""
    }
  end

  def extract_form_data(data) do
    %{
      "location_sheet_id" => data["location_sheet_id"] || "",
      "int_ext" => data["int_ext"] || "int",
      "sub_location" => data["sub_location"] || "",
      "time_of_day" => data["time_of_day"] || "",
      "description" => data["description"] || "",
      "technical_id" => data["technical_id"] || ""
    }
  end

  def on_select(_node, socket), do: socket
  def on_double_click(_node), do: :toolbar

  def duplicate_data_cleanup(data) do
    Map.put(data, "technical_id", "")
  end

  # -- Technical ID generation --

  @doc "Generates a technical ID for a scene node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node
    flow = socket.assigns.flow
    location_name = get_location_name(socket, node.data["location_sheet_id"])
    int_ext = node.data["int_ext"] || "int"
    scene_count = count_scene_in_flow(flow, node.id)
    technical_id = generate_scene_technical_id(flow.shortcut, int_ext, location_name, scene_count)

    NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
  end

  # -- Private helpers --

  defp get_location_name(_socket, nil), do: nil

  defp get_location_name(socket, location_sheet_id) do
    Enum.find_value(socket.assigns.all_sheets, fn sheet ->
      if to_string(sheet.id) == to_string(location_sheet_id), do: sheet.name
    end)
  end

  defp count_scene_in_flow(flow, current_node_id) do
    flow = if Ecto.assoc_loaded?(flow.nodes), do: flow, else: Repo.preload(flow, :nodes)

    scene_nodes =
      flow.nodes
      |> Enum.filter(&(&1.type == "scene"))
      |> Enum.sort_by(& &1.inserted_at)

    case Enum.find_index(scene_nodes, &(&1.id == current_node_id)) do
      nil -> length(scene_nodes) + 1
      index -> index + 1
    end
  end

  defp generate_scene_technical_id(flow_slug, int_ext, location_name, scene_count) do
    flow_part = NodeTypeHelpers.normalize_for_id(flow_slug || "")
    int_ext_part = NodeTypeHelpers.normalize_for_id(int_ext || "")
    location_part = NodeTypeHelpers.normalize_for_id(location_name || "")
    flow_part = if flow_part == "", do: "scene", else: flow_part
    int_ext_part = if int_ext_part == "", do: "int", else: int_ext_part
    location_part = if location_part == "", do: "location", else: location_part
    "#{flow_part}_#{int_ext_part}_#{location_part}_#{scene_count}"
  end
end

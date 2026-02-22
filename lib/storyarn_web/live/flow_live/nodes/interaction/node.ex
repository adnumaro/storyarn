defmodule StoryarnWeb.FlowLive.Nodes.Interaction.Node do
  @moduledoc """
  Interaction node type definition.

  References a map in the project. Event zones on that map become dynamic
  output pins — the Story Player pauses at this node, renders the map, and
  advances through the pin corresponding to the zone the player clicks.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Maps
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  @doc "Returns the node type identifier."
  def type, do: "interaction"

  @doc "Returns the Lucide icon name for this node type."
  def icon_name, do: "gamepad-2"

  @doc "Returns the human-readable label for this node type."
  def label, do: dgettext("flows", "Interaction")

  @doc "Returns default data for a new interaction node."
  def default_data, do: %{"map_id" => nil}

  @doc "Extracts form-relevant fields from node data."
  def extract_form_data(data) do
    %{"map_id" => data["map_id"]}
  end

  @doc "Loads map info and event zones when an interaction node is selected."
  def on_select(node, socket) do
    map_id = node.data["map_id"]
    project_id = socket.assigns.project.id

    {map_info, event_zones} = load_map_data(project_id, map_id)
    project_maps = Maps.search_maps(project_id, "")

    socket
    |> assign(:interaction_map, map_info)
    |> assign(:interaction_event_zones, event_zones)
    |> assign(:project_maps, project_maps)
  end

  @doc "Double-click opens the toolbar for map selection."
  def on_double_click(_node), do: :toolbar

  @doc "Keep map_id on duplicate (map is a shared resource)."
  def duplicate_data_cleanup(data), do: data

  @doc "Handles selecting a map from the toolbar picker."
  def handle_select_map(%{"map-id" => map_id_str}, socket) do
    case socket.assigns.selected_node do
      nil -> {:noreply, socket}
      node -> do_update_map(socket, node, normalize_map_id(map_id_str))
    end
  end

  # -- Private --

  defp do_update_map(socket, node, nil) do
    # Clearing is always valid
    persist_and_return(socket, node, nil)
  end

  defp do_update_map(socket, node, map_id) do
    project_id = socket.assigns.project.id

    case Maps.get_map_brief(project_id, map_id) do
      nil ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           dgettext("flows", "Map not found in this project.")
         )}

      _map ->
        persist_and_return(socket, node, map_id)
    end
  end

  defp persist_and_return(socket, node, map_id) do
    NodeHelpers.persist_node_update(socket, node.id, fn data ->
      Map.put(data, "map_id", map_id)
    end)
  end

  defp normalize_map_id(str) when str in ["", nil], do: nil
  defp normalize_map_id(str), do: str

  defp load_map_data(_project_id, nil), do: {nil, []}

  defp load_map_data(project_id, map_id) do
    map = Maps.get_map_brief(project_id, map_id)
    zones = if map, do: Maps.list_event_zones(map_id), else: []
    {map, zones}
  end
end

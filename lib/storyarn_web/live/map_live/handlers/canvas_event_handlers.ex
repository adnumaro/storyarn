defmodule StoryarnWeb.MapLive.Handlers.CanvasEventHandlers do
  @moduledoc """
  Canvas UI event handlers for the map LiveView.

  Handles tool selection, export, edit mode toggle, search/filter, and element
  selection/deselection. Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps

  import StoryarnWeb.MapLive.Helpers.MapHelpers
  import StoryarnWeb.MapLive.Helpers.Serializer

  @spec handle_save_name(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_save_name(%{"name" => name}, socket) do
    case Maps.update_map(socket.assigns.map, %{name: name}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:map, updated)
         |> reload_maps_tree()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not save map name."))}
    end
  end

  @valid_tools ~w(select pan pin zone annotation connector ruler)a

  @spec handle_set_tool(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_set_tool(tool, socket) do
    case Enum.find(@valid_tools, fn t -> Atom.to_string(t) == tool end) do
      nil ->
        {:noreply, socket}

      tool_atom ->
        {:noreply,
         socket
         |> assign(:active_tool, tool_atom)
         |> push_event("tool_changed", %{tool: tool})}
    end
  end

  @spec handle_export_map(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_export_map(format, socket) do
    {:noreply, push_event(socket, "export_map", %{format: format})}
  end

  @spec handle_toggle_edit_mode(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_edit_mode(socket) do
    new_mode = !socket.assigns.edit_mode

    {:noreply,
     socket
     |> assign(:edit_mode, new_mode)
     |> assign(:active_tool, if(new_mode, do: :select, else: :pan))
     |> push_event("edit_mode_changed", %{edit_mode: new_mode})
     |> push_event("tool_changed", %{tool: if(new_mode, do: "select", else: "pan")})}
  end

  @spec handle_search_elements(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_search_elements(%{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> push_event("clear_highlights", %{})}
    else
      results = search_map_elements(socket, query, socket.assigns.search_filter)

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, results)
       |> push_event("highlight_elements", %{
         elements: Enum.map(results, &%{type: &1.type, id: &1.id})
       })}
    end
  end

  @spec handle_set_search_filter(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_set_search_filter(%{"filter" => filter}, socket) do
    socket = assign(socket, :search_filter, filter)

    if socket.assigns.search_query != "" do
      results = search_map_elements(socket, socket.assigns.search_query, filter)

      {:noreply,
       socket
       |> assign(:search_results, results)
       |> push_event("highlight_elements", %{
         elements: Enum.map(results, &%{type: &1.type, id: &1.id})
       })}
    else
      {:noreply, socket}
    end
  end

  @spec handle_clear_search(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_clear_search(socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_filter, "all")
     |> assign(:search_results, [])
     |> push_event("clear_highlights", %{})}
  end

  @spec handle_focus_search_result(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_focus_search_result(%{"type" => type, "id" => id}, socket) do
    id = parse_id(id)
    map_id = socket.assigns.map.id

    case load_element(type, id, map_id) do
      nil ->
        {:noreply, socket}

      element ->
        {:noreply,
         socket
         |> assign(:selected_type, type)
         |> assign(:selected_element, element)
         |> push_event("element_selected", %{type: type, id: id})
         |> push_event("focus_element", %{type: type, id: id})}
    end
  end

  @spec handle_select_element(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_select_element(%{"type" => type, "id" => id}, socket) do
    id = parse_id(id)
    map_id = socket.assigns.map.id

    case load_element(type, id, map_id) do
      nil ->
        {:noreply, socket}

      element ->
        {:noreply,
         socket
         |> assign(:selected_type, type)
         |> assign(:selected_element, element)
         |> push_event("element_selected", %{type: type, id: id})}
    end
  end

  @spec handle_deselect(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_deselect(socket) do
    {:noreply,
     socket
     |> assign(:selected_type, nil)
     |> assign(:selected_element, nil)
     |> push_event("element_deselected", %{})}
  end
end

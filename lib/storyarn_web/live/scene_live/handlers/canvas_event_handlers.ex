defmodule StoryarnWeb.SceneLive.Handlers.CanvasEventHandlers do
  @moduledoc """
  Canvas UI event handlers for the scene LiveView.

  Handles tool selection, export, edit mode toggle, search/filter, and element
  selection/deselection. Returns `{:noreply, socket}`.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.Helpers.AutoSnapshot, only: [schedule: 2]
  import StoryarnWeb.SceneLive.Helpers.SceneHelpers
  import StoryarnWeb.SceneLive.Helpers.SceneSerializer

  alias Phoenix.LiveView.Socket
  alias Storyarn.Scenes

  @spec handle_save_name(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_save_name(%{"name" => name}, socket) do
    case Scenes.update_scene(socket.assigns.scene, %{name: name}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:scene, updated)
         |> schedule(:scene)
         |> reload_scenes_tree()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not save scene name."))}
    end
  end

  @valid_tools ~w(select pan pin rectangle triangle circle freeform annotation connector ruler)a

  @spec handle_set_tool(String.t(), Socket.t()) ::
          {:noreply, Socket.t()}
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

  @spec handle_export_scene(String.t(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_export_scene(format, socket) do
    {:noreply, push_event(socket, "export_scene", %{format: format})}
  end

  @spec handle_toggle_edit_mode(Socket.t(), map()) ::
          {:noreply, Socket.t()}
  def handle_toggle_edit_mode(socket, params) do
    new_mode =
      case params do
        %{"mode" => "edit"} -> true
        %{"mode" => "view"} -> false
        _ -> !socket.assigns.edit_mode
      end

    if new_mode == socket.assigns.edit_mode do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:edit_mode, new_mode)
       |> assign(:active_tool, if(new_mode, do: :select, else: :pan))
       |> push_event("edit_mode_changed", %{edit_mode: new_mode})
       |> push_event("tool_changed", %{tool: if(new_mode, do: "select", else: "pan")})}
    end
  end

  @spec handle_search_elements(map(), Socket.t()) ::
          {:noreply, Socket.t()}
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

  @spec handle_set_search_filter(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_set_search_filter(%{"filter" => filter}, socket) do
    socket = assign(socket, :search_filter, filter)

    if socket.assigns.search_query == "" do
      {:noreply, socket}
    else
      results = search_map_elements(socket, socket.assigns.search_query, filter)

      {:noreply,
       socket
       |> assign(:search_results, results)
       |> push_event("highlight_elements", %{
         elements: Enum.map(results, &%{type: &1.type, id: &1.id})
       })}
    end
  end

  @spec handle_clear_search(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_clear_search(socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_filter, "all")
     |> assign(:search_results, [])
     |> push_event("clear_highlights", %{})}
  end

  @spec handle_focus_search_result(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_focus_search_result(%{"type" => type, "id" => id}, socket) do
    id = parse_id(id)
    scene_id = socket.assigns.scene.id

    case load_element(type, id, scene_id) do
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

  @spec handle_select_element(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_select_element(%{"type" => type, "id" => id}, socket) do
    id = parse_id(id)
    scene_id = socket.assigns.scene.id

    case load_element(type, id, scene_id) do
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

  @spec handle_deselect(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_deselect(socket) do
    {:noreply,
     socket
     |> assign(:selected_type, nil)
     |> assign(:selected_element, nil)
     |> dismiss_right_panel(:element)
     |> push_event("element_deselected", %{})}
  end
end

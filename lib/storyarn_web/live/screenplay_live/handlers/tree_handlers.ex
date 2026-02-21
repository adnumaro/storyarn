defmodule StoryarnWeb.ScreenplayLive.Handlers.TreeHandlers do
  @moduledoc """
  Screenplay tree management handlers for the screenplay LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Screenplays

  import StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers

  def do_delete_screenplay(socket, screenplay_id) do
    case Screenplays.get_screenplay(socket.assigns.project.id, screenplay_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay not found."))}

      screenplay ->
        persist_screenplay_deletion(socket, screenplay)
    end
  end

  def persist_screenplay_deletion(socket, screenplay) do
    case Screenplays.delete_screenplay(screenplay) do
      {:ok, _} ->
        if to_string(screenplay.id) == to_string(socket.assigns.screenplay.id) do
          {:noreply,
           socket
           |> put_flash(:info, dgettext("screenplays", "Screenplay moved to trash."))
           |> push_navigate(to: screenplays_path(socket))}
        else
          {:noreply,
           socket
           |> put_flash(:info, dgettext("screenplays", "Screenplay moved to trash."))
           |> reload_screenplays_tree()}
        end

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "Could not delete screenplay."))}
    end
  end

  def do_move_to_parent(socket, item_id, new_parent_id, position) do
    case Screenplays.get_screenplay(socket.assigns.project.id, item_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay not found."))}

      screenplay ->
        new_parent_id = parse_int(new_parent_id)
        position = parse_int(position) || 0

        case Screenplays.move_screenplay_to_position(screenplay, new_parent_id, position) do
          {:ok, _} ->
            {:noreply, reload_screenplays_tree(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("screenplays", "Could not move screenplay."))}
        end
    end
  end

  def do_create_screenplay(socket, extra_attrs) do
    with_edit_permission(socket, fn ->
      attrs = Map.merge(%{name: dgettext("screenplays", "Untitled")}, extra_attrs)

      case Screenplays.create_screenplay(socket.assigns.project, attrs) do
        {:ok, new_screenplay} ->
          {:noreply, push_navigate(socket, to: screenplays_path(socket, new_screenplay.id))}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, dgettext("screenplays", "Could not create screenplay."))}
      end
    end)
  end

  def with_edit_permission(socket, fun) do
    case authorize(socket, :edit_content) do
      :ok ->
        fun.()

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("screenplays", "You don't have permission to perform this action.")
         )}
    end
  end

  def handle_save_name(%{"name" => name}, socket) do
    case Screenplays.update_screenplay(socket.assigns.screenplay, %{name: name}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:screenplay, updated)
         |> reload_screenplays_tree()}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("screenplays", "Could not save screenplay name."))}
    end
  end
end

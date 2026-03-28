defmodule StoryarnWeb.SheetLive.Handlers.TreeHandlers do
  @moduledoc """
  Handles sheet tree events: create, delete, move.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
  import StoryarnWeb.SheetLive.Helpers.PropsSerializer, only: [prepare_tree: 1]

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets

  def handle_create(_params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("sheets", "Untitled")}) do
        {:ok, new_sheet} ->
          helpers.broadcast_project.(socket, :tree_changed)

          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_create_child(%{"parent_id" => parent_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          helpers.broadcast_project.(socket, :tree_changed)

          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, :limit_reached, _} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    end)
  end

  def handle_set_pending_delete(%{"id" => id}, socket, _helpers) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_confirm_delete(_params, socket, helpers) do
    if id = socket.assigns[:pending_delete_id] do
      Authorize.with_authorization(socket, :edit_content, fn socket ->
        with %{} = sheet <- Sheets.get_sheet(socket.assigns.project.id, id),
             {:ok, _} <- Sheets.delete_sheet(sheet) do
          {:noreply,
           socket
           |> put_flash(:info, dgettext("sheets", "Sheet moved to trash."))
           |> assign(
             :sheets_tree,
             prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id))
           )
           |> helpers.broadcast_project.(:tree_changed)}
        else
          _ ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
        end
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_move(params, socket, helpers) do
    %{"item_id" => id, "new_parent_id" => new_parent_id, "position" => position} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = Sheets.get_sheet(socket.assigns.project.id, MapUtils.parse_int(id))

      if sheet do
        parsed_parent = if new_parent_id in [nil, ""], do: nil, else: MapUtils.parse_int(new_parent_id)
        parsed_pos = MapUtils.parse_int(position) || 0

        case Sheets.move_sheet_to_position(sheet, parsed_parent, parsed_pos) do
          {:ok, _} ->
            {:noreply,
             socket
             |> helpers.reload_blocks.()
             |> assign(:sheets_tree,
               prepare_tree(Sheets.list_sheets_tree(socket.assigns.project.id))
             )
             |> helpers.broadcast_project.(:tree_changed)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end
end

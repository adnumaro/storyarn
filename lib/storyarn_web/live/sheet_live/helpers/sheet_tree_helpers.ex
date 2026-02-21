defmodule StoryarnWeb.SheetLive.Helpers.SheetTreeHelpers do
  @moduledoc """
  Sheet tree operation helpers for the sheet editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  use Gettext, backend: StoryarnWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: StoryarnWeb.Endpoint, router: StoryarnWeb.Router

  alias Storyarn.Sheets

  @doc """
  Deletes a sheet.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_sheet(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_sheet(socket, sheet_id) do
    sheet = Sheets.get_sheet!(socket.assigns.project.id, sheet_id)

    case Sheets.delete_sheet(sheet) do
      {:ok, _} ->
        handle_sheet_deleted(socket, sheet)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
    end
  end

  @doc """
  Moves a sheet to a new position in the tree.
  Returns {:noreply, socket} tuple.
  """
  @spec move_sheet(Phoenix.LiveView.Socket.t(), any(), any(), integer()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def move_sheet(socket, sheet_id, parent_id, position) do
    sheet = Sheets.get_sheet!(socket.assigns.project.id, sheet_id)
    parent_id = normalize_parent_id(parent_id)
    position = normalize_position(position)

    case Sheets.move_sheet_to_position(sheet, parent_id, position) do
      {:ok, _sheet} ->
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
        {:noreply, assign(socket, :sheets_tree, sheets_tree)}

      {:error, :would_create_cycle} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("sheets", "Cannot move a sheet into its own children.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
    end
  end

  @doc """
  Creates a child sheet under the given parent.
  Returns {:noreply, socket} tuple.
  """
  @spec create_child_sheet(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def create_child_sheet(socket, parent_id) do
    attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

    case Sheets.create_sheet(socket.assigns.project, attrs) do
      {:ok, new_sheet} ->
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:sheets_tree, sheets_tree)
         |> push_navigate(
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
    end
  end

  @doc """
  Saves the sheet name.
  Returns {:noreply, socket} tuple.
  """
  @spec save_name(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def save_name(socket, name) do
    old_name = socket.assigns.sheet.name

    case Sheets.update_sheet(socket.assigns.sheet, %{name: name}) do
      {:ok, sheet} ->
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        # Create version if name actually changed
        if name != old_name do
          sheet_with_blocks = Storyarn.Repo.preload(sheet, :blocks)
          user_id = socket.assigns.current_scope.user.id
          Sheets.maybe_create_version(sheet_with_blocks, user_id)
        end

        {:noreply,
         socket
         |> assign(:sheet, sheet)
         |> assign(:sheets_tree, sheets_tree)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp handle_sheet_deleted(socket, deleted_sheet) do
    socket = put_flash(socket, :info, dgettext("sheets", "Sheet deleted successfully."))

    if deleted_sheet.id == socket.assigns.sheet.id do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets"
       )}
    else
      sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
      {:noreply, assign(socket, :sheets_tree, sheets_tree)}
    end
  end

  defp normalize_parent_id(""), do: nil
  defp normalize_parent_id("null"), do: nil
  defp normalize_parent_id(nil), do: nil

  defp normalize_parent_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp normalize_parent_id(id) when is_integer(id), do: id

  defp normalize_position(val) when is_integer(val), do: val

  defp normalize_position(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp normalize_position(_), do: 0
end

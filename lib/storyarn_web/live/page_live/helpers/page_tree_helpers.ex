defmodule StoryarnWeb.PageLive.Helpers.PageTreeHelpers do
  @moduledoc """
  Page tree operation helpers for the page editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  use Gettext, backend: StoryarnWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: StoryarnWeb.Endpoint, router: StoryarnWeb.Router

  alias Storyarn.Pages

  @doc """
  Deletes a page.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_page(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_page(socket, page_id) do
    page = Pages.get_page!(socket.assigns.project.id, page_id)

    case Pages.delete_page(page) do
      {:ok, _} ->
        handle_page_deleted(socket, page)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete page."))}
    end
  end

  @doc """
  Moves a page to a new position in the tree.
  Returns {:noreply, socket} tuple.
  """
  @spec move_page(Phoenix.LiveView.Socket.t(), any(), any(), integer()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def move_page(socket, page_id, parent_id, position) do
    page = Pages.get_page!(socket.assigns.project.id, page_id)
    parent_id = normalize_parent_id(parent_id)

    case Pages.move_page_to_position(page, parent_id, position) do
      {:ok, _page} ->
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
        {:noreply, assign(socket, :pages_tree, pages_tree)}

      {:error, :would_create_cycle} ->
        {:noreply,
         put_flash(socket, :error, gettext("Cannot move a page into its own children."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not move page."))}
    end
  end

  @doc """
  Creates a child page under the given parent.
  Returns {:noreply, socket} tuple.
  """
  @spec create_child_page(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def create_child_page(socket, parent_id) do
    attrs = %{name: gettext("New Page"), parent_id: parent_id}

    case Pages.create_page(socket.assigns.project, attrs) do
      {:ok, new_page} ->
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:pages_tree, pages_tree)
         |> push_navigate(
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
    end
  end

  @doc """
  Saves the page name.
  Returns {:noreply, socket} tuple.
  """
  @spec save_name(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def save_name(socket, name) do
    case Pages.update_page(socket.assigns.page, %{name: name}) do
      {:ok, page} ->
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:page, page)
         |> assign(:pages_tree, pages_tree)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp handle_page_deleted(socket, deleted_page) do
    socket = put_flash(socket, :info, gettext("Page deleted successfully."))

    if deleted_page.id == socket.assigns.page.id do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages"
       )}
    else
      pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
      {:noreply, assign(socket, :pages_tree, pages_tree)}
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
end

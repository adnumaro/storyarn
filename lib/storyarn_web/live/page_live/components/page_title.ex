defmodule StoryarnWeb.PageLive.Components.PageTitle do
  @moduledoc """
  LiveComponent for the page title and shortcut editing.
  Handles inline editing with auto-save.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Pages
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1">
      <h1
        :if={@can_edit}
        id="page-title"
        class="text-3xl font-bold outline-none rounded px-2 -mx-2 py-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
        contenteditable="true"
        phx-hook="EditableTitle"
        phx-update="ignore"
        data-placeholder={gettext("Untitled")}
        data-name={@page.name}
        data-target={@myself}
      >
        {@page.name}
      </h1>
      <h1 :if={!@can_edit} class="text-3xl font-bold px-2 -mx-2 py-1">
        {@page.name}
      </h1>
      <%!-- Shortcut --%>
      <div :if={@can_edit} class="flex items-center gap-1 px-2 -mx-2 mt-1">
        <span class="text-base-content/50">#</span>
        <span
          id="page-shortcut"
          class="text-sm text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
          contenteditable="true"
          phx-hook="EditableShortcut"
          phx-update="ignore"
          data-placeholder={gettext("add-shortcut")}
          data-shortcut={@page.shortcut || ""}
          data-target={@myself}
        >
          {@page.shortcut}
        </span>
      </div>
      <div
        :if={!@can_edit && @page.shortcut}
        class="text-sm text-base-content/50 px-2 -mx-2 mt-1"
      >
        #{@page.shortcut}
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("save_name", %{"name" => name}, socket) do
    page = socket.assigns.page
    old_name = page.name

    case Pages.update_page(page, %{name: name}) do
      {:ok, updated_page} ->
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

        if name != old_name do
          page_with_blocks = Repo.preload(updated_page, :blocks)
          user_id = socket.assigns.current_user_id
          Pages.maybe_create_version(page_with_blocks, user_id)
        end

        send(self(), {:page_title, :name_saved, updated_page, pages_tree})
        {:noreply, assign(socket, :page, updated_page)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_shortcut", %{"shortcut" => shortcut}, socket) do
    page = socket.assigns.page
    old_shortcut = page.shortcut
    shortcut = if shortcut == "", do: nil, else: shortcut

    case Pages.update_page(page, %{shortcut: shortcut}) do
      {:ok, updated_page} ->
        updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset, :blocks])

        if shortcut != old_shortcut do
          user_id = socket.assigns.current_user_id
          Pages.maybe_create_version(updated_page, user_id)
        end

        send(self(), {:page_title, :shortcut_saved, updated_page})
        {:noreply, assign(socket, :page, updated_page)}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        send(self(), {:page_title, :error, error_msg})
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> gettext("Shortcut %{error}", error: msg)
      nil -> gettext("Could not save shortcut.")
    end
  end
end

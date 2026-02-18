defmodule StoryarnWeb.SheetLive.Components.SheetTitle do
  @moduledoc """
  LiveComponent for the sheet title and shortcut editing.
  Handles inline editing with auto-save.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Repo
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1">
      <h1
        :if={@can_edit}
        id="sheet-title"
        class="text-3xl font-bold outline-none rounded px-2 -mx-2 py-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
        contenteditable="true"
        phx-hook="EditableTitle"
        phx-update="ignore"
        data-placeholder={dgettext("sheets", "Untitled")}
        data-name={@sheet.name}
        data-target={@myself}
      >
        {@sheet.name}
      </h1>
      <h1 :if={!@can_edit} class="text-3xl font-bold px-2 -mx-2 py-1">
        {@sheet.name}
      </h1>
      <%!-- Shortcut --%>
      <div :if={@can_edit} class="flex items-center gap-1 px-2 -mx-2 mt-1">
        <span class="text-base-content/50">#</span>
        <span
          id="sheet-shortcut"
          class="text-sm text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
          contenteditable="true"
          phx-hook="EditableShortcut"
          phx-update="ignore"
          data-placeholder={dgettext("sheets", "add-shortcut")}
          data-shortcut={@sheet.shortcut || ""}
          data-target={@myself}
        >
          {@sheet.shortcut}
        </span>
      </div>
      <div
        :if={!@can_edit && @sheet.shortcut}
        class="text-sm text-base-content/50 px-2 -mx-2 mt-1"
      >
        #{@sheet.shortcut}
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
    sheet = socket.assigns.sheet
    old_name = sheet.name

    case Sheets.update_sheet(sheet, %{name: name}) do
      {:ok, updated_sheet} ->
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        if name != old_name do
          sheet_with_blocks = Repo.preload(updated_sheet, :blocks)
          user_id = socket.assigns.current_user_id
          Sheets.maybe_create_version(sheet_with_blocks, user_id)
        end

        send(self(), {:sheet_title, :name_saved, updated_sheet, sheets_tree})
        {:noreply, assign(socket, :sheet, updated_sheet)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_shortcut", %{"shortcut" => shortcut}, socket) do
    sheet = socket.assigns.sheet
    old_shortcut = sheet.shortcut
    shortcut = if shortcut == "", do: nil, else: shortcut

    case Sheets.update_sheet(sheet, %{shortcut: shortcut}) do
      {:ok, updated_sheet} ->
        updated_sheet =
          Repo.preload(updated_sheet, [:avatar_asset, :banner_asset, :blocks], force: true)

        if shortcut != old_shortcut do
          user_id = socket.assigns.current_user_id
          Sheets.maybe_create_version(updated_sheet, user_id)
        end

        send(self(), {:sheet_title, :shortcut_saved, updated_sheet})
        {:noreply, assign(socket, :sheet, updated_sheet)}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        send(self(), {:sheet_title, :error, error_msg})
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> dgettext("sheets", "Shortcut %{error}", error: msg)
      nil -> dgettext("sheets", "Could not save shortcut.")
    end
  end
end

defmodule StoryarnWeb.SheetLive.Helpers.VersioningHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias Storyarn.Repo

  @versions_per_page 20

  @doc """
  Handles restore_version event.
  """
  def restore_version(socket, version_number) do
    version_number = String.to_integer(version_number)

    case Sheets.get_version(socket.assigns.sheet.id, version_number) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Version not found."))}

      version ->
        restore_from_version(socket, version)
    end
  end

  @doc """
  Handles delete_version event.
  """
  def delete_version(socket, version_number) do
    version_number = String.to_integer(version_number)

    case Sheets.get_version(socket.assigns.sheet.id, version_number) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Version not found."))}

      version ->
        case Sheets.delete_version(version) do
          {:ok, _} ->
            versions = Sheets.list_versions(socket.assigns.sheet.id, limit: @versions_per_page)
            # Reload sheet in case current_version was cleared
            sheet = Sheets.get_sheet!(socket.assigns.project.id, socket.assigns.sheet.id)
            sheet = Repo.preload(sheet, [:avatar_asset, :banner_asset, :blocks, :current_version])

            {:noreply,
             socket
             |> assign(:sheet, sheet)
             |> assign(:versions, versions)
             |> put_flash(:info, gettext("Version deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete version."))}
        end
    end
  end

  @doc """
  Handles create_version event.
  """
  def create_version(socket, title, description) do
    sheet = Repo.preload(socket.assigns.sheet, :blocks)
    user_id = socket.assigns.current_scope.user.id

    title = if title == "", do: nil, else: title
    description = if description == "", do: nil, else: description

    case Sheets.create_version(sheet, user_id, title: title, description: description) do
      {:ok, version} ->
        versions = Sheets.list_versions(sheet.id, limit: @versions_per_page)
        # Set as current version
        {:ok, updated_sheet} = Sheets.set_current_version(sheet, version)

        updated_sheet =
          Repo.preload(updated_sheet, [:avatar_asset, :banner_asset, :blocks, :current_version])

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:versions, versions)
         |> assign(:show_create_version_modal, false)
         |> put_flash(:info, gettext("Version created."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create version."))}
    end
  end

  @doc """
  Loads more versions (pagination).
  """
  def load_more_versions(socket) do
    next_page = socket.assigns.versions_page + 1
    {:noreply, load_versions(socket, next_page)}
  end

  @doc """
  Loads versions with pagination support.
  """
  def load_versions(socket, sheet) do
    offset = (sheet - 1) * @versions_per_page

    # Fetch one extra to check if more exist
    versions =
      Sheets.list_versions(
        socket.assigns.sheet.id,
        limit: @versions_per_page + 1,
        offset: offset
      )

    has_more = length(versions) > @versions_per_page
    versions = Enum.take(versions, @versions_per_page)

    # If loading more sheets, append to existing versions
    versions =
      if sheet > 1 and not is_nil(socket.assigns.versions) do
        socket.assigns.versions ++ versions
      else
        versions
      end

    socket
    |> assign(:versions, versions)
    |> assign(:versions_page, sheet)
    |> assign(:has_more_versions, has_more)
  end

  # Private functions

  defp restore_from_version(socket, version) do
    sheet = socket.assigns.sheet

    case Sheets.restore_version(sheet, version) do
      {:ok, updated_sheet} ->
        handle_successful_restore(socket, updated_sheet, version)

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore version."))}
    end
  end

  defp handle_successful_restore(socket, updated_sheet, version) do
    sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
    versions = Sheets.list_versions(updated_sheet.id, limit: @versions_per_page)
    blocks = load_blocks_with_references(updated_sheet.id, socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:sheet, updated_sheet)
     |> assign(:blocks, blocks)
     |> assign(:sheets_tree, sheets_tree)
     |> assign(:versions, versions)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()
     |> push_event("restore_sheet_content", %{
       name: updated_sheet.name,
       shortcut: updated_sheet.shortcut || ""
     })
     |> put_flash(
       :info,
       gettext("Restored to version %{number}", number: version.version_number)
     )}
  end

  defp load_blocks_with_references(sheet_id, project_id) do
    Sheets.list_blocks(sheet_id)
    |> Enum.map(&add_reference_target(&1, project_id))
  end

  defp add_reference_target(%{type: "reference"} = block, project_id) do
    target_type = get_in(block.value, ["target_type"])
    target_id = get_in(block.value, ["target_id"])
    reference_target = Sheets.get_reference_target(target_type, target_id, project_id)
    Map.put(block, :reference_target, reference_target)
  end

  defp add_reference_target(block, _project_id) do
    Map.put(block, :reference_target, nil)
  end

  defp schedule_save_status_reset(socket) do
    Process.send_after(self(), :reset_save_status, 4000)
    socket
  end
end

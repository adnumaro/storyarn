defmodule StoryarnWeb.PageLive.Helpers.VersioningHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Pages
  alias Storyarn.Repo

  @versions_per_page 20

  @doc """
  Handles restore_version event.
  """
  def restore_version(socket, version_number) do
    version_number = String.to_integer(version_number)

    case Pages.get_version(socket.assigns.page.id, version_number) do
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

    case Pages.get_version(socket.assigns.page.id, version_number) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Version not found."))}

      version ->
        case Pages.delete_version(version) do
          {:ok, _} ->
            versions = Pages.list_versions(socket.assigns.page.id, limit: @versions_per_page)
            # Reload page in case current_version was cleared
            page = Pages.get_page!(socket.assigns.project.id, socket.assigns.page.id)
            page = Repo.preload(page, [:avatar_asset, :banner_asset, :blocks, :current_version])

            {:noreply,
             socket
             |> assign(:page, page)
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
    page = Repo.preload(socket.assigns.page, :blocks)
    user_id = socket.assigns.current_scope.user.id

    title = if title == "", do: nil, else: title
    description = if description == "", do: nil, else: description

    case Pages.create_version(page, user_id, title: title, description: description) do
      {:ok, version} ->
        versions = Pages.list_versions(page.id, limit: @versions_per_page)
        # Set as current version
        {:ok, updated_page} = Pages.set_current_version(page, version)

        updated_page =
          Repo.preload(updated_page, [:avatar_asset, :banner_asset, :blocks, :current_version])

        {:noreply,
         socket
         |> assign(:page, updated_page)
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
  def load_versions(socket, page) do
    offset = (page - 1) * @versions_per_page

    # Fetch one extra to check if more exist
    versions =
      Pages.list_versions(
        socket.assigns.page.id,
        limit: @versions_per_page + 1,
        offset: offset
      )

    has_more = length(versions) > @versions_per_page
    versions = Enum.take(versions, @versions_per_page)

    # If loading more pages, append to existing versions
    versions =
      if page > 1 and not is_nil(socket.assigns.versions) do
        socket.assigns.versions ++ versions
      else
        versions
      end

    socket
    |> assign(:versions, versions)
    |> assign(:versions_page, page)
    |> assign(:has_more_versions, has_more)
  end

  # Private functions

  defp restore_from_version(socket, version) do
    page = socket.assigns.page

    case Pages.restore_version(page, version) do
      {:ok, updated_page} ->
        handle_successful_restore(socket, updated_page, version)

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not restore version."))}
    end
  end

  defp handle_successful_restore(socket, updated_page, version) do
    pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
    versions = Pages.list_versions(updated_page.id, limit: @versions_per_page)
    blocks = load_blocks_with_references(updated_page.id, socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:page, updated_page)
     |> assign(:blocks, blocks)
     |> assign(:pages_tree, pages_tree)
     |> assign(:versions, versions)
     |> assign(:save_status, :saved)
     |> schedule_save_status_reset()
     |> push_event("restore_page_content", %{
       name: updated_page.name,
       shortcut: updated_page.shortcut || ""
     })
     |> put_flash(
       :info,
       gettext("Restored to version %{number}", number: version.version_number)
     )}
  end

  defp load_blocks_with_references(page_id, project_id) do
    Pages.list_blocks(page_id)
    |> Enum.map(&add_reference_target(&1, project_id))
  end

  defp add_reference_target(%{type: "reference"} = block, project_id) do
    target_type = get_in(block.value, ["target_type"])
    target_id = get_in(block.value, ["target_id"])
    reference_target = Pages.get_reference_target(target_type, target_id, project_id)
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

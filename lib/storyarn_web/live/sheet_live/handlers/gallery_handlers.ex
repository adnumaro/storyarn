defmodule StoryarnWeb.SheetLive.Handlers.GalleryHandlers do
  @moduledoc """
  Handles gallery block events for the ContentTab LiveComponent.

  Each public function returns `{:noreply, socket}`.

  The `helpers` map must contain:
    - `:reload_blocks`        - fn(socket) -> socket
    - `:maybe_create_version` - fn(socket) -> any
    - `:notify_parent`        - fn(socket, status) -> any
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Assets
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ===========================================================================
  # Upload
  # ===========================================================================

  @doc "Handles a gallery image upload (base64 from JS hook)."
  def handle_upload_gallery_image(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block_id"])
    filename = params["filename"]
    content_type = params["content_type"]
    data = params["data"]

    project = socket.assigns.project
    user = socket.assigns.current_scope.user

    block = Sheets.get_block_in_project(block_id, project.id)

    if block && block.type == "gallery" do
      case decode_base64(data) do
        {:ok, binary_data} ->
          upload_gallery_file(
            socket,
            block,
            filename,
            content_type,
            binary_data,
            project,
            user,
            helpers
          )

        :error ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    else
      {:noreply, socket}
    end
  end

  @doc "Handles upload validation errors from JS."
  def handle_upload_validation_error(params, socket) do
    {:noreply, put_flash(socket, :error, params["message"] || dgettext("sheets", "Upload error"))}
  end

  # ===========================================================================
  # Update
  # ===========================================================================

  @doc "Updates a gallery image's label or description."
  def handle_update_gallery_image(params, socket, helpers) do
    gallery_image_id = ContentTabHelpers.to_integer(params["gallery-image-id"])
    field = params["field"]
    value = params["value"]

    case Sheets.get_gallery_image(gallery_image_id) do
      nil ->
        {:noreply, socket}

      gi ->
        attrs = %{field => value}

        case Sheets.update_gallery_image(gi, attrs) do
          {:ok, _} ->
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # ===========================================================================
  # Remove
  # ===========================================================================

  @doc "Removes a gallery image."
  def handle_remove_gallery_image(params, socket, helpers) do
    gallery_image_id = ContentTabHelpers.to_integer(params["gallery_image_id"])

    case Sheets.remove_gallery_image(gallery_image_id) do
      {:ok, _} ->
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove image."))}
    end
  end

  # ===========================================================================
  # Reorder
  # ===========================================================================

  @doc "Reorders gallery images within a block."
  def handle_reorder_gallery_images(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block_id"])
    ordered_ids = Enum.map(params["ids"] || [], &ContentTabHelpers.to_integer/1)

    case Sheets.reorder_gallery_images(block_id, ordered_ids) do
      {:ok, _} ->
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp decode_base64(data) do
    case String.split(data, ",", parts: 2) do
      [_header, base64_data] -> Base.decode64(base64_data)
      _ -> :error
    end
  end

  defp upload_gallery_file(
         socket,
         block,
         filename,
         content_type,
         binary_data,
         project,
         user,
         helpers
       ) do
    if Assets.allowed_content_type?(content_type) do
      with {:ok, asset} <-
             Assets.upload_binary_and_create_asset(
               binary_data,
               %{filename: filename, content_type: content_type},
               project,
               user
             ),
           {:ok, _gi} <- Sheets.add_gallery_image(block, asset.id) do
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}
      else
        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload image."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}
    end
  end
end

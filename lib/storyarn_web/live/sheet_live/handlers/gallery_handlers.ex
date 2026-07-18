defmodule StoryarnWeb.SheetLive.Handlers.GalleryHandlers do
  @moduledoc """
  Handles gallery block image events for the V2 sheet editor.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Assets
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  def handle_attach(%{"block_id" => block_id, "asset_id" => asset_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      socket
      |> gallery_block_for_current_sheet(helpers.parse_id.(block_id))
      |> attach_asset_to_gallery(socket, asset_id, helpers)
    end)
  end

  def handle_update(params, socket, helpers) do
    %{"gallery_image_id" => id, "field" => field, "value" => value} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with field when field in [:label, :description] <- gallery_field(field),
           %{} = image <-
             Sheets.get_gallery_image_for_sheet(
               socket.assigns.sheet.id,
               helpers.parse_id.(id)
             ),
           {:ok, _updated} <- Sheets.update_gallery_image(image, %{field => value}) do
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        _error ->
          {:noreply, socket}
      end
    end)
  end

  defp gallery_field("label"), do: :label
  defp gallery_field("description"), do: :description
  defp gallery_field(_field), do: nil

  def handle_remove(%{"gallery_image_id" => id} = _params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.remove_gallery_image(socket.assigns.sheet.id, helpers.parse_id.(id)) do
        {:ok, _} ->
          {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

        _ ->
          {:noreply, socket}
      end
    end)
  end

  def handle_reorder(%{"block_id" => block_id, "ids" => ids}, socket, helpers) when is_list(ids) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      int_ids = Enum.map(ids, &helpers.parse_id.(&1))

      with {:ok, block} <-
             gallery_block_for_current_sheet(socket, helpers.parse_id.(block_id)),
           {:ok, _result} <- Sheets.reorder_gallery_images(block.id, int_ids) do
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        _error -> {:noreply, socket}
      end
    end)
  end

  def handle_reorder(_params, socket, _helpers), do: {:noreply, socket}

  defp gallery_block_for_current_sheet(socket, block_id) do
    case Sheets.get_block(block_id) do
      %{sheet_id: sheet_id, type: "gallery"} = block when sheet_id == socket.assigns.sheet.id -> {:ok, block}
      _ -> :error
    end
  end

  defp attach_asset_to_gallery({:ok, block}, socket, asset_id, helpers) do
    case Assets.get_asset(socket.assigns.project.id, asset_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Asset not found."))}

      _asset ->
        case Sheets.add_gallery_image(block, asset_id) do
          {:ok, _image} ->
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, {:invalid_asset_content_type, _, _}} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}

          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end

  defp attach_asset_to_gallery(:error, socket, _asset_id, _helpers) do
    {:noreply, socket}
  end
end

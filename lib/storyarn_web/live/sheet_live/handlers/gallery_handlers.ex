defmodule StoryarnWeb.SheetLive.Handlers.GalleryHandlers do
  @moduledoc """
  Handles gallery block image events for the V2 sheet editor.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Assets
  alias Storyarn.Sheets

  def handle_attach(%{"block_id" => block_id, "asset_id" => asset_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id && block.type == "gallery" do
        case Assets.get_asset(socket.assigns.project.id, asset_id) do
          nil ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Asset not found."))}

          _asset ->
            Sheets.add_gallery_image(block, asset_id)
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_update(params, socket, helpers) do
    %{"gallery_image_id" => id, "field" => field, "value" => value} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Sheets.get_gallery_image_for_sheet(socket.assigns.sheet.id, helpers.parse_id.(id)) do
        nil ->
          {:noreply, socket}

        gi ->
          Sheets.update_gallery_image(gi, %{String.to_existing_atom(field) => value})
          {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end
    end)
  end

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

  def handle_reorder(%{"block_id" => block_id, "ids" => ids}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      int_ids = Enum.map(ids, &helpers.parse_id.(&1))
      Sheets.reorder_gallery_images(helpers.parse_id.(block_id), int_ids)
      {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
    end)
  end
end

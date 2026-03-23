defmodule StoryarnWeb.SheetLive.Handlers.SelectOptionHandlers do
  @moduledoc """
  Handles select/multi_select option management events for the V2 sheet editor.
  """

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Sheets

  def handle_add(%{"block-id" => block_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        options = get_in(block.config, ["options"]) || []
        new_option = %{"key" => "option_#{length(options) + 1}", "value" => ""}
        new_config = Map.put(block.config || %{}, "options", options ++ [new_option])

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} -> {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
          {:error, _} -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_remove(%{"block-id" => block_id, "index" => index}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        options = get_in(block.config, ["options"]) || []
        new_config = Map.put(block.config || %{}, "options", List.delete_at(options, index))

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} -> {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
          {:error, _} -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_update(params, socket, helpers) do
    %{"block-id" => block_id, "index" => index, "field" => field, "value" => value} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        options = get_in(block.config, ["options"]) || []

        new_options =
          List.update_at(options, index, fn opt ->
            Map.put(opt || %{}, field, value)
          end)

        new_config = Map.put(block.config || %{}, "options", new_options)

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} -> {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
          {:error, _} -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end
end

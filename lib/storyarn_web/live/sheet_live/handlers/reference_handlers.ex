defmodule StoryarnWeb.SheetLive.Handlers.ReferenceHandlers do
  @moduledoc """
  Handles reference block events for the V2 sheet editor.
  """

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Sheets

  def handle_search(%{"block-id" => block_id} = params, socket, helpers) do
    query = params["query"] || ""
    block_id = helpers.parse_id.(block_id)
    block = Sheets.get_block(block_id)
    allowed_types = get_in(block.config, ["allowed_types"]) || ["sheet", "flow"]

    results = Sheets.search_referenceable(socket.assigns.project.id, query, allowed_types)

    {:noreply,
     push_event(socket, "reference_results", %{
       block_id: block_id,
       results: results
     })}
  end

  def handle_select(params, socket, helpers) do
    %{"block-id" => block_id, "type" => target_type, "id" => target_id} = params

    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block_id = helpers.parse_id.(block_id)
      block = Sheets.get_block(block_id)

      if block && block.sheet_id == socket.assigns.sheet.id do
        target_id_int = helpers.parse_id.(target_id)

        case Sheets.validate_reference_target(
               target_type,
               target_id_int,
               socket.assigns.project.id
             ) do
          {:ok, _target} ->
            Sheets.update_block_value(block, %{
              "target_type" => target_type,
              "target_id" => target_id_int
            })

            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Reference target not found."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_clear(%{"block-id" => block_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(block_id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_block_value(block, %{"target_type" => nil, "target_id" => nil})
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        {:noreply, socket}
      end
    end)
  end
end

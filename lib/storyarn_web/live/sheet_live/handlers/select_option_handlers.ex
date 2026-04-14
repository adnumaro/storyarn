defmodule StoryarnWeb.SheetLive.Handlers.SelectOptionHandlers do
  @moduledoc """
  Unified add/remove/update of select & multi_select options.

  Works against two scopes:

    * `"block"` → options live in `blocks.config["options"]`.
    * `"column"` → options live in `table_columns.config["options"]`.

  The wire payload always carries `scope` + `id` (+ `index`, `field`, `value` as
  needed). Each scope persists through its own Sheets facade and emits its
  existing undo tag, so no changes to `UndoRedoHandlers` are required.
  """

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Sheets

  # ── Public event handlers ──────────────────────────────────────────────────

  def handle_add(%{"scope" => scope, "id" => id}, socket, helpers) do
    with_scope(scope, id, socket, helpers, fn ctx ->
      options = ctx.options
      new_option = %{"key" => "option_#{length(options) + 1}", "value" => ""}
      persist(ctx, options ++ [new_option], socket, helpers)
    end)
  end

  def handle_remove(
        %{"scope" => scope, "id" => id, "index" => index},
        socket,
        helpers
      ) do
    with_scope(scope, id, socket, helpers, fn ctx ->
      persist(ctx, List.delete_at(ctx.options, index), socket, helpers)
    end)
  end

  def handle_update(
        %{
          "scope" => scope,
          "id" => id,
          "index" => index,
          "field" => field,
          "value" => value
        },
        socket,
        helpers
      )
      when field in ["key", "value"] do
    with_scope(scope, id, socket, helpers, fn ctx ->
      new_options =
        List.update_at(ctx.options, index, fn opt -> Map.put(opt || %{}, field, value) end)

      persist(ctx, new_options, socket, helpers)
    end)
  end

  def handle_update(_params, socket, _helpers), do: {:noreply, socket}

  # ── Scope dispatch ─────────────────────────────────────────────────────────

  defp with_scope("block", id, socket, helpers, fun) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        fun.(%{
          kind: :block,
          entity: block,
          options: get_in(block.config, ["options"]) || [],
          prev_config: block.config
        })
      else
        {:noreply, socket}
      end
    end)
  end

  defp with_scope("column", id, socket, helpers, fun) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      column_id = helpers.parse_id.(id)

      case find_block_id_for_column(socket, column_id) do
        {:ok, block_id} ->
          column = Sheets.get_table_column!(block_id, column_id)

          fun.(%{
            kind: :column,
            entity: column,
            options: get_in(column.config, ["options"]) || [],
            prev_config: column.config
          })

        :not_found ->
          {:noreply, socket}
      end
    end)
  end

  defp with_scope(_scope, _id, socket, _helpers, _fun), do: {:noreply, socket}

  # ── Persistence ────────────────────────────────────────────────────────────

  defp persist(%{kind: :block, entity: block, prev_config: prev}, new_options, socket, helpers) do
    new_config = Map.put(prev || %{}, "options", new_options)

    case Sheets.update_block_config(block, new_config) do
      {:ok, _} ->
        {:noreply,
         socket
         |> helpers.push_undo.({:update_block_config, block.id, prev, new_config})
         |> helpers.reload_blocks.()
         |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp persist(%{kind: :column, entity: column, prev_config: prev}, new_options, socket, helpers) do
    new_config = Map.put(prev || %{}, "options", new_options)

    case Sheets.update_table_column(column, %{config: new_config}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> helpers.push_undo.(
           {:update_table_column_config, column.block_id, column.id, prev, new_config}
         )
         |> helpers.reload_blocks.()
         |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp find_block_id_for_column(socket, column_id) do
    result =
      Enum.find_value(socket.assigns.table_data, fn {block_id, %{columns: columns}} ->
        if Enum.any?(columns, &(&1.id == column_id)), do: block_id
      end)

    if result, do: {:ok, result}, else: :not_found
  end
end

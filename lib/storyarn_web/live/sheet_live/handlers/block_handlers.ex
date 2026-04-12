defmodule StoryarnWeb.SheetLive.Handlers.BlockHandlers do
  @moduledoc """
  Handles block CRUD, toolbar, reorder, and inheritance events for the sheet editor.
  """

  import Phoenix.LiveView, only: [put_flash: 3]
  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Sheets

  # ===========================================================================
  # Block CRUD
  # ===========================================================================

  def handle_add(%{"type" => type} = params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{type: type}
      attrs = if params["scope"], do: Map.put(attrs, :scope, params["scope"]), else: attrs

      case Sheets.create_block(socket.assigns.sheet, attrs) do
        {:ok, block} ->
          snapshot = helpers.block_to_snapshot.(block)

          {:noreply,
           socket
           |> helpers.push_undo.({:create_block, snapshot})
           |> helpers.reload_blocks.()
           |> helpers.broadcast.(:block_created)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create block."))}
      end
    end)
  end

  def handle_update_value(%{"id" => id, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        prev = get_in(block.value, ["content"])

        case Sheets.update_block_value(block, %{"content" => value}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> helpers.push_block_value_coalesced.(block.id, prev, value)
             |> helpers.reload_blocks.()
             |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_toggle_multi_select(%{"id" => id, "key" => key}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        current = get_in(block.value, ["content"]) || []

        new_content =
          if key in current,
            do: List.delete(current, key),
            else: current ++ [key]

        case Sheets.update_block_value(block, %{"content" => new_content}) do
          {:ok, _} ->
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_update_config(%{"id" => id, "field" => field, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        new_config = Map.put(block.config || %{}, field, value)

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} ->
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_delete(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        snapshot = helpers.block_to_snapshot.(block)

        case Sheets.delete_block(block) do
          {:ok, _} ->
            {:noreply,
             socket
             |> helpers.push_undo.({:delete_block, snapshot})
             |> helpers.reload_blocks.()
             |> helpers.broadcast_with_payload.(:block_deleted, %{block_id: helpers.parse_id.(id)})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_duplicate(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.duplicate_block(block) do
          {:ok, new_block} ->
            snapshot = helpers.block_to_snapshot.(new_block)

            {:noreply,
             socket
             |> helpers.push_undo.({:create_block, snapshot})
             |> helpers.reload_blocks.()
             |> helpers.broadcast.(:block_created)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_undo(params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case helpers.handle_undo.(params, socket) do
        {:noreply, socket} ->
          {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end
    end)
  end

  def handle_redo(params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case helpers.handle_redo.(params, socket) do
        {:noreply, socket} ->
          {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end
    end)
  end

  # ===========================================================================
  # Block reorder
  # ===========================================================================

  def handle_reorder_layout(%{"layout" => layout}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet_id = socket.assigns.sheet.id

      case flatten_layout(layout, helpers.parse_id) do
        {:ok, sanitized} ->
          prev_layout =
            Sheets.list_blocks(sheet_id)
            |> Enum.sort_by(& &1.position)
            |> Enum.map(fn b ->
              %{id: b.id, column_group_id: b.column_group_id, column_index: b.column_index}
            end)

          case Sheets.reorder_blocks_with_columns(sheet_id, sanitized) do
            {:ok, _} ->
              {:noreply,
               socket
               |> helpers.push_undo.({:reorder_blocks_with_columns, prev_layout, sanitized})
               |> helpers.reload_blocks.()
               |> helpers.broadcast.(:block_reordered)}

            {:error, _} ->
              {:noreply,
               put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
          end

        :error ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid layout."))}
      end
    end)
  end

  # ===========================================================================
  # Block toolbar
  # ===========================================================================

  def handle_toggle_constant(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        prev = block.is_constant

        case Sheets.update_block(block, %{is_constant: !prev}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> helpers.push_undo.({:toggle_constant, block.id, prev, !prev})
             |> helpers.reload_blocks.()
             |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_update_variable_name(%{"id" => id, "variable_name" => name}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_variable_name(block, name)
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_change_scope(%{"id" => id, "scope" => scope}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_block(block, %{scope: scope})
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_toggle_required(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        Sheets.update_block(block, %{required: !block.required})
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      else
        {:noreply, socket}
      end
    end)
  end

  # ===========================================================================
  # Inheritance
  # ===========================================================================

  def handle_detach(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.detach_block(block) do
          {:ok, _} ->
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not detach block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_reattach(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      block = Sheets.get_block(helpers.parse_id.(id))

      if block && block.sheet_id == socket.assigns.sheet.id do
        case Sheets.reattach_block(block) do
          {:ok, _} ->
            {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reattach block."))}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp flatten_layout(layout, parse_id) when is_list(layout) do
    try do
      items =
        Enum.flat_map(layout, fn
          %{"kind" => "full_width", "block_id" => id} ->
            [%{id: parse_id.(id), column_group_id: nil, column_index: 0}]

          %{"kind" => "column_group", "group_id" => group_id, "block_ids" => ids}
          when is_list(ids) and length(ids) >= 2 and length(ids) <= 3 ->
            ids
            |> Enum.with_index()
            |> Enum.map(fn {id, idx} ->
              %{id: parse_id.(id), column_group_id: group_id, column_index: idx}
            end)

          _ ->
            throw(:invalid)
        end)

      {:ok, items}
    catch
      :invalid -> :error
    end
  end

  defp flatten_layout(_, _), do: :error
end

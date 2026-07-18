defmodule StoryarnWeb.SheetLive.Handlers.BlockHandlers do
  @moduledoc """
  Handles block CRUD, toolbar, reorder, and inheritance events for the sheet editor.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Analytics
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

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
          track_block_created(socket, block, params, "create")

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

  defp track_block_created(socket, block, params, creation_method) do
    Analytics.track(socket.assigns.current_scope, "sheet block created", %{
      block_type: block.type,
      creation_method: creation_method,
      project_id: socket.assigns.project.id,
      scope: params["scope"],
      sheet_id: socket.assigns.sheet.id
    })
  end

  def handle_update_value(%{"id" => id, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        update_owned_block_value(block, value, socket, helpers)
      end)
    end)
  end

  def handle_toggle_multi_select(%{"id" => id, "key" => key}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        toggle_owned_multi_select(block, key, socket, helpers)
      end)
    end)
  end

  def handle_update_config(%{"id" => id, "field" => field, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        update_owned_block_config(block, field, value, socket, helpers)
      end)
    end)
  end

  def handle_delete(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        delete_owned_block(block, socket, helpers)
      end)
    end)
  end

  def handle_duplicate(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        duplicate_owned_block(block, socket, helpers)
      end)
    end)
  end

  def handle_undo(params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      {:noreply, socket} = helpers.handle_undo.(params, socket)
      {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
    end)
  end

  def handle_redo(params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      {:noreply, socket} = helpers.handle_redo.(params, socket)
      {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
    end)
  end

  # ===========================================================================
  # Block reorder
  # ===========================================================================

  def handle_reorder_layout(%{"layout" => layout}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      reorder_layout(layout, socket, helpers)
    end)
  end

  # ===========================================================================
  # Block toolbar
  # ===========================================================================

  def handle_toggle_constant(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        toggle_owned_constant(block, socket, helpers)
      end)
    end)
  end

  def handle_update_variable_name(%{"id" => id, "variable_name" => name}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        Sheets.update_variable_name(block, name)
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end)
    end)
  end

  def handle_change_scope(%{"id" => id, "scope" => scope}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        Sheets.update_block(block, %{scope: scope})
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end)
    end)
  end

  def handle_toggle_required(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        Sheets.update_block(block, %{required: !block.required})
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}
      end)
    end)
  end

  # ===========================================================================
  # Inheritance
  # ===========================================================================

  def handle_detach(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        detach_owned_block(block, socket, helpers)
      end)
    end)
  end

  def handle_reattach(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with_owned_block(id, socket, helpers, fn block ->
        reattach_owned_block(block, socket, helpers)
      end)
    end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp with_owned_block(id, socket, helpers, fun) do
    case get_owned_block(id, socket, helpers) do
      nil -> {:noreply, socket}
      block -> fun.(block)
    end
  end

  defp get_owned_block(id, socket, helpers) do
    sheet_id = socket.assigns.sheet.id

    case Sheets.get_block(helpers.parse_id.(id)) do
      %{sheet_id: ^sheet_id} = block -> block
      _ -> nil
    end
  end

  defp update_owned_block_value(block, value, socket, helpers) do
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
  end

  defp toggle_owned_multi_select(block, key, socket, helpers) do
    current = get_in(block.value, ["content"]) || []
    new_content = toggle_list_member(current, key)

    case Sheets.update_block_value(block, %{"content" => new_content}) do
      {:ok, _} ->
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp toggle_list_member(list, item) do
    if item in list,
      do: List.delete(list, item),
      else: list ++ [item]
  end

  defp update_owned_block_config(block, field, value, socket, helpers) do
    new_config = Map.put(block.config || %{}, field, value)

    case Sheets.update_block_config(block, new_config) do
      {:ok, _} ->
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp delete_owned_block(block, socket, helpers) do
    snapshot = helpers.block_to_snapshot.(block)

    case Sheets.delete_block(block) do
      {:ok, _} ->
        {:noreply,
         socket
         |> helpers.push_undo.({:delete_block, snapshot})
         |> helpers.reload_blocks.()
         |> helpers.broadcast_with_payload.(:block_deleted, %{block_id: block.id})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete block."))}
    end
  end

  defp duplicate_owned_block(block, socket, helpers) do
    case Sheets.duplicate_block(block) do
      {:ok, new_block} ->
        snapshot = helpers.block_to_snapshot.(new_block)
        track_block_created(socket, new_block, %{}, "duplicate")

        {:noreply,
         socket
         |> helpers.push_undo.({:create_block, snapshot})
         |> helpers.reload_blocks.()
         |> helpers.broadcast.(:block_created)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
    end
  end

  defp reorder_layout(layout, socket, helpers) do
    case flatten_layout(layout, helpers.parse_id) do
      {:ok, sanitized} ->
        reorder_sanitized_layout(socket, sanitized, helpers)

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid layout."))}
    end
  end

  defp reorder_sanitized_layout(socket, sanitized, helpers) do
    sheet_id = socket.assigns.sheet.id
    prev_layout = current_layout(sheet_id)

    case Sheets.reorder_blocks_with_columns(sheet_id, sanitized) do
      {:ok, _} ->
        {:noreply,
         socket
         |> helpers.push_undo.({:reorder_blocks_with_columns, prev_layout, sanitized})
         |> helpers.reload_blocks.()
         |> helpers.broadcast.(:block_reordered)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
    end
  end

  defp current_layout(sheet_id) do
    sheet_id
    |> Sheets.list_blocks()
    |> Enum.filter(&(is_nil(&1.inherited_from_block_id) or &1.detached))
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn block ->
      %{id: block.id, column_group_id: block.column_group_id, column_index: block.column_index}
    end)
  end

  defp toggle_owned_constant(block, socket, helpers) do
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
  end

  defp detach_owned_block(block, socket, helpers) do
    case Sheets.detach_block(block) do
      {:ok, _} ->
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not detach block."))}
    end
  end

  defp reattach_owned_block(block, socket, helpers) do
    case Sheets.reattach_block(block) do
      {:ok, _} ->
        {:noreply, socket |> helpers.reload_blocks.() |> helpers.broadcast.(:block_updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reattach block."))}
    end
  end

  defp flatten_layout(layout, parse_id) when is_list(layout) do
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

  defp flatten_layout(_, _), do: :error
end

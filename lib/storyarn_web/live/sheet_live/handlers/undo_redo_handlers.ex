defmodule StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers do
  @moduledoc """
  Undo/redo action dispatch for the Sheet editor.
  Uses shared stack management from UndoRedoStack.

  Stacks live in `show.ex` socket assigns. ContentTab LiveComponent sends
  `{:content_tab, :push_undo, action}` messages to the parent for recording.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SheetLive.Helpers.ReferenceHelpers

  # ===========================================================================
  # Public dispatch
  # ===========================================================================

  def handle_undo(_params, socket) do
    case UndoRedoStack.pop_undo(socket) do
      :empty ->
        {:noreply, socket}

      {action, socket} ->
        case undo_action(action, socket) do
          {:ok, socket, redo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_redo(redo_item)
             |> reload_sheet()}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  def handle_redo(_params, socket) do
    case UndoRedoStack.pop_redo(socket) do
      :empty ->
        {:noreply, socket}

      {action, socket} ->
        case redo_action(action, socket) do
          {:ok, socket, undo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_undo_no_clear(undo_item)
             |> reload_sheet()}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  # ===========================================================================
  # Coalescing helpers (called from show.ex handlers)
  # ===========================================================================

  def push_name_coalesced(socket, prev, new) do
    UndoRedoStack.push_coalesced(
      socket,
      {:update_sheet_name, prev, new},
      fn
        {:update_sheet_name, _, _} -> true
        _ -> false
      end,
      fn {:update_sheet_name, original_prev, _} ->
        {:update_sheet_name, original_prev, new}
      end
    )
  end

  def push_shortcut_coalesced(socket, prev, new) do
    UndoRedoStack.push_coalesced(
      socket,
      {:update_sheet_shortcut, prev, new},
      fn
        {:update_sheet_shortcut, _, _} -> true
        _ -> false
      end,
      fn {:update_sheet_shortcut, original_prev, _} ->
        {:update_sheet_shortcut, original_prev, new}
      end
    )
  end

  def push_block_value_coalesced(socket, block_id, prev, new) do
    UndoRedoStack.push_coalesced(
      socket,
      {:update_block_value, block_id, prev, new},
      fn
        {:update_block_value, ^block_id, _, _} -> true
        _ -> false
      end,
      fn {:update_block_value, ^block_id, original_prev, _} ->
        {:update_block_value, block_id, original_prev, new}
      end
    )
  end

  def push_cell_coalesced(socket, block_id, row_id, col_slug, prev, new) do
    UndoRedoStack.push_coalesced(
      socket,
      {:update_table_cell, block_id, row_id, col_slug, prev, new},
      fn
        {:update_table_cell, ^block_id, ^row_id, ^col_slug, _, _} -> true
        _ -> false
      end,
      fn {:update_table_cell, ^block_id, ^row_id, ^col_slug, original_prev, _} ->
        {:update_table_cell, block_id, row_id, col_slug, original_prev, new}
      end
    )
  end

  # ===========================================================================
  # Block snapshot helpers
  # ===========================================================================

  def block_to_snapshot(block) do
    %{
      id: block.id,
      sheet_id: block.sheet_id,
      type: block.type,
      value: block.value,
      config: block.config,
      position: block.position,
      is_constant: block.is_constant,
      variable_name: block.variable_name,
      scope: block.scope,
      column_group_id: block.column_group_id,
      column_index: block.column_index
    }
  end

  # ===========================================================================
  # Undo: Sheet metadata
  # ===========================================================================

  defp undo_action({:update_sheet_name, prev, _new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{name: prev}) do
      {:ok, _} ->
        {:ok, push_event(socket, "restore_page_content", %{name: prev}),
         {:update_sheet_name, prev, socket.assigns.sheet.name}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp undo_action({:update_sheet_shortcut, prev, _new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{shortcut: prev}) do
      {:ok, _} ->
        {:ok, push_event(socket, "restore_page_content", %{shortcut: prev || ""}),
         {:update_sheet_shortcut, prev, socket.assigns.sheet.shortcut}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp undo_action({:update_sheet_color, prev, _new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{color: prev}) do
      {:ok, _} ->
        {:ok, socket, {:update_sheet_color, prev, socket.assigns.sheet.color}}

      {:error, _} ->
        {:error, socket}
    end
  end

  # ===========================================================================
  # Undo: Block CRUD
  # ===========================================================================

  defp undo_action({:create_block, snapshot}, socket) do
    case Sheets.get_block(snapshot.id) do
      nil ->
        {:error, socket}

      block ->
        case Sheets.delete_block(block) do
          {:ok, _} -> {:ok, socket, {:create_block, snapshot}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:delete_block, snapshot}, socket) do
    case Sheets.create_block_from_snapshot(socket.assigns.sheet, snapshot) do
      {:ok, block} ->
        {:ok, socket, {:delete_block, block_to_snapshot(block)}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp undo_action({:reorder_blocks, prev_order, new_order}, socket) do
    case Sheets.reorder_blocks(socket.assigns.sheet.id, prev_order) do
      {:ok, _} -> {:ok, socket, {:reorder_blocks, prev_order, new_order}}
      {:error, _} -> {:error, socket}
    end
  end

  # ===========================================================================
  # Undo: Block values & config
  # ===========================================================================

  defp undo_action({:update_block_value, block_id, prev, _new}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current = block.value

        case Sheets.update_block_value(block, %{"content" => prev}) do
          {:ok, _} -> {:ok, socket, {:update_block_value, block_id, prev, current}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:update_block_config, block_id, prev_config, _new_config}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current_config = block.config

        case Sheets.update_block_config(block, prev_config) do
          {:ok, _} ->
            {:ok, socket, {:update_block_config, block_id, prev_config, current_config}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:toggle_constant, block_id, prev, _new}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current = block.is_constant

        case Sheets.update_block(block, %{is_constant: prev}) do
          {:ok, _} -> {:ok, socket, {:toggle_constant, block_id, prev, current}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  # ===========================================================================
  # Undo: Table operations
  # ===========================================================================

  defp undo_action({:add_table_column, block_id, column_snapshot}, socket) do
    case Sheets.get_table_column(column_snapshot.id) do
      nil ->
        {:error, socket}

      column ->
        case Sheets.delete_table_column(column) do
          {:ok, _} -> {:ok, socket, {:add_table_column, block_id, column_snapshot}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:delete_table_column, block_id, column_snapshot, cell_values}, socket) do
    case Sheets.create_table_column_from_snapshot(block_id, column_snapshot, cell_values) do
      {:ok, column} ->
        new_snapshot = table_column_to_snapshot(column)
        {:ok, socket, {:delete_table_column, block_id, new_snapshot, cell_values}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp undo_action({:add_table_row, block_id, row_snapshot}, socket) do
    case Sheets.get_table_row(row_snapshot.id) do
      nil ->
        {:error, socket}

      row ->
        case Sheets.delete_table_row(row) do
          {:ok, _} -> {:ok, socket, {:add_table_row, block_id, row_snapshot}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:delete_table_row, block_id, row_snapshot, cell_values}, socket) do
    case Sheets.create_table_row_from_snapshot(block_id, row_snapshot, cell_values) do
      {:ok, row} ->
        new_snapshot = table_row_to_snapshot(row)
        {:ok, socket, {:delete_table_row, block_id, new_snapshot, cell_values}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp undo_action({:update_table_cell, block_id, row_id, col_slug, prev, _new}, socket) do
    case Sheets.get_table_row(row_id) do
      nil ->
        {:error, socket}

      row ->
        current = row.cells[col_slug]

        case Sheets.update_table_cell(row, col_slug, prev) do
          {:ok, _} ->
            {:ok, socket, {:update_table_cell, block_id, row_id, col_slug, prev, current}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:rename_table_column, block_id, col_id, prev_name, _new_name}, socket) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_name = column.name

        case Sheets.update_table_column(column, %{name: prev_name}) do
          {:ok, _} ->
            {:ok, socket, {:rename_table_column, block_id, col_id, prev_name, current_name}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:rename_table_row, block_id, row_id, prev_name, _new_name}, socket) do
    case Sheets.get_table_row(row_id) do
      nil ->
        {:error, socket}

      row ->
        current_name = row.name

        case Sheets.update_table_row(row, %{name: prev_name}) do
          {:ok, _} ->
            {:ok, socket, {:rename_table_row, block_id, row_id, prev_name, current_name}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:reorder_table_rows, block_id, prev_order, new_order}, socket) do
    case Sheets.reorder_table_rows(block_id, prev_order) do
      {:ok, _} -> {:ok, socket, {:reorder_table_rows, block_id, prev_order, new_order}}
      {:error, _} -> {:error, socket}
    end
  end

  defp undo_action(
         {:update_table_column_config, block_id, col_id, prev_config, _new_config},
         socket
       ) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_config = column.config

        case Sheets.update_table_column(column, %{config: prev_config}) do
          {:ok, _} ->
            {:ok, socket,
             {:update_table_column_config, block_id, col_id, prev_config, current_config}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:toggle_column_flag, block_id, col_id, flag, prev, _new}, socket) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current = Map.get(column, flag)

        case Sheets.update_table_column(column, %{flag => prev}) do
          {:ok, _} ->
            {:ok, socket, {:toggle_column_flag, block_id, col_id, flag, prev, current}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action(
         {:change_column_type, block_id, col_id, prev_type, _new_type, prev_cells},
         socket
       ) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_type = column.type
        current_cells = snapshot_column_cells(block_id, column.slug)

        with {:ok, _} <- Sheets.update_table_column(column, %{type: prev_type}),
             :ok <- restore_column_cells(column.slug, prev_cells) do
          {:ok, socket,
           {:change_column_type, block_id, col_id, prev_type, current_type, current_cells}}
        else
          _ -> {:error, socket}
        end
    end
  end

  # ===========================================================================
  # Undo: Compound actions
  # ===========================================================================

  defp undo_action({:compound, actions}, socket) do
    result =
      actions
      |> Enum.reverse()
      |> Enum.reduce_while({:ok, socket, []}, fn action, {:ok, sock, redo_items} ->
        case undo_action(action, sock) do
          {:ok, sock, redo_item} -> {:cont, {:ok, sock, [redo_item | redo_items]}}
          {:error, sock} -> {:halt, {:error, sock}}
        end
      end)

    case result do
      {:ok, socket, redo_items} -> {:ok, socket, {:compound, Enum.reverse(redo_items)}}
      {:error, socket} -> {:error, socket}
    end
  end

  # Fallback: unknown action type — skip silently
  defp undo_action(_action, socket), do: {:error, socket}

  # ===========================================================================
  # Redo: all types mirror undo with swapped prev/new
  # ===========================================================================

  defp redo_action({:update_sheet_name, _prev, new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{name: new}) do
      {:ok, _} ->
        {:ok, push_event(socket, "restore_page_content", %{name: new}),
         {:update_sheet_name, socket.assigns.sheet.name, new}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:update_sheet_shortcut, _prev, new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{shortcut: new}) do
      {:ok, _} ->
        {:ok, push_event(socket, "restore_page_content", %{shortcut: new || ""}),
         {:update_sheet_shortcut, socket.assigns.sheet.shortcut, new}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:update_sheet_color, _prev, new}, socket) do
    case Sheets.update_sheet(socket.assigns.sheet, %{color: new}) do
      {:ok, _} ->
        {:ok, socket, {:update_sheet_color, socket.assigns.sheet.color, new}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:create_block, snapshot}, socket) do
    case Sheets.create_block_from_snapshot(socket.assigns.sheet, snapshot) do
      {:ok, block} ->
        {:ok, socket, {:create_block, block_to_snapshot(block)}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:delete_block, snapshot}, socket) do
    case Sheets.get_block(snapshot.id) do
      nil ->
        {:error, socket}

      block ->
        case Sheets.delete_block(block) do
          {:ok, _} -> {:ok, socket, {:delete_block, snapshot}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:reorder_blocks, _prev_order, new_order}, socket) do
    case Sheets.reorder_blocks(socket.assigns.sheet.id, new_order) do
      {:ok, _} ->
        current_ids = Sheets.list_blocks(socket.assigns.sheet.id) |> Enum.map(& &1.id)
        {:ok, socket, {:reorder_blocks, current_ids, new_order}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:update_block_value, block_id, _prev, new}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current = block.value

        case Sheets.update_block_value(block, %{"content" => new}) do
          {:ok, _} -> {:ok, socket, {:update_block_value, block_id, current, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:update_block_config, block_id, _prev_config, new_config}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current_config = block.config

        case Sheets.update_block_config(block, new_config) do
          {:ok, _} ->
            {:ok, socket, {:update_block_config, block_id, current_config, new_config}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:toggle_constant, block_id, _prev, new}, socket) do
    case Sheets.get_block(block_id) do
      nil ->
        {:error, socket}

      block ->
        current = block.is_constant

        case Sheets.update_block(block, %{is_constant: new}) do
          {:ok, _} -> {:ok, socket, {:toggle_constant, block_id, current, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  # --- Table redo ---

  defp redo_action({:add_table_column, block_id, column_snapshot}, socket) do
    case Sheets.create_table_column_from_snapshot(block_id, column_snapshot, []) do
      {:ok, column} ->
        {:ok, socket, {:add_table_column, block_id, table_column_to_snapshot(column)}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:delete_table_column, block_id, column_snapshot, _cell_values}, socket) do
    case Sheets.get_table_column(column_snapshot.id) do
      nil ->
        {:error, socket}

      column ->
        current_cells = snapshot_column_cells(block_id, column.slug)

        case Sheets.delete_table_column(column) do
          {:ok, _} ->
            {:ok, socket, {:delete_table_column, block_id, column_snapshot, current_cells}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:add_table_row, block_id, row_snapshot}, socket) do
    case Sheets.create_table_row_from_snapshot(block_id, row_snapshot, row_snapshot.cells || %{}) do
      {:ok, row} ->
        {:ok, socket, {:add_table_row, block_id, table_row_to_snapshot(row)}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:delete_table_row, block_id, row_snapshot, cell_values}, socket) do
    case Sheets.get_table_row(row_snapshot.id) do
      nil ->
        {:error, socket}

      row ->
        case Sheets.delete_table_row(row) do
          {:ok, _} -> {:ok, socket, {:delete_table_row, block_id, row_snapshot, cell_values}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:update_table_cell, block_id, row_id, col_slug, _prev, new}, socket) do
    case Sheets.get_table_row(row_id) do
      nil ->
        {:error, socket}

      row ->
        current = row.cells[col_slug]

        case Sheets.update_table_cell(row, col_slug, new) do
          {:ok, _} ->
            {:ok, socket, {:update_table_cell, block_id, row_id, col_slug, current, new}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:rename_table_column, block_id, col_id, _prev_name, new_name}, socket) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_name = column.name

        case Sheets.update_table_column(column, %{name: new_name}) do
          {:ok, _} ->
            {:ok, socket, {:rename_table_column, block_id, col_id, current_name, new_name}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:rename_table_row, block_id, row_id, _prev_name, new_name}, socket) do
    case Sheets.get_table_row(row_id) do
      nil ->
        {:error, socket}

      row ->
        current_name = row.name

        case Sheets.update_table_row(row, %{name: new_name}) do
          {:ok, _} -> {:ok, socket, {:rename_table_row, block_id, row_id, current_name, new_name}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:reorder_table_rows, block_id, _prev_order, new_order}, socket) do
    current_order = Sheets.list_table_rows(block_id) |> Enum.map(& &1.id)

    case Sheets.reorder_table_rows(block_id, new_order) do
      {:ok, _} -> {:ok, socket, {:reorder_table_rows, block_id, current_order, new_order}}
      {:error, _} -> {:error, socket}
    end
  end

  defp redo_action(
         {:update_table_column_config, block_id, col_id, _prev_config, new_config},
         socket
       ) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_config = column.config

        case Sheets.update_table_column(column, %{config: new_config}) do
          {:ok, _} ->
            {:ok, socket,
             {:update_table_column_config, block_id, col_id, current_config, new_config}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:toggle_column_flag, block_id, col_id, flag, _prev, new}, socket) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current = Map.get(column, flag)

        case Sheets.update_table_column(column, %{flag => new}) do
          {:ok, _} ->
            {:ok, socket, {:toggle_column_flag, block_id, col_id, flag, current, new}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action(
         {:change_column_type, block_id, col_id, _prev_type, new_type, _prev_cells},
         socket
       ) do
    case Sheets.get_table_column(col_id) do
      nil ->
        {:error, socket}

      column ->
        current_type = column.type
        current_cells = snapshot_column_cells(block_id, column.slug)

        case Sheets.update_table_column(column, %{type: new_type}) do
          {:ok, _} ->
            {:ok, socket,
             {:change_column_type, block_id, col_id, current_type, new_type, current_cells}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:compound, actions}, socket) do
    result =
      Enum.reduce_while(actions, {:ok, socket, []}, fn action, {:ok, sock, undo_items} ->
        case redo_action(action, sock) do
          {:ok, sock, undo_item} -> {:cont, {:ok, sock, [undo_item | undo_items]}}
          {:error, sock} -> {:halt, {:error, sock}}
        end
      end)

    case result do
      {:ok, socket, undo_items} -> {:ok, socket, {:compound, Enum.reverse(undo_items)}}
      {:error, socket} -> {:error, socket}
    end
  end

  # Fallback: unknown action type
  defp redo_action(_action, socket), do: {:error, socket}

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp reload_sheet(socket) do
    project_id = socket.assigns.project.id
    sheet_id = socket.assigns.sheet.id

    sheet = Sheets.get_sheet_full!(project_id, sheet_id)
    blocks = ReferenceHelpers.load_blocks_with_references(sheet_id, project_id)
    sheets_tree = Sheets.list_sheets_tree(project_id)
    ancestors = Sheets.get_sheet_with_ancestors(project_id, sheet_id) || [sheet]

    socket
    |> assign(:sheet, sheet)
    |> assign(:blocks, blocks)
    |> assign(:sheets_tree, sheets_tree)
    |> assign(:ancestors, ancestors)
  end

  def table_column_to_snapshot(column) do
    %{
      id: column.id,
      block_id: column.block_id,
      name: column.name,
      slug: column.slug,
      type: column.type,
      position: column.position,
      is_constant: column.is_constant,
      required: column.required,
      config: column.config
    }
  end

  def table_row_to_snapshot(row) do
    %{
      id: row.id,
      block_id: row.block_id,
      name: row.name,
      shortcut: row.shortcut,
      position: row.position,
      cells: row.cells
    }
  end

  def snapshot_column_cells(block_id, column_slug) do
    block_id
    |> Sheets.list_table_rows()
    |> Enum.map(fn row -> {row.id, Map.get(row.cells || %{}, column_slug)} end)
  end

  defp restore_column_cells(column_slug, cell_values) do
    Enum.reduce_while(cell_values, :ok, fn {row_id, value}, _acc ->
      row_id
      |> Sheets.get_table_row()
      |> restore_single_cell(column_slug, value)
    end)
  end

  defp restore_single_cell(nil, _column_slug, _value), do: {:cont, :ok}

  defp restore_single_cell(row, column_slug, value) do
    case Sheets.update_table_cell(row, column_slug, value) do
      {:ok, _} -> {:cont, :ok}
      {:error, _} -> {:halt, {:error, :restore_failed}}
    end
  end
end

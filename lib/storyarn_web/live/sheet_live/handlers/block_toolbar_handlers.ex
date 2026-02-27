defmodule StoryarnWeb.SheetLive.Handlers.BlockToolbarHandlers do
  @moduledoc """
  Handles toolbar action events for the ContentTab LiveComponent.

  Covers: duplicate_block, toolbar_toggle_constant, move_block_up, move_block_down.

  The `helpers` map must contain:
    - `:reload_blocks`        - fn(socket) -> socket
    - `:maybe_create_version` - fn(socket) -> any
    - `:notify_parent`        - fn(socket, status) -> any
    - `:push_undo`            - fn(action) -> any
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # duplicate_block
  # ---------------------------------------------------------------------------

  @doc "Duplicates a block, placing the copy after the original."
  def handle_duplicate_block(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        case Sheets.duplicate_block(block) do
          {:ok, new_block} ->
            helpers.push_undo.({:create_block, UndoRedoHandlers.block_to_snapshot(new_block)})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not duplicate block."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # toolbar_toggle_constant
  # ---------------------------------------------------------------------------

  @doc "Toggles the is_constant flag on a block from the toolbar."
  def handle_toggle_constant(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        prev_value = block.is_constant
        new_value = !prev_value

        case Sheets.update_block(block, %{is_constant: new_value}) do
          {:ok, _updated} ->
            helpers.push_undo.({:toggle_constant, block.id, prev_value, new_value})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not toggle constant."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # move_block_up
  # ---------------------------------------------------------------------------

  @doc "Moves a block up by swapping with the previous block."
  def handle_move_block_up(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet_id = socket.assigns.sheet.id
    prev_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)

    case Sheets.move_block_up(block_id, sheet_id) do
      {:ok, :moved} ->
        new_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)
        helpers.push_undo.({:reorder_blocks, prev_order, new_order})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:ok, :already_first} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}
    end
  end

  # ---------------------------------------------------------------------------
  # move_block_down
  # ---------------------------------------------------------------------------

  @doc "Moves a block down by swapping with the next block."
  def handle_move_block_down(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    sheet_id = socket.assigns.sheet.id
    prev_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)

    case Sheets.move_block_down(block_id, sheet_id) do
      {:ok, :moved} ->
        new_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)
        helpers.push_undo.({:reorder_blocks, prev_order, new_order})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:ok, :already_last} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}
    end
  end
end

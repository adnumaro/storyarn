defmodule StoryarnWeb.SheetLive.Handlers.BlockCrudHandlers do
  @moduledoc """
  Handles block CRUD and column-layout events for the ContentTab LiveComponent.

  Each public function corresponds to one or more `handle_event` clauses in
  `ContentTab` and returns `{:noreply, socket}`.

  The `helpers` map must contain:
    - `:reload_blocks`       - fn(socket) -> socket
    - `:maybe_create_version`- fn(socket) -> any
    - `:notify_parent`       - fn(socket, status) -> any
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # add_block
  # ---------------------------------------------------------------------------

  @doc "Creates a new block of the given type on the current sheet."
  def handle_add_block(type, socket, helpers) do
    sheet = socket.assigns.sheet
    scope = socket.assigns.block_scope

    case Sheets.create_block(sheet, %{type: type, scope: scope}) do
      {:ok, block} ->
        helpers.push_undo.({:create_block, UndoRedoHandlers.block_to_snapshot(block)})
        helpers.notify_parent.(socket, :saved)

        {:noreply,
         socket
         |> assign(:show_block_menu, false)
         |> assign(:block_scope, "self")
         |> helpers.reload_blocks.()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create block."))}
    end
  end

  # ---------------------------------------------------------------------------
  # update_block_value
  # ---------------------------------------------------------------------------

  @doc "Updates the value content of a single block."
  def handle_update_block_value(block_id, value, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        prev_value = get_in(block.value, ["content"])
        value = maybe_clamp_number_value(block, value)

        case Sheets.update_block_value(block, %{"content" => value}) do
          {:ok, _updated} ->
            helpers.push_undo.({:update_block_value, block.id, prev_value, value})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not update block."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # delete_block
  # ---------------------------------------------------------------------------

  @doc "Deletes a block by ID."
  def handle_delete_block(block_id, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(block_id)
    project_id = socket.assigns.project.id

    case Sheets.get_block_in_project(block_id, project_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Block not found."))}

      block ->
        snapshot = UndoRedoHandlers.block_to_snapshot(block)

        case Sheets.delete_block(block) do
          {:ok, _} ->
            helpers.push_undo.({:delete_block, snapshot})
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete block."))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # reorder
  # ---------------------------------------------------------------------------

  @doc "Reorders blocks within the sheet."
  def handle_reorder(ids, socket, helpers) do
    sheet_id = socket.assigns.sheet.id
    prev_order = Sheets.list_blocks(sheet_id) |> Enum.map(& &1.id)
    block_ids = Enum.map(ids, &ContentTabHelpers.to_integer/1)

    case Sheets.reorder_blocks(sheet_id, block_ids) do
      {:ok, _} ->
        helpers.push_undo.({:reorder_blocks, prev_order, block_ids})
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        {:noreply, helpers.reload_blocks.(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
    end
  end

  # ---------------------------------------------------------------------------
  # reorder_with_columns
  # ---------------------------------------------------------------------------

  @doc "Reorders blocks with column-layout metadata."
  def handle_reorder_with_columns(items, socket, helpers) do
    sheet_id = socket.assigns.sheet.id

    blocks_by_id =
      Sheets.list_blocks(sheet_id)
      |> Map.new(fn b -> {b.id, b} end)

    # Snapshot current layout for undo
    prev_layout = snapshot_block_layout(blocks_by_id)

    sanitized =
      items
      |> Enum.map(&ContentTabHelpers.sanitize_column_item(&1, blocks_by_id))
      |> Enum.reject(&is_nil/1)

    case Sheets.reorder_blocks_with_columns(sheet_id, sanitized) do
      {:ok, _} ->
        helpers.maybe_create_version.(socket)
        helpers.notify_parent.(socket, :saved)
        helpers.push_undo.({:reorder_blocks_with_columns, prev_layout, sanitized})
        {:noreply, helpers.reload_blocks.(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not reorder blocks."))}
    end
  end

  defp snapshot_block_layout(blocks_by_id) do
    blocks_by_id
    |> Map.values()
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn b ->
      %{id: b.id, column_group_id: b.column_group_id, column_index: b.column_index}
    end)
  end

  # ---------------------------------------------------------------------------
  # create_column_group
  # ---------------------------------------------------------------------------

  @doc "Creates a column group from a set of block IDs."
  def handle_create_column_group(block_ids, socket, helpers) do
    sheet_id = socket.assigns.sheet.id

    blocks_by_id =
      Sheets.list_blocks(sheet_id)
      |> Map.new(fn b -> {b.id, b} end)

    requested_ids = Enum.map(block_ids, &ContentTabHelpers.to_integer/1)
    blocks = Enum.map(requested_ids, &Map.get(blocks_by_id, &1))

    case ContentTabHelpers.validate_column_group_blocks(blocks) do
      :ok ->
        validated_ids = Enum.map(blocks, & &1.id)

        case Sheets.create_column_group(sheet_id, validated_ids) do
          {:ok, _group_id} ->
            helpers.maybe_create_version.(socket)
            helpers.notify_parent.(socket, :saved)
            {:noreply, helpers.reload_blocks.(socket)}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("sheets", "Could not create column group."))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # ---------------------------------------------------------------------------
  # Number constraint clamping
  # ---------------------------------------------------------------------------

  defp maybe_clamp_number_value(%{type: "number", config: config}, value) when is_binary(value) do
    Sheets.number_clamp_and_format(value, config)
  end

  defp maybe_clamp_number_value(_block, value), do: value
end

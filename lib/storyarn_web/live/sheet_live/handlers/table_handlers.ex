defmodule StoryarnWeb.SheetLive.Handlers.TableHandlers do
  @moduledoc """
  Handles all table block events for the ContentTab LiveComponent.

  Each public function corresponds to one or more `handle_event` clauses in
  `ContentTab` and returns `{:noreply, socket}`.

  The `helpers` map must contain:
    - `:reload_blocks`       - fn(socket) -> socket
    - `:maybe_create_version`- fn(socket) -> any
    - `:notify_parent`       - fn(socket, status) -> any
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ===========================================================================
  # Column resize (silent — no save indicator flash)
  # ===========================================================================

  @doc "Persists a column width after drag-resize. No reload, no save indicator."
  def handle_resize_column(params, socket) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column),
         {:ok, width} <- sanitize_width(params["width"]) do
      new_config = Map.put(column.config || %{}, "width", width)

      case Sheets.update_table_column(column, %{config: new_config}) do
        {:ok, _} -> {:noreply, socket}
        {:error, _} -> {:noreply, socket}
      end
    else
      :invalid_width -> {:noreply, socket}
      other -> other
    end
  end

  defp sanitize_width(w) when is_number(w) do
    width = w |> max(80) |> min(2000) |> round()
    {:ok, width}
  end

  defp sanitize_width(_), do: :invalid_width

  # ===========================================================================
  # Existing table events (extracted from ContentTab)
  # ===========================================================================

  @doc "Updates a single cell value in a table row."
  def handle_update_cell(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    column_slug = params["column-slug"]

    value =
      if params["type"] == "multi_select" do
        (params["value"] || "")
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        params["value"]
      end

    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      col = find_column_by_slug(socket, row.block_id, column_slug)

      if col && col.required && value_empty?(value) do
        {:noreply, err(socket, :required_field)}
      else
        case Sheets.update_table_cell(row, column_slug, value) do
          {:ok, _} -> save_and_reload(socket, helpers)
          {:error, _} -> {:noreply, err(socket, :cell_update)}
        end
      end
    end
  end

  @doc "Toggles the collapsed state of a table block."
  def handle_toggle_collapse(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block-id"])
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)
    collapsed = block.config["collapsed"] || false
    new_config = Map.put(block.config || %{}, "collapsed", !collapsed)

    case Sheets.update_block_config(block, new_config) do
      {:ok, _} ->
        {:noreply, helpers.reload_blocks.(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not toggle table."))}
    end
  end

  @doc "Toggles a boolean cell value in a table."
  def handle_toggle_cell_boolean(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    column_slug = params["column-slug"]
    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      current = row.cells[column_slug]
      new_value = if current == true, do: false, else: true

      case Sheets.update_table_cell(row, column_slug, new_value) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :cell_update)}
      end
    end
  end

  # ===========================================================================
  # Add column / row
  # ===========================================================================

  @doc "Adds a new column to a table block."
  def handle_add_column(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block-id"])
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    col_count = length(Map.get(socket.assigns.table_data, block_id, %{columns: []}).columns)
    default_name = dgettext("sheets", "Column %{n}", n: col_count + 1)

    case Sheets.create_table_column(block, %{name: default_name}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :column_add)}
    end
  end

  @doc "Adds a new row to a table block."
  def handle_add_row(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block-id"])
    project_id = socket.assigns.project.id
    block = Sheets.get_block_in_project!(block_id, project_id)

    row_count = length(Map.get(socket.assigns.table_data, block_id, %{rows: []}).rows)
    default_name = dgettext("sheets", "Row %{n}", n: row_count + 1)

    case Sheets.create_table_row(block, %{name: default_name}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :row_add)}
    end
  end

  # ===========================================================================
  # Column management
  # ===========================================================================

  @doc "Renames a table column."
  def handle_rename_column(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    new_name = String.trim(params["value"] || "")
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      if new_name == "" or new_name == column.name do
        {:noreply, socket}
      else
        do_rename_column(column, new_name, socket, helpers)
      end
    end
  end

  @doc "Changes a column type directly (no confirmation)."
  def handle_change_column_type(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    new_type = params["new-type"]
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      do_change_column_type(column, new_type, socket, helpers)
    end
  end

  @doc "Toggles the is_constant flag on a column."
  def handle_toggle_column_constant(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      case Sheets.update_table_column(column, %{is_constant: !column.is_constant}) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :column_update)}
      end
    end
  end

  @doc "Toggles the required flag on a column."
  def handle_toggle_column_required(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      case Sheets.update_table_column(column, %{required: !column.required}) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :column_update)}
      end
    end
  end

  @doc "Deletes a table column directly."
  def handle_delete_column(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      do_delete_column(column, socket, helpers)
    end
  end

  # ===========================================================================
  # Row management
  # ===========================================================================

  @doc "Renames a table row."
  def handle_rename_row(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    new_name = String.trim(params["value"] || "")
    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      if new_name == "" or new_name == row.name do
        {:noreply, socket}
      else
        do_rename_row(row, new_name, socket, helpers)
      end
    end
  end

  @doc "Handles keydown on row rename input (Enter to save)."
  def handle_rename_row_keydown(%{"key" => "Enter"} = params, socket, helpers) do
    handle_rename_row(params, socket, helpers)
  end

  def handle_rename_row_keydown(_params, socket, _helpers) do
    {:noreply, socket}
  end

  @doc "Deletes a table row directly."
  def handle_delete_row(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      do_delete_row(row, socket, helpers)
    end
  end

  @doc "Reorders table rows by their IDs."
  def handle_reorder_rows(params, socket, helpers) do
    block_id = ContentTabHelpers.to_integer(params["block_id"])
    row_ids = Enum.map(params["row_ids"] || [], &ContentTabHelpers.to_integer/1)

    with :ok <- verify_block_ownership(socket, block_id) do
      case Sheets.reorder_table_rows(block_id, row_ids) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :row_reorder)}
      end
    end
  end

  # ===========================================================================
  # Select/Multi-Select cell events (hook-driven)
  # ===========================================================================

  @doc "Sets a select cell value to the given key (or clears it)."
  def handle_select_table_cell(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    column_slug = params["column-slug"]
    key = params["key"]
    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      value = if key == "", do: nil, else: key
      col = find_column_by_slug(socket, row.block_id, column_slug)

      if col && col.required && value_empty?(value) do
        {:noreply, err(socket, :required_field)}
      else
        case Sheets.update_table_cell(row, column_slug, value) do
          {:ok, _} -> save_and_reload(socket, helpers)
          {:error, _} -> {:noreply, err(socket, :cell_update)}
        end
      end
    end
  end

  @doc "Toggles a key in a multi-select cell (add if absent, remove if present)."
  def handle_toggle_table_cell_multi_select(params, socket, helpers) do
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    column_slug = params["column-slug"]
    key = params["key"]
    row = Sheets.get_table_row!(row_id)

    with :ok <- verify_row_ownership(socket, row) do
      current = row.cells[column_slug] || []
      current = if is_list(current), do: current, else: []

      new_value =
        if key in current,
          do: List.delete(current, key),
          else: current ++ [key]

      col = find_column_by_slug(socket, row.block_id, column_slug)

      if col && col.required && value_empty?(new_value) do
        {:noreply, err(socket, :required_field)}
      else
        case Sheets.update_table_cell(row, column_slug, new_value) do
          {:ok, _} -> save_and_reload(socket, helpers)
          {:error, _} -> {:noreply, err(socket, :cell_update)}
        end
      end
    end
  end

  @doc "Adds a new option to a column and selects/toggles it in the cell."
  def handle_add_table_cell_option(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    row_id = ContentTabHelpers.to_integer(params["row-id"])
    column_slug = params["column-slug"]
    label = String.trim(params["value"] || "")

    if label == "" do
      {:noreply, socket}
    else
      column = Sheets.get_table_column!(column_id)

      with :ok <- verify_column_ownership(socket, column) do
        existing_options = (column.config || %{})["options"] || []
        key = slugify(label)
        new_option = %{"key" => key, "value" => label}
        new_config = Map.put(column.config || %{}, "options", existing_options ++ [new_option])

        case Sheets.update_table_column(column, %{config: new_config}) do
          {:ok, _} ->
            # Also select/toggle the new option in the cell
            row = Sheets.get_table_row!(row_id)

            new_cell_value =
              if column.type == "multi_select" do
                current = row.cells[column_slug] || []
                current = if is_list(current), do: current, else: []
                current ++ [key]
              else
                key
              end

            case Sheets.update_table_cell(row, column_slug, new_cell_value) do
              {:ok, _} -> save_and_reload(socket, helpers)
              {:error, _} -> save_and_reload(socket, helpers)
            end

          {:error, _} ->
            {:noreply, err(socket, :column_update)}
        end
      end
    end
  end

  # ===========================================================================
  # Select/Multi-Select options management
  # ===========================================================================

  @doc "Adds a new option to a select/multi_select column."
  def handle_add_column_option(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    label = String.trim(params["value"] || "")

    if label == "" do
      {:noreply, socket}
    else
      column = Sheets.get_table_column!(column_id)

      with :ok <- verify_column_ownership(socket, column) do
        do_add_column_option(column, label, socket, helpers)
      end
    end
  end

  @doc "Removes an option from a select/multi_select column by key."
  def handle_remove_column_option(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    key = params["key"]
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      existing_options = (column.config || %{})["options"] || []
      new_options = Enum.reject(existing_options, fn opt -> opt["key"] == key end)
      new_config = Map.put(column.config || %{}, "options", new_options)

      case Sheets.update_table_column(column, %{config: new_config}) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :column_update)}
      end
    end
  end

  @doc "Updates an option value at a given index in a select/multi_select column."
  def handle_update_column_option(params, socket, helpers) do
    column_id = ContentTabHelpers.to_integer(params["column-id"])
    index = ContentTabHelpers.to_integer(params["index"])
    new_value = String.trim(params["value"] || "")
    column = Sheets.get_table_column!(column_id)

    with :ok <- verify_column_ownership(socket, column) do
      existing_options = (column.config || %{})["options"] || []

      new_options =
        List.update_at(existing_options, index, fn opt ->
          %{"key" => slugify(new_value), "value" => new_value}
          |> Map.merge(Map.drop(opt, ["key", "value"]))
        end)

      new_config = Map.put(column.config || %{}, "options", new_options)

      case Sheets.update_table_column(column, %{config: new_config}) do
        {:ok, _} -> save_and_reload(socket, helpers)
        {:error, _} -> {:noreply, err(socket, :column_update)}
      end
    end
  end

  # ===========================================================================
  # Private helpers — IDOR verification
  # ===========================================================================

  defp verify_column_ownership(socket, column) do
    if Map.has_key?(socket.assigns.table_data, column.block_id),
      do: :ok,
      else: {:noreply, err(socket, :column_update)}
  end

  defp verify_row_ownership(socket, row) do
    if Map.has_key?(socket.assigns.table_data, row.block_id),
      do: :ok,
      else: {:noreply, err(socket, :cell_update)}
  end

  defp verify_block_ownership(socket, block_id) do
    if Map.has_key?(socket.assigns.table_data, block_id),
      do: :ok,
      else: {:noreply, err(socket, :row_reorder)}
  end

  # ===========================================================================
  # Private helpers — common patterns
  # ===========================================================================

  defp save_and_reload(socket, helpers) do
    helpers.maybe_create_version.(socket)
    helpers.notify_parent.(socket, :saved)
    {:noreply, helpers.reload_blocks.(socket)}
  end

  # Error messages — using dgettext macros so strings are extractable
  defp err(socket, :cell_update),
    do: put_flash(socket, :error, dgettext("sheets", "Could not update cell."))

  defp err(socket, :column_add),
    do: put_flash(socket, :error, dgettext("sheets", "Could not add column."))

  defp err(socket, :column_update),
    do: put_flash(socket, :error, dgettext("sheets", "Could not update column."))

  defp err(socket, :column_rename),
    do: put_flash(socket, :error, dgettext("sheets", "Could not rename column."))

  defp err(socket, :column_type),
    do: put_flash(socket, :error, dgettext("sheets", "Could not change column type."))

  defp err(socket, :column_delete),
    do: put_flash(socket, :error, dgettext("sheets", "Could not delete column."))

  defp err(socket, :column_last),
    do: put_flash(socket, :error, dgettext("sheets", "Cannot delete the last column."))

  defp err(socket, :row_add),
    do: put_flash(socket, :error, dgettext("sheets", "Could not add row."))

  defp err(socket, :row_rename),
    do: put_flash(socket, :error, dgettext("sheets", "Could not rename row."))

  defp err(socket, :row_delete),
    do: put_flash(socket, :error, dgettext("sheets", "Could not delete row."))

  defp err(socket, :row_last),
    do: put_flash(socket, :error, dgettext("sheets", "Cannot delete the last row."))

  defp err(socket, :row_reorder),
    do: put_flash(socket, :error, dgettext("sheets", "Could not reorder rows."))

  defp err(socket, :required_field),
    do: put_flash(socket, :error, dgettext("sheets", "This field is required."))

  # Looks up a column from socket.assigns.table_data by block_id + slug
  defp find_column_by_slug(socket, block_id, slug) do
    case Map.get(socket.assigns.table_data, block_id) do
      nil -> nil
      %{columns: columns} -> Enum.find(columns, fn c -> c.slug == slug end)
      _ -> nil
    end
  end

  defp value_empty?(nil), do: true
  defp value_empty?(""), do: true
  defp value_empty?([]), do: true
  defp value_empty?(_), do: false

  # ===========================================================================
  # Private helpers — extracted operations (reduce nesting)
  # ===========================================================================

  defp do_change_column_type(column, new_type, socket, helpers) do
    case Sheets.update_table_column(column, %{type: new_type}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :column_type)}
    end
  end

  defp do_rename_column(column, new_name, socket, helpers) do
    case Sheets.update_table_column(column, %{name: new_name}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :column_rename)}
    end
  end

  defp do_rename_row(row, new_name, socket, helpers) do
    case Sheets.update_table_row(row, %{name: new_name}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :row_rename)}
    end
  end

  defp do_delete_column(column, socket, helpers) do
    case Sheets.delete_table_column(column) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, :last_column} -> {:noreply, err(socket, :column_last)}
      {:error, _} -> {:noreply, err(socket, :column_delete)}
    end
  end

  defp do_delete_row(row, socket, helpers) do
    case Sheets.delete_table_row(row) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, :last_row} -> {:noreply, err(socket, :row_last)}
      {:error, _} -> {:noreply, err(socket, :row_delete)}
    end
  end

  defp do_add_column_option(column, label, socket, helpers) do
    existing_options = (column.config || %{})["options"] || []
    key = slugify(label)
    new_option = %{"key" => key, "value" => label}
    new_config = Map.put(column.config || %{}, "options", existing_options ++ [new_option])

    case Sheets.update_table_column(column, %{config: new_config}) do
      {:ok, _} -> save_and_reload(socket, helpers)
      {:error, _} -> {:noreply, err(socket, :column_update)}
    end
  end

  defp slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s_-]/, "")
    |> String.replace(~r/[\s-]+/, "_")
    |> String.trim("_")
    |> then(fn
      "" -> "option"
      slug -> slug
    end)
  end
end

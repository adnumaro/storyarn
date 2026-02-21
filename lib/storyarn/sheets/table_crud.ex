defmodule Storyarn.Sheets.TableCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Repo
  alias Storyarn.Sheets.{Block, TableColumn, TableRow}

  # =============================================================================
  # Column Operations
  # =============================================================================

  @doc "Lists all columns for a block, ordered by position."
  def list_columns(block_id) do
    from(c in TableColumn,
      where: c.block_id == ^block_id,
      order_by: [asc: c.position]
    )
    |> Repo.all()
  end

  @doc "Gets a single column by ID. Raises if not found."
  def get_column!(column_id) do
    Repo.get!(TableColumn, column_id)
  end

  @doc """
  Creates a new column on a table block.
  Auto-generates slug, auto-assigns position, and adds empty cell to all existing rows.
  """
  def create_column(%Block{id: block_id, type: "table"}, attrs) do
    position = attrs[:position] || next_column_position(block_id)
    existing_slugs = list_column_slugs(block_id)

    changeset =
      %TableColumn{block_id: block_id}
      |> TableColumn.create_changeset(Map.put(attrs, :position, position))

    slug = Ecto.Changeset.get_field(changeset, :slug)
    unique_slug = ensure_unique_slug(slug, existing_slugs)

    changeset =
      if unique_slug != slug do
        Ecto.Changeset.put_change(changeset, :slug, unique_slug)
      else
        changeset
      end

    Multi.new()
    |> Multi.insert(:column, changeset)
    |> Multi.run(:add_cells, fn _repo, %{column: column} ->
      add_cell_to_all_rows(block_id, column.slug)
      {:ok, :done}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{column: column}} -> {:ok, column}
      {:error, :column, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates a column. Handles rename (slug migration) and type change (cell reset).
  """
  def update_column(%TableColumn{} = column, attrs) do
    changeset = TableColumn.update_changeset(column, attrs)
    new_slug = Ecto.Changeset.get_field(changeset, :slug)
    new_type = Ecto.Changeset.get_field(changeset, :type)
    old_slug = column.slug
    old_type = column.type

    slug_changed? = new_slug != old_slug
    type_changed? = new_type != old_type

    # Ensure unique slug if it changed
    changeset =
      if slug_changed? do
        existing_slugs = list_column_slugs(column.block_id, column.id)
        unique_slug = ensure_unique_slug(new_slug, existing_slugs)
        Ecto.Changeset.put_change(changeset, :slug, unique_slug)
      else
        changeset
      end

    final_new_slug = Ecto.Changeset.get_field(changeset, :slug)

    multi =
      Multi.new()
      |> Multi.update(:column, changeset)

    # Migrate cell keys if slug changed
    multi =
      if slug_changed? do
        Multi.run(multi, :migrate_cells, fn _repo, _changes ->
          migrate_cells_key(column.block_id, old_slug, final_new_slug)
        end)
      else
        multi
      end

    # Reset cells if type changed
    multi =
      if type_changed? do
        Multi.run(multi, :reset_cells, fn _repo, _changes ->
          reset_cells_for_column(column.block_id, final_new_slug)
        end)
      else
        multi
      end

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{column: column}} -> {:ok, column}
      {:error, :column, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a column. Prevents deletion of the last column.
  Removes the column's cell key from all rows.
  """
  def delete_column(%TableColumn{} = column) do
    column_count =
      from(c in TableColumn, where: c.block_id == ^column.block_id, select: count(c.id))
      |> Repo.one()

    if column_count <= 1 do
      {:error, :last_column}
    else
      Multi.new()
      |> Multi.delete(:column, column)
      |> Multi.run(:remove_cells, fn _repo, _changes ->
        remove_cell_from_all_rows(column.block_id, column.slug)
        {:ok, :done}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{column: column}} -> {:ok, column}
        {:error, :column, changeset, _} -> {:error, changeset}
      end
    end
  end

  @doc "Reorders columns by updating their positions."
  def reorder_columns(block_id, column_ids) when is_list(column_ids) do
    Repo.transaction(fn ->
      column_ids
      |> Enum.with_index()
      |> Enum.each(fn {column_id, index} ->
        from(c in TableColumn,
          where: c.id == ^column_id and c.block_id == ^block_id
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_columns(block_id)
    end)
  end

  @doc """
  Batch loads table data (columns + rows) for multiple blocks at once.
  Returns a map of block_id => %{columns: [...], rows: [...]}.
  """
  def batch_load_table_data(block_ids) when is_list(block_ids) do
    columns =
      from(c in TableColumn,
        where: c.block_id in ^block_ids,
        order_by: [asc: c.block_id, asc: c.position]
      )
      |> Repo.all()

    rows =
      from(r in TableRow,
        where: r.block_id in ^block_ids,
        order_by: [asc: r.block_id, asc: r.position]
      )
      |> Repo.all()

    columns_by_block = Enum.group_by(columns, & &1.block_id)
    rows_by_block = Enum.group_by(rows, & &1.block_id)

    Map.new(block_ids, fn block_id ->
      {block_id,
       %{
         columns: Map.get(columns_by_block, block_id, []),
         rows: Map.get(rows_by_block, block_id, [])
       }}
    end)
  end

  # =============================================================================
  # Row Operations
  # =============================================================================

  @doc "Lists all rows for a block, ordered by position."
  def list_rows(block_id) do
    from(r in TableRow,
      where: r.block_id == ^block_id,
      order_by: [asc: r.position]
    )
    |> Repo.all()
  end

  @doc "Gets a single row by ID. Raises if not found."
  def get_row!(row_id) do
    Repo.get!(TableRow, row_id)
  end

  @doc """
  Creates a new row on a table block.
  Auto-generates slug, auto-assigns position, initializes cells for all columns.
  """
  def create_row(%Block{id: block_id, type: "table"}, attrs) do
    position = attrs[:position] || next_row_position(block_id)
    existing_slugs = list_row_slugs(block_id)

    # Initialize cells for all existing columns
    column_slugs = list_column_slugs(block_id)
    default_cells = Map.new(column_slugs, fn slug -> {slug, nil} end)
    cells = Map.merge(default_cells, attrs[:cells] || %{})

    changeset =
      %TableRow{block_id: block_id}
      |> TableRow.create_changeset(
        attrs
        |> Map.put(:position, position)
        |> Map.put(:cells, cells)
      )

    slug = Ecto.Changeset.get_field(changeset, :slug)
    unique_slug = ensure_unique_slug(slug, existing_slugs)

    changeset =
      if unique_slug != slug do
        Ecto.Changeset.put_change(changeset, :slug, unique_slug)
      else
        changeset
      end

    case Repo.insert(changeset) do
      {:ok, row} -> {:ok, row}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Updates a row (rename → re-slug)."
  def update_row(%TableRow{} = row, attrs) do
    changeset = TableRow.update_changeset(row, attrs)
    new_slug = Ecto.Changeset.get_field(changeset, :slug)

    changeset =
      if new_slug != row.slug do
        existing_slugs = list_row_slugs(row.block_id, row.id)
        unique_slug = ensure_unique_slug(new_slug, existing_slugs)
        Ecto.Changeset.put_change(changeset, :slug, unique_slug)
      else
        changeset
      end

    Repo.update(changeset)
  end

  @doc "Deletes a row. Prevents deletion of the last row."
  def delete_row(%TableRow{} = row) do
    row_count =
      from(r in TableRow, where: r.block_id == ^row.block_id, select: count(r.id))
      |> Repo.one()

    if row_count <= 1 do
      {:error, :last_row}
    else
      Repo.delete(row)
    end
  end

  @doc "Reorders rows by updating their positions."
  def reorder_rows(block_id, row_ids) when is_list(row_ids) do
    Repo.transaction(fn ->
      row_ids
      |> Enum.with_index()
      |> Enum.each(fn {row_id, index} ->
        from(r in TableRow,
          where: r.id == ^row_id and r.block_id == ^block_id
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_rows(block_id)
    end)
  end

  @doc "Updates a single cell value in a row."
  def update_cell(%TableRow{} = row, column_slug, value) do
    new_cells = Map.put(row.cells, column_slug, value)

    row
    |> TableRow.cells_changeset(%{cells: new_cells})
    |> Repo.update()
  end

  @doc "Batch updates multiple cells in a row."
  def update_cells(%TableRow{} = row, cells_map) when is_map(cells_map) do
    new_cells = Map.merge(row.cells, cells_map)

    row
    |> TableRow.cells_changeset(%{cells: new_cells})
    |> Repo.update()
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp next_column_position(block_id) do
    from(c in TableColumn,
      where: c.block_id == ^block_id,
      select: max(c.position)
    )
    |> Repo.one()
    |> then(fn max_pos -> (max_pos || -1) + 1 end)
  end

  defp next_row_position(block_id) do
    from(r in TableRow,
      where: r.block_id == ^block_id,
      select: max(r.position)
    )
    |> Repo.one()
    |> then(fn max_pos -> (max_pos || -1) + 1 end)
  end

  defp list_column_slugs(block_id, exclude_id \\ nil) do
    query = from(c in TableColumn, where: c.block_id == ^block_id, select: c.slug)

    query =
      if exclude_id do
        where(query, [c], c.id != ^exclude_id)
      else
        query
      end

    Repo.all(query)
  end

  defp list_row_slugs(block_id, exclude_id \\ nil) do
    query = from(r in TableRow, where: r.block_id == ^block_id, select: r.slug)

    query =
      if exclude_id do
        where(query, [r], r.id != ^exclude_id)
      else
        query
      end

    Repo.all(query)
  end

  # Same dedup pattern as BlockCrud.find_unique_variable_name/2
  defp ensure_unique_slug(slug, existing_slugs) do
    if slug in existing_slugs do
      find_unique_slug(slug, existing_slugs, 2)
    else
      slug
    end
  end

  defp find_unique_slug(base, existing, suffix) do
    candidate = "#{base}_#{suffix}"

    if candidate in existing do
      find_unique_slug(base, existing, suffix + 1)
    else
      candidate
    end
  end

  # Adds a cell key with nil value to all rows of a block
  defp add_cell_to_all_rows(block_id, column_slug) do
    rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id))

    Enum.each(rows, fn row ->
      unless Map.has_key?(row.cells, column_slug) do
        new_cells = Map.put(row.cells, column_slug, nil)

        row
        |> TableRow.cells_changeset(%{cells: new_cells})
        |> Repo.update!()
      end
    end)
  end

  # Removes a cell key from all rows of a block
  defp remove_cell_from_all_rows(block_id, column_slug) do
    rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id))

    Enum.each(rows, fn row ->
      new_cells = Map.delete(row.cells, column_slug)

      row
      |> TableRow.cells_changeset(%{cells: new_cells})
      |> Repo.update!()
    end)
  end

  # Migrates JSONB cell keys when a column is renamed.
  # Called within Multi.run (already in a transaction), so updates directly.
  defp migrate_cells_key(block_id, old_slug, new_slug) do
    rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id))

    Enum.each(rows, fn row ->
      {value, rest} = Map.pop(row.cells, old_slug)
      new_cells = Map.put(rest, new_slug, value)

      row
      |> TableRow.cells_changeset(%{cells: new_cells})
      |> Repo.update!()
    end)

    {:ok, :done}
  end

  # Resets cell values to nil for a specific column across all rows.
  # Called within Multi.run (already in a transaction), so updates directly.
  defp reset_cells_for_column(block_id, column_slug) do
    rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id))

    Enum.each(rows, fn row ->
      new_cells = Map.put(row.cells, column_slug, nil)

      row
      |> TableRow.cells_changeset(%{cells: new_cells})
      |> Repo.update!()
    end)

    {:ok, :done}
  end
end

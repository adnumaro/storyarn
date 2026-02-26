defmodule Storyarn.Sheets.TableCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}
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

  @doc "Gets a single column by ID. Returns nil if not found."
  def get_column(column_id) do
    Repo.get(TableColumn, column_id)
  end

  @doc """
  Creates a new column on a table block.
  Auto-generates slug, auto-assigns position, and adds empty cell to all existing rows.
  """
  def create_column(%Block{id: block_id, type: "table"} = block, attrs) do
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

    result =
      Multi.new()
      |> Multi.insert(:column, changeset)
      |> Multi.run(:add_cells, fn _repo, %{column: column} ->
        add_cell_to_all_rows(block_id, column.slug)
        {:ok, :done}
      end)
      |> Multi.run(:sync_children, fn _repo, %{column: column} ->
        sync_column_to_children(block, column, :create)
        {:ok, :done}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{column: column}} -> {:ok, column}
        {:error, :column, changeset, _} -> {:error, changeset}
      end

    result
  end

  @doc """
  Updates a column. Handles rename (slug migration) and type change (cell reset).
  """
  def update_column(%TableColumn{} = column, attrs) do
    changeset =
      column
      |> TableColumn.update_changeset(attrs)
      |> maybe_sync_table_slug(column.block_id)

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

    # Sync to children within the same transaction
    multi =
      Multi.run(multi, :sync_children, fn _repo, %{column: updated_column} ->
        sync_column_to_children(column.block_id, updated_column, :update, old_slug, type_changed?)
        {:ok, :done}
      end)

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
      |> Multi.run(:sync_children, fn _repo, _changes ->
        sync_column_to_children(column.block_id, column, :delete)
        {:ok, :done}
      end)
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

  @doc """
  Recreates a column from a snapshot map (for undo/redo).
  Also restores cell values for the column across all rows.
  """
  def create_column_from_snapshot(block_id, snapshot, cell_values) do
    changeset =
      %TableColumn{block_id: block_id}
      |> TableColumn.create_changeset(%{
        name: snapshot.name,
        type: snapshot.type,
        position: snapshot.position,
        is_constant: Map.get(snapshot, :is_constant, false),
        required: Map.get(snapshot, :required, false),
        config: Map.get(snapshot, :config, %{})
      })
      # Force slug to match the original
      |> Ecto.Changeset.force_change(:slug, snapshot.slug)

    case Repo.insert(changeset) do
      {:ok, column} ->
        restore_column_cell_values(column.slug, cell_values)
        {:ok, column}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp restore_column_cell_values(column_slug, cell_values) do
    for {row_id, value} <- cell_values do
      case Repo.get(TableRow, row_id) do
        nil ->
          :skip

        row ->
          new_cells = Map.put(row.cells || %{}, column_slug, value)
          row |> TableRow.cells_changeset(%{cells: new_cells}) |> Repo.update()
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

  @doc "Gets a single row by ID. Returns nil if not found."
  def get_row(row_id) do
    Repo.get(TableRow, row_id)
  end

  @doc """
  Creates a new row on a table block.
  Auto-generates slug, auto-assigns position, initializes cells for all columns.
  """
  def create_row(%Block{id: block_id, type: "table"} = block, attrs) do
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

    result =
      Multi.new()
      |> Multi.insert(:row, changeset)
      |> Multi.run(:sync_children, fn _repo, %{row: row} ->
        sync_row_to_children(block, row, :create)
        {:ok, :done}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{row: row}} -> {:ok, row}
        {:error, :row, changeset, _} -> {:error, changeset}
      end

    result
  end

  @doc "Updates a row (rename → re-slug)."
  def update_row(%TableRow{} = row, attrs) do
    old_slug = row.slug

    changeset =
      row
      |> TableRow.update_changeset(attrs)
      |> maybe_sync_table_slug(row.block_id)

    new_slug = Ecto.Changeset.get_field(changeset, :slug)

    changeset =
      if new_slug != row.slug do
        existing_slugs = list_row_slugs(row.block_id, row.id)
        unique_slug = ensure_unique_slug(new_slug, existing_slugs)
        Ecto.Changeset.put_change(changeset, :slug, unique_slug)
      else
        changeset
      end

    Multi.new()
    |> Multi.update(:row, changeset)
    |> Multi.run(:sync_children, fn _repo, %{row: updated_row} ->
      sync_row_to_children(row.block_id, updated_row, :update, old_slug)
      {:ok, :done}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{row: row}} -> {:ok, row}
      {:error, :row, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Recreates a row from a snapshot map (for undo/redo).
  """
  def create_row_from_snapshot(block_id, snapshot, cells) do
    changeset =
      %TableRow{block_id: block_id}
      |> TableRow.create_changeset(%{
        name: snapshot.name,
        position: snapshot.position,
        cells: cells
      })
      # Force slug to match the original
      |> Ecto.Changeset.force_change(:slug, snapshot.slug)

    Repo.insert(changeset)
  end

  @doc "Deletes a row. Prevents deletion of the last row."
  def delete_row(%TableRow{} = row) do
    row_count =
      from(r in TableRow, where: r.block_id == ^row.block_id, select: count(r.id))
      |> Repo.one()

    if row_count <= 1 do
      {:error, :last_row}
    else
      Multi.new()
      |> Multi.run(:sync_children, fn _repo, _changes ->
        sync_row_to_children(row.block_id, row, :delete)
        {:ok, :done}
      end)
      |> Multi.delete(:row, row)
      |> Repo.transaction()
      |> case do
        {:ok, %{row: row}} -> {:ok, row}
        {:error, :row, changeset, _} -> {:error, changeset}
      end
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
  # Child Sync (Table Inheritance) — Private
  # =============================================================================

  # Syncs a column creation to non-detached inherited instances.
  defp sync_column_to_children(%Block{} = parent_block, %TableColumn{} = column, :create) do
    with_inheriting_instances(parent_block, fn instance_ids ->
      now = TimeHelpers.now()

      col_entries =
        Enum.map(instance_ids, fn instance_id ->
          %{
            name: column.name,
            slug: column.slug,
            type: column.type,
            is_constant: column.is_constant,
            required: column.required,
            position: column.position,
            config: column.config,
            block_id: instance_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableColumn, col_entries)

      Enum.each(instance_ids, fn instance_id ->
        add_cell_to_all_rows(instance_id, column.slug)
      end)
    end)
  end

  # Syncs a column deletion to non-detached inherited instances.
  defp sync_column_to_children(parent_block_id, %TableColumn{} = column, :delete) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      from(c in TableColumn,
        where: c.block_id in ^instance_ids and c.slug == ^column.slug
      )
      |> Repo.delete_all()

      Enum.each(instance_ids, fn instance_id ->
        remove_cell_from_all_rows(instance_id, column.slug)
      end)
    end)
  end

  # Syncs a column update (rename + type change) to non-detached inherited instances.
  defp sync_column_to_children(
         parent_block_id,
         %TableColumn{} = column,
         :update,
         old_slug,
         type_changed?
       ) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      slug_changed? = column.slug != old_slug

      from(c in TableColumn,
        where: c.block_id in ^instance_ids and c.slug == ^old_slug
      )
      |> Repo.update_all(
        set: [
          name: column.name,
          slug: column.slug,
          type: column.type,
          is_constant: column.is_constant,
          required: column.required,
          config: column.config
        ]
      )

      if slug_changed?, do: migrate_cells_key_for_instances(instance_ids, old_slug, column.slug)
      if type_changed?, do: reset_cells_for_instances(instance_ids, column.slug)
    end)
  end

  defp migrate_cells_key_for_instances(instance_ids, old_slug, new_slug) do
    from(r in TableRow, where: r.block_id in ^instance_ids)
    |> update([r],
      set: [
        cells:
          fragment(
            "(? - ?::text) || jsonb_build_object(?::text, ? -> ?::text)",
            r.cells,
            ^old_slug,
            ^new_slug,
            r.cells,
            ^old_slug
          )
      ]
    )
    |> Repo.update_all([])
  end

  defp reset_cells_for_instances(instance_ids, column_slug) do
    from(r in TableRow, where: r.block_id in ^instance_ids)
    |> update([r],
      set: [
        cells: fragment("? || jsonb_build_object(?::text, null::jsonb)", r.cells, ^column_slug)
      ]
    )
    |> Repo.update_all([])
  end

  # Syncs a row creation to non-detached inherited instances.
  defp sync_row_to_children(%Block{} = parent_block, %TableRow{} = row, :create) do
    with_inheriting_instances(parent_block, fn instance_ids ->
      now = TimeHelpers.now()

      row_entries =
        Enum.map(instance_ids, fn instance_id ->
          %{
            name: row.name,
            slug: row.slug,
            position: row.position,
            cells: row.cells,
            block_id: instance_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableRow, row_entries)
    end)
  end

  # Syncs a row deletion to non-detached inherited instances.
  defp sync_row_to_children(parent_block_id, %TableRow{} = row, :delete) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      from(r in TableRow,
        where: r.block_id in ^instance_ids and r.slug == ^row.slug
      )
      |> Repo.delete_all()
    end)
  end

  # Syncs a row rename to non-detached inherited instances.
  # Does NOT overwrite cell values (children may have overridden them).
  defp sync_row_to_children(parent_block_id, %TableRow{} = row, :update, old_slug) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      from(r in TableRow,
        where: r.block_id in ^instance_ids and r.slug == ^old_slug
      )
      |> Repo.update_all(set: [name: row.name, slug: row.slug])
    end)
  end

  # Resolves non-detached instance block IDs and calls the function if any exist.
  # Accepts either a %Block{} struct (avoids extra query) or a block_id integer.
  defp with_inheriting_instances(%Block{} = parent_block, fun) do
    if parent_block.scope == "children" do
      do_with_inheriting_instances(parent_block.id, fun)
    end

    :ok
  end

  defp with_inheriting_instances(parent_block_id, fun) when is_integer(parent_block_id) do
    parent_block = Repo.get(Block, parent_block_id)

    if parent_block && parent_block.scope == "children" do
      do_with_inheriting_instances(parent_block_id, fun)
    end

    :ok
  end

  defp do_with_inheriting_instances(parent_block_id, fun) do
    instance_ids =
      from(b in Block,
        where:
          b.inherited_from_block_id == ^parent_block_id and
            b.detached == false and
            is_nil(b.deleted_at),
        select: b.id
      )
      |> Repo.all()

    if instance_ids != [] do
      fun.(instance_ids)
    end
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

  # Syncs slug from name only if the parent table block has no variable references.
  defp maybe_sync_table_slug(changeset, block_id) do
    name = Ecto.Changeset.get_change(changeset, :name)

    if name do
      current_slug = Ecto.Changeset.get_field(changeset, :slug)
      referenced? = Flows.count_variable_usage(block_id) != %{}

      new_slug =
        NameNormalizer.maybe_regenerate(
          current_slug,
          name,
          referenced?,
          &NameNormalizer.variablify/1
        )

      Ecto.Changeset.put_change(changeset, :slug, new_slug)
    else
      changeset
    end
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

  # Adds a cell key with null value to all rows of a block (single UPDATE)
  defp add_cell_to_all_rows(block_id, column_slug) do
    from(r in TableRow,
      where:
        r.block_id == ^block_id and
          not fragment("? \\? ?::text", r.cells, ^column_slug)
    )
    |> update([r],
      set: [
        cells: fragment("? || jsonb_build_object(?::text, null::jsonb)", r.cells, ^column_slug)
      ]
    )
    |> Repo.update_all([])
  end

  # Removes a cell key from all rows of a block (single UPDATE)
  defp remove_cell_from_all_rows(block_id, column_slug) do
    from(r in TableRow, where: r.block_id == ^block_id)
    |> update([r], set: [cells: fragment("? - ?::text", r.cells, ^column_slug)])
    |> Repo.update_all([])
  end

  # Migrates JSONB cell keys when a column is renamed (single UPDATE)
  defp migrate_cells_key(block_id, old_slug, new_slug) do
    from(r in TableRow, where: r.block_id == ^block_id)
    |> update([r],
      set: [
        cells:
          fragment(
            "(? - ?::text) || jsonb_build_object(?::text, ? -> ?::text)",
            r.cells,
            ^old_slug,
            ^new_slug,
            r.cells,
            ^old_slug
          )
      ]
    )
    |> Repo.update_all([])

    {:ok, :done}
  end

  # Resets cell values to null for a specific column across all rows (single UPDATE)
  defp reset_cells_for_column(block_id, column_slug) do
    from(r in TableRow, where: r.block_id == ^block_id)
    |> update([r],
      set: [
        cells: fragment("? || jsonb_build_object(?::text, null::jsonb)", r.cells, ^column_slug)
      ]
    )
    |> Repo.update_all([])

    {:ok, :done}
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a table column for import. Raw insert — no auto-slug dedup,
  no auto-position, no cell propagation, no child sync.
  Returns `{:ok, column}` or `{:error, changeset}`.
  """
  def import_column(block_id, attrs) do
    %TableColumn{block_id: block_id}
    |> TableColumn.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a table row for import. Raw insert — no auto-position, no slug dedup.
  Returns `{:ok, row}` or `{:error, changeset}`.
  """
  def import_row(block_id, attrs) do
    %TableRow{block_id: block_id}
    |> TableRow.create_changeset(attrs)
    |> Repo.insert()
  end
end

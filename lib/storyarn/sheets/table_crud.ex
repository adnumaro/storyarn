defmodule Storyarn.Sheets.TableCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.FormulaEngine
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.TreeOperations
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.FormulaBindingRewriter
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  # =============================================================================
  # Column Operations
  # =============================================================================

  @doc "Lists all columns for a block, ordered by position."
  def list_columns(block_id) do
    Repo.all(from(c in TableColumn, where: c.block_id == ^block_id, order_by: [asc: c.position]))
  end

  @doc "Gets a single column by ID, scoped to a block. Raises if not found."
  def get_column!(block_id, column_id) do
    Repo.one!(from(c in TableColumn, where: c.id == ^column_id and c.block_id == ^block_id))
  end

  @doc "Gets a single column by ID, scoped to a block. Returns nil if not found."
  def get_column(block_id, column_id) do
    Repo.one(from(c in TableColumn, where: c.id == ^column_id and c.block_id == ^block_id))
  end

  @doc """
  Creates a new column on a table block.
  Auto-generates slug, auto-assigns position, and adds empty cell to all existing rows.
  """
  def create_column(%Block{type: "table"} = block, attrs) do
    attrs = maybe_force_formula_constant(attrs)

    Repo.transaction(fn ->
      scope = lock_table_scope!(block)
      create_column_in_scope!(scope, attrs)
    end)
  end

  defp create_column_in_scope!(scope, attrs) do
    block_id = scope.block.id
    position = attrs[:position] || attrs["position"] || next_column_position(block_id)
    existing_slugs = Enum.map(parent_columns(scope), & &1.slug)

    changeset =
      TableColumn.create_changeset(
        %TableColumn{block_id: block_id},
        Map.put(attrs, :position, position)
      )

    slug = Ecto.Changeset.get_field(changeset, :slug)
    unique_slug = ensure_unique_slug(slug, existing_slugs)

    changeset =
      if unique_slug == slug,
        do: changeset,
        else: Ecto.Changeset.put_change(changeset, :slug, unique_slug)

    case Repo.insert(changeset) do
      {:ok, column} ->
        add_cell_to_all_rows(block_id, column.slug)
        sync_column_to_children(scope.block, column, :create)
        column

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  @doc """
  Updates a column. Handles rename (slug migration) and type change (cell reset).
  """
  def update_column(%TableColumn{} = column, attrs) do
    attrs = maybe_force_formula_constant(attrs)

    Repo.transaction(fn ->
      {scope, persisted_column} = lock_table_scope_from_column!(column)
      update_column_in_scope!(scope, persisted_column, attrs)
    end)
  end

  defp update_column_in_scope!(scope, column, attrs) do
    changeset =
      column
      |> TableColumn.update_changeset(attrs)
      |> maybe_sync_table_slug(column.block_id)

    new_slug = Ecto.Changeset.get_field(changeset, :slug)
    new_type = Ecto.Changeset.get_field(changeset, :type)
    old_slug = column.slug
    slug_changed? = new_slug != old_slug
    type_changed? = new_type != column.type

    changeset =
      if slug_changed? do
        existing_slugs =
          scope
          |> parent_columns()
          |> Enum.reject(&(&1.id == column.id))
          |> Enum.map(& &1.slug)

        Ecto.Changeset.put_change(
          changeset,
          :slug,
          ensure_unique_slug(new_slug, existing_slugs)
        )
      else
        changeset
      end

    final_new_slug = Ecto.Changeset.get_field(changeset, :slug)

    case Repo.update(changeset) do
      {:ok, updated_column} ->
        if slug_changed?,
          do: migrate_cells_key(column.block_id, old_slug, final_new_slug)

        if type_changed?,
          do: reset_cells_for_column(column.block_id, final_new_slug)

        sync_column_to_children(
          scope.block,
          updated_column,
          :update,
          old_slug,
          type_changed?
        )

        updated_column

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  @doc """
  Deletes a column. Prevents deletion of the last column.
  Removes the column's cell key from all rows.
  """
  def delete_column(%TableColumn{} = column) do
    Repo.transaction(fn ->
      {scope, persisted_column} = lock_table_scope_from_column!(column)

      if length(parent_columns(scope)) <= 1 do
        Repo.rollback(:last_column)
      end

      sync_column_to_children(
        scope.block,
        persisted_column,
        :delete
      )

      case Repo.delete(persisted_column) do
        {:ok, deleted} ->
          remove_cell_from_all_rows(scope.block.id, persisted_column.slug)
          deleted

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Recreates a column from a snapshot map (for undo/redo).
  Also restores cell values for the column across all rows.
  """
  def create_column_from_snapshot(block_id, snapshot, cell_values) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      validate_snapshot_owner!(snapshot, block_id)

      snapshot_id = valid_snapshot_id!(snapshot)

      changeset =
        %TableColumn{id: snapshot_id, block_id: block_id}
        |> TableColumn.create_changeset(%{
          name: snapshot.name,
          type: snapshot.type,
          position: snapshot.position,
          is_constant: Map.get(snapshot, :is_constant, false),
          required: Map.get(snapshot, :required, false),
          config: Map.get(snapshot, :config, %{})
        })
        |> Ecto.Changeset.force_change(:slug, snapshot.slug)

      case Repo.insert(changeset) do
        {:ok, column} ->
          restore_column_cell_values!(scope, column.slug, cell_values)
          sync_column_to_children(scope.block, column, :create)
          column

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp restore_column_cell_values!(scope, column_slug, cell_values) when is_list(cell_values) do
    parent_rows_by_id = Map.new(parent_rows(scope), &{&1.id, &1})
    row_ids = Enum.map(cell_values, &elem(&1, 0))

    if length(row_ids) != length(Enum.uniq(row_ids)) or
         Enum.any?(row_ids, &(not Map.has_key?(parent_rows_by_id, &1))) do
      Repo.rollback(:invalid_table_snapshot)
    end

    Enum.each(cell_values, fn {row_id, value} ->
      row = Map.fetch!(parent_rows_by_id, row_id)
      new_cells = Map.put(row.cells || %{}, column_slug, value)

      case row |> TableRow.cells_changeset(%{cells: new_cells}) |> Repo.update() do
        {:ok, _updated} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp restore_column_cell_values!(_scope, _column_slug, _cell_values) do
    Repo.rollback(:invalid_table_snapshot)
  end

  defp validate_snapshot_owner!(snapshot, block_id) do
    case Map.get(snapshot, :block_id) do
      nil -> :ok
      ^block_id -> :ok
      _other -> Repo.rollback(:invalid_table_snapshot)
    end
  end

  defp valid_snapshot_id!(snapshot) do
    case Map.get(snapshot, :id) do
      id when is_integer(id) and id > 0 -> id
      _invalid -> Repo.rollback(:invalid_table_snapshot)
    end
  end

  @doc "Reorders columns by updating their positions."
  def reorder_columns(block_id, column_ids) when is_list(column_ids) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      normalized_ids = normalize_exact_child_ids!(column_ids, parent_columns(scope), :column)
      pairs = Enum.with_index(normalized_ids)

      TreeOperations.batch_set_positions("table_columns", pairs, scope: {"block_id", block_id})
      sync_column_positions_to_children(scope, normalized_ids)

      list_columns(block_id)
    end)
  end

  def reorder_columns(_block_id, column_ids), do: {:error, {:invalid_table_column_reorder, column_ids}}

  @doc """
  Batch loads table data (columns + rows) for multiple blocks at once.
  Returns a map of block_id => %{columns: [...], rows: [...]}.
  """
  def batch_load_table_data(block_ids) when is_list(block_ids) do
    columns =
      Repo.all(from(c in TableColumn, where: c.block_id in ^block_ids, order_by: [asc: c.block_id, asc: c.position]))

    rows = Repo.all(from(r in TableRow, where: r.block_id in ^block_ids, order_by: [asc: r.block_id, asc: r.position]))

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
    Repo.all(from(r in TableRow, where: r.block_id == ^block_id, order_by: [asc: r.position]))
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
  def create_row(%Block{type: "table"} = block, attrs) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block)
      block_id = scope.block.id
      position = attrs[:position] || attrs["position"] || next_row_position(block_id)
      existing_slugs = Enum.map(parent_rows(scope), & &1.slug)
      column_slugs = Enum.map(parent_columns(scope), & &1.slug)
      default_cells = Map.new(column_slugs, &{&1, nil})
      supplied_cells = attrs[:cells] || attrs["cells"] || %{}
      validate_cell_keys!(scope, supplied_cells, enforce_required: false)
      cells = Map.merge(default_cells, supplied_cells)

      changeset =
        TableRow.create_changeset(
          %TableRow{block_id: block_id},
          attrs |> Map.put(:position, position) |> Map.put(:cells, cells)
        )

      slug = Ecto.Changeset.get_field(changeset, :slug)
      unique_slug = ensure_unique_slug(slug, existing_slugs)

      changeset =
        if unique_slug == slug,
          do: changeset,
          else: Ecto.Changeset.put_change(changeset, :slug, unique_slug)

      case Repo.insert(changeset) do
        {:ok, row} ->
          sync_row_to_children(scope.block, row, :create)
          row

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc "Updates a row (rename → re-slug)."
  def update_row(%TableRow{} = row, attrs) do
    Repo.transaction(fn ->
      {scope, persisted_row} = lock_table_scope_from_row!(row)
      old_slug = persisted_row.slug

      changeset =
        persisted_row
        |> TableRow.update_changeset(attrs)
        |> maybe_sync_table_slug(persisted_row.block_id)

      new_slug = Ecto.Changeset.get_field(changeset, :slug)

      changeset =
        if new_slug == persisted_row.slug do
          changeset
        else
          existing_slugs =
            scope
            |> parent_rows()
            |> Enum.reject(&(&1.id == persisted_row.id))
            |> Enum.map(& &1.slug)

          Ecto.Changeset.put_change(
            changeset,
            :slug,
            ensure_unique_slug(new_slug, existing_slugs)
          )
        end

      case Repo.update(changeset) do
        {:ok, updated_row} ->
          sync_row_to_children(scope.block, updated_row, :update, old_slug)
          updated_row

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Recreates a row from a snapshot map (for undo/redo).
  """
  def create_row_from_snapshot(block_id, snapshot, cells) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      validate_snapshot_owner!(snapshot, block_id)
      validate_cell_keys!(scope, cells, enforce_required: false)

      changeset =
        %TableRow{id: valid_snapshot_id!(snapshot), block_id: block_id}
        |> TableRow.create_changeset(%{
          name: snapshot.name,
          position: snapshot.position,
          cells: cells
        })
        |> Ecto.Changeset.force_change(:slug, snapshot.slug)

      case Repo.insert(changeset) do
        {:ok, row} ->
          sync_row_to_children(scope.block, row, :create)
          row

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc "Deletes a row. Prevents deletion of the last row."
  def delete_row(%TableRow{} = row) do
    Repo.transaction(fn ->
      {scope, persisted_row} = lock_table_scope_from_row!(row)

      if length(parent_rows(scope)) <= 1 do
        Repo.rollback(:last_row)
      end

      sync_row_to_children(scope.block, persisted_row, :delete)

      case Repo.delete(persisted_row) do
        {:ok, deleted} -> deleted
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Reorders rows by updating their positions."
  def reorder_rows(block_id, row_ids) when is_list(row_ids) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      normalized_ids = normalize_exact_child_ids!(row_ids, parent_rows(scope), :row)
      pairs = Enum.with_index(normalized_ids)

      TreeOperations.batch_set_positions("table_rows", pairs, scope: {"block_id", block_id})
      sync_row_positions_to_children(scope, normalized_ids)

      list_rows(block_id)
    end)
  end

  def reorder_rows(_block_id, row_ids), do: {:error, {:invalid_table_row_reorder, row_ids}}

  @doc "Updates a single cell value in a row."
  def update_cell(%TableRow{} = row, column_slug, value) do
    update_cells(row, %{column_slug => value})
  end

  @doc "Batch updates multiple cells in a row."
  def update_cells(%TableRow{} = row, cells_map) when is_map(cells_map) do
    Repo.transaction(fn ->
      {scope, persisted_row} = lock_table_scope_from_row!(row)
      validate_cell_keys!(scope, cells_map, enforce_required: true)
      new_cells = Map.merge(persisted_row.cells || %{}, cells_map)

      case persisted_row
           |> TableRow.cells_changeset(%{cells: new_cells})
           |> Repo.update() do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_cells(_row, _cells_map), do: {:error, :invalid_table_cells}

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
      Repo.delete_all(from(c in TableColumn, where: c.block_id in ^instance_ids and c.slug == ^column.slug))

      Enum.each(instance_ids, fn instance_id ->
        remove_cell_from_all_rows(instance_id, column.slug)
      end)
    end)
  end

  # Syncs a column update (rename + type change) to non-detached inherited instances.
  defp sync_column_to_children(parent_block_id, %TableColumn{} = column, :update, old_slug, type_changed?) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      slug_changed? = column.slug != old_slug

      Repo.update_all(from(c in TableColumn, where: c.block_id in ^instance_ids and c.slug == ^old_slug),
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
  # Rewrites formula bindings if the row contains cross-sheet variable references.
  defp sync_row_to_children(%Block{} = parent_block, %TableRow{} = row, :create) do
    if FormulaBindingRewriter.has_formula_variable_bindings?(row.cells) do
      sync_row_to_children_with_rewrite(parent_block, row)
    else
      sync_row_to_children_plain(parent_block, row)
    end
  end

  # Syncs a row deletion to non-detached inherited instances.
  defp sync_row_to_children(parent_block_id, %TableRow{} = row, :delete) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      Repo.delete_all(from(r in TableRow, where: r.block_id in ^instance_ids and r.slug == ^row.slug))
    end)
  end

  # Syncs a row rename to non-detached inherited instances.
  # Does NOT overwrite cell values (children may have overridden them).
  defp sync_row_to_children(parent_block_id, %TableRow{} = row, :update, old_slug) do
    with_inheriting_instances(parent_block_id, fn instance_ids ->
      Repo.update_all(from(r in TableRow, where: r.block_id in ^instance_ids and r.slug == ^old_slug),
        set: [name: row.name, slug: row.slug]
      )
    end)
  end

  defp sync_row_to_children_plain(parent_block, row) do
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

  # Creates row entries with per-instance formula binding rewriting.
  defp sync_row_to_children_with_rewrite(%Block{} = parent_block, %TableRow{} = row) do
    if parent_block.scope != "children", do: throw(:ok)

    # Load instances with their sheet_ids
    instances =
      Repo.all(
        from(instance in Block,
          join: instance_sheet in Sheet,
          on: instance_sheet.id == instance.sheet_id,
          join: source_sheet in Sheet,
          on: source_sheet.id == ^parent_block.sheet_id,
          where:
            instance.inherited_from_block_id == ^parent_block.id and
              instance.detached == false and
              instance.type == "table" and
              is_nil(source_sheet.deleted_at) and
              instance_sheet.project_id == source_sheet.project_id and
              is_nil(instance.deleted_at),
          order_by: [asc: instance.id],
          select: %{id: instance.id, sheet_id: instance.sheet_id}
        )
      )

    if instances == [] do
      :ok
    else
      parent_shortcut =
        Repo.one(
          from(s in Sheet, join: b in Block, on: b.sheet_id == s.id, where: b.id == ^parent_block.id, select: s.shortcut)
        )

      child_sheet_ids = instances |> Enum.map(& &1.sheet_id) |> Enum.uniq()

      child_shortcuts =
        from(s in Sheet, where: s.id in ^child_sheet_ids, select: {s.id, s.shortcut})
        |> Repo.all()
        |> Map.new()

      mappings =
        Map.new(child_sheet_ids, fn sheet_id ->
          {sheet_id, FormulaBindingRewriter.build_var_name_mapping(parent_block.sheet_id, sheet_id)}
        end)

      now = TimeHelpers.now()

      row_entries =
        Enum.map(instances, fn instance ->
          child_shortcut = Map.get(child_shortcuts, instance.sheet_id)
          mapping = Map.get(mappings, instance.sheet_id, %{})

          cells =
            FormulaBindingRewriter.rewrite_cells(
              row.cells,
              parent_shortcut,
              child_shortcut,
              mapping
            )

          %{
            name: row.name,
            slug: row.slug,
            position: row.position,
            cells: cells,
            block_id: instance.id,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableRow, row_entries)
    end

    :ok
  catch
    :ok -> :ok
  end

  # Resolves non-detached instance block IDs and calls the function if any exist.
  # Accepts either a %Block{} struct (avoids extra query) or a block_id integer.
  defp with_inheriting_instances(%Block{} = parent_block, fun) do
    if managed_table_source?(parent_block) do
      do_with_inheriting_instances(parent_block.id, fun)
    end

    :ok
  end

  defp with_inheriting_instances(parent_block_id, fun) when is_integer(parent_block_id) do
    parent_block = Repo.get(Block, parent_block_id)

    if parent_block && managed_table_source?(parent_block) do
      do_with_inheriting_instances(parent_block_id, fun)
    end

    :ok
  end

  defp do_with_inheriting_instances(parent_block_id, fun) do
    instance_ids =
      Repo.all(
        from(instance in Block,
          join: instance_sheet in Sheet,
          on: instance_sheet.id == instance.sheet_id,
          join: source in Block,
          on: source.id == ^parent_block_id,
          join: source_sheet in Sheet,
          on: source_sheet.id == source.sheet_id,
          where:
            instance.inherited_from_block_id == ^parent_block_id and
              instance.detached == false and
              instance.type == "table" and
              is_nil(source.deleted_at) and
              is_nil(source_sheet.deleted_at) and
              instance_sheet.project_id == source_sheet.project_id and
              source.scope == "children" and is_nil(instance.deleted_at),
          order_by: [asc: instance.id],
          select: instance.id
        )
      )

    if instance_ids != [] do
      fun.(instance_ids)
    end
  end

  defp managed_table_source?(%Block{scope: "children"}), do: true

  defp managed_table_source?(_block), do: false

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp lock_table_scope!(%Block{} = block) do
    lock_table_scope!(block.id, block.sheet_id)
  end

  defp lock_table_scope!(block_id), do: lock_table_scope!(block_id, nil)

  defp lock_table_scope!(block_id, expected_sheet_id) do
    {project_id, sheet_id} = fetch_table_owner!(block_id)

    if expected_sheet_id && expected_sheet_id != sheet_id do
      Repo.rollback(:inactive_table)
    end

    lock_active_project!(project_id)
    instance_metadata = active_table_instance_metadata(block_id, project_id)
    block_ids = [block_id | Enum.map(instance_metadata, &elem(&1, 0))] |> Enum.uniq() |> Enum.sort()
    instance_sheet_ids = instance_metadata |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    lock_table_source_and_target_sheets!(project_id, sheet_id, instance_sheet_ids)
    blocks = lock_active_table_blocks!(block_id, block_ids)
    columns = lock_table_columns!(block_ids)
    rows = lock_table_rows!(block_ids)

    block =
      Enum.find(blocks, &(&1.id == block_id and &1.sheet_id == sheet_id)) ||
        Repo.rollback(:inactive_table)

    %{
      block: block,
      instance_ids: Enum.reject(block_ids, &(&1 == block_id)),
      columns: columns,
      rows: rows
    }
  end

  defp lock_table_scope_from_column!(%TableColumn{} = column) do
    block_id =
      Repo.one(
        from(persisted in TableColumn,
          where: persisted.id == ^column.id,
          select: persisted.block_id
        )
      ) || Repo.rollback(:column_not_found)

    if block_id != column.block_id do
      Repo.rollback(:column_not_found)
    end

    scope = lock_table_scope!(block_id)

    persisted =
      Enum.find(
        scope.columns,
        &(&1.id == column.id and &1.block_id == block_id)
      ) || Repo.rollback(:column_not_found)

    {scope, persisted}
  end

  defp lock_table_scope_from_row!(%TableRow{} = row) do
    block_id =
      Repo.one(
        from(persisted in TableRow,
          where: persisted.id == ^row.id,
          select: persisted.block_id
        )
      ) || Repo.rollback(:row_not_found)

    if block_id != row.block_id do
      Repo.rollback(:row_not_found)
    end

    scope = lock_table_scope!(block_id)

    persisted =
      Enum.find(
        scope.rows,
        &(&1.id == row.id and &1.block_id == block_id)
      ) || Repo.rollback(:row_not_found)

    {scope, persisted}
  end

  defp fetch_table_owner!(block_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id,
        select: {sheet.project_id, sheet.id}
      )
    ) || Repo.rollback(:inactive_table)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp active_table_instance_metadata(block_id, project_id) do
    Repo.all(
      from(instance in Block,
        join: owner_sheet in Sheet,
        on: owner_sheet.id == instance.sheet_id,
        join: source in Block,
        on: source.id == ^block_id,
        where:
          is_nil(source.deleted_at) and
            instance.inherited_from_block_id == source.id and
            instance.detached == false and
            instance.type == "table" and
            owner_sheet.project_id == ^project_id and
            source.scope == "children" and is_nil(instance.deleted_at),
        order_by: [asc: instance.id],
        select: {instance.id, instance.sheet_id}
      )
    )
  end

  defp lock_table_source_and_target_sheets!(project_id, source_sheet_id, target_sheet_ids) do
    requested_ids =
      [source_sheet_id | target_sheet_ids]
      |> Enum.uniq()
      |> Enum.sort()

    locked_sheets =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.id in ^requested_ids and
              sheet.project_id == ^project_id,
          order_by: [asc: sheet.id],
          lock: "FOR UPDATE",
          select: {sheet.id, sheet.deleted_at}
        )
      )

    locked_ids = Enum.map(locked_sheets, &elem(&1, 0))

    source_active? =
      Enum.any?(locked_sheets, fn {id, deleted_at} ->
        id == source_sheet_id and is_nil(deleted_at)
      end)

    if locked_ids != requested_ids or !source_active?, do: Repo.rollback(:inactive_table)
  end

  defp lock_active_table_blocks!(source_block_id, block_ids) do
    blocks =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^block_ids and
              block.type == "table",
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    source = Enum.find(blocks, &(&1.id == source_block_id))

    valid? =
      ((Enum.map(blocks, & &1.id) == block_ids and
          source) && is_nil(source.deleted_at)) and
        Enum.all?(blocks, fn
          %{id: ^source_block_id} ->
            true

          instance ->
            instance.inherited_from_block_id == source_block_id and
              instance.detached == false and is_nil(instance.deleted_at)
        end)

    if valid? do
      blocks
    else
      Repo.rollback(:inactive_table)
    end
  end

  defp lock_table_columns!(block_ids) do
    Repo.all(
      from(column in TableColumn,
        where: column.block_id in ^block_ids,
        order_by: [asc: column.block_id, asc: column.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_table_rows!(block_ids) do
    Repo.all(
      from(row in TableRow,
        where: row.block_id in ^block_ids,
        order_by: [asc: row.block_id, asc: row.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp parent_columns(scope), do: Enum.filter(scope.columns, &(&1.block_id == scope.block.id))

  defp parent_rows(scope), do: Enum.filter(scope.rows, &(&1.block_id == scope.block.id))

  defp normalize_exact_child_ids!(requested_ids, persisted_children, type) do
    persisted_ids = persisted_children |> Enum.map(& &1.id) |> Enum.sort()

    valid? =
      Enum.all?(requested_ids, &(is_integer(&1) and &1 > 0)) and
        length(requested_ids) == length(Enum.uniq(requested_ids)) and
        Enum.sort(requested_ids) == persisted_ids

    if valid? do
      requested_ids
    else
      reason =
        case type do
          :column -> {:invalid_table_column_reorder, requested_ids}
          :row -> {:invalid_table_row_reorder, requested_ids}
        end

      Repo.rollback(reason)
    end
  end

  defp sync_column_positions_to_children(%{instance_ids: []}, _ordered_ids), do: :ok

  defp sync_column_positions_to_children(scope, ordered_ids) do
    columns_by_id = Map.new(parent_columns(scope), &{&1.id, &1})

    ordered_ids
    |> Enum.with_index()
    |> Enum.each(fn {column_id, position} ->
      column = Map.fetch!(columns_by_id, column_id)

      Repo.update_all(
        from(child_column in TableColumn,
          where:
            child_column.block_id in ^scope.instance_ids and
              child_column.slug == ^column.slug
        ),
        set: [position: position]
      )
    end)
  end

  defp sync_row_positions_to_children(%{instance_ids: []}, _ordered_ids), do: :ok

  defp sync_row_positions_to_children(scope, ordered_ids) do
    rows_by_id = Map.new(parent_rows(scope), &{&1.id, &1})

    ordered_ids
    |> Enum.with_index()
    |> Enum.each(fn {row_id, position} ->
      row = Map.fetch!(rows_by_id, row_id)

      Repo.update_all(
        from(child_row in TableRow,
          where:
            child_row.block_id in ^scope.instance_ids and
              child_row.slug == ^row.slug
        ),
        set: [position: position]
      )
    end)
  end

  defp validate_cell_keys!(scope, cells_map, opts) when is_map(cells_map) do
    columns_by_slug = Map.new(parent_columns(scope), &{&1.slug, &1})
    enforce_required? = Keyword.fetch!(opts, :enforce_required)

    Enum.each(cells_map, fn {slug, value} ->
      column = Map.get(columns_by_slug, slug)
      validate_table_cell!(column, slug, value, columns_by_slug, enforce_required?)
    end)
  end

  defp validate_cell_keys!(_scope, _cells_map, _opts), do: Repo.rollback(:invalid_table_cells)

  defp validate_table_cell!(nil, slug, _value, _columns_by_slug, _enforce_required?) do
    Repo.rollback({:unknown_table_column, slug})
  end

  defp validate_table_cell!(%TableColumn{type: "formula"} = column, _slug, value, columns_by_slug, _enforce_required?) do
    validate_formula_cell!(value, column, columns_by_slug)
  end

  defp validate_table_cell!(%TableColumn{required: true}, slug, value, _columns_by_slug, true) do
    if empty_cell_value?(value),
      do: Repo.rollback({:required_table_column, slug})
  end

  defp validate_table_cell!(%TableColumn{}, _slug, _value, _columns_by_slug, _enforce_required?), do: :ok

  defp validate_formula_cell!(nil, _column, _columns_by_slug), do: :ok

  defp validate_formula_cell!(%{"expression" => expression, "bindings" => bindings} = value, column, columns_by_slug)
       when is_binary(expression) and is_map(bindings) do
    if value |> Map.keys() |> Enum.sort() != ["bindings", "expression"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end

    allowed_symbols =
      case FormulaEngine.parse(expression) do
        {:ok, ast} -> ast |> FormulaEngine.extract_symbols() |> MapSet.new()
        {:error, _reason} -> MapSet.new()
      end

    Enum.each(bindings, fn {symbol, binding} ->
      if !is_binary(symbol) or !MapSet.member?(allowed_symbols, symbol) do
        Repo.rollback({:invalid_formula_cell, column.slug})
      end

      validate_formula_binding!(binding, column, columns_by_slug)
    end)
  end

  defp validate_formula_cell!(_value, column, _columns_by_slug) do
    Repo.rollback({:invalid_formula_cell, column.slug})
  end

  defp validate_formula_binding!(
         %{"type" => "same_row", "column_slug" => referenced_slug} = binding,
         column,
         columns_by_slug
       )
       when is_binary(referenced_slug) and referenced_slug != "" do
    referenced_column = Map.get(columns_by_slug, referenced_slug)

    if binding |> Map.keys() |> Enum.sort() != ["column_slug", "type"] or
         referenced_slug == column.slug or
         is_nil(referenced_column) or
         referenced_column.type not in ["number", "formula"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end
  end

  defp validate_formula_binding!(%{"type" => "variable", "ref" => reference} = binding, column, _columns_by_slug)
       when is_binary(reference) and reference != "" do
    if binding |> Map.keys() |> Enum.sort() != ["ref", "type"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end
  end

  defp validate_formula_binding!(_binding, column, _columns_by_slug) do
    Repo.rollback({:invalid_formula_cell, column.slug})
  end

  defp empty_cell_value?(nil), do: true
  defp empty_cell_value?(""), do: true
  defp empty_cell_value?([]), do: true
  defp empty_cell_value?(_value), do: false

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
    Repo.transaction(fn ->
      _scope = lock_table_scope!(block_id)

      case %TableColumn{block_id: block_id}
           |> TableColumn.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, column} -> column
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates a table row for import. Raw insert — no auto-position, no slug dedup.
  Returns `{:ok, row}` or `{:error, changeset}`.
  """
  def import_row(block_id, attrs) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      cells = attrs[:cells] || attrs["cells"] || %{}
      validate_cell_keys!(scope, cells, enforce_required: false)

      case %TableRow{block_id: block_id}
           |> TableRow.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, row} -> row
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_force_formula_constant(attrs) do
    type = attrs[:type] || attrs["type"]

    if type == "formula" do
      # Detect key style (atom or string) and use the same
      if Map.has_key?(attrs, :type) do
        Map.put(attrs, :is_constant, true)
      else
        Map.put(attrs, "is_constant", true)
      end
    else
      attrs
    end
  end
end

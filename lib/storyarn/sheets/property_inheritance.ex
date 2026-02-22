defmodule Storyarn.Sheets.PropertyInheritance do
  @moduledoc """
  Core logic for property (block) inheritance between parent and child sheets.

  When a block has `scope: "children"`, it cascades to all descendant sheets.
  Each child gets its own instance block with `inherited_from_block_id` pointing
  back to the source definition. Values are always local to each child.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}

  alias Storyarn.Sheets.{
    Block,
    BlockCrud,
    EntityReference,
    Sheet,
    SheetQueries,
    TableColumn,
    TableRow
  }

  # =============================================================================
  # Resolution
  # =============================================================================

  @doc """
  Returns inherited blocks for a sheet, grouped by source sheet.

  Walks the ancestor chain and collects all blocks with `scope: "children"`,
  filtering out blocks hidden by intermediate ancestors.

  Returns `[%{source_sheet: sheet, blocks: [block, ...]}]` ordered from
  nearest ancestor to farthest.
  """
  @spec resolve_inherited_blocks(integer()) :: [%{source_sheet: Sheet.t(), blocks: [Block.t()]}]
  def resolve_inherited_blocks(sheet_id) do
    sheet = Repo.get!(Sheet, sheet_id)
    ancestors = build_ancestor_list(sheet)

    if ancestors == [] do
      []
    else
      # Collect hidden block IDs from intermediate sheets (the current sheet and all ancestors except root)
      all_sheets = [sheet | ancestors]
      hidden_block_ids = collect_hidden_block_ids(all_sheets)

      ancestors
      |> Enum.map(&ancestor_to_block_group(&1, hidden_block_ids))
      |> Enum.reject(fn group -> group.blocks == [] end)
    end
  end

  @doc """
  Creates inherited block instances on child sheets for a parent block.

  For each child sheet ID, creates a new block with:
  - Same `type`, `config`, `required` as parent block
  - Default `value` for the type
  - `inherited_from_block_id` pointing to parent block
  - `scope: "self"` (instances don't cascade by default)
  """
  @spec create_inherited_instances(Block.t(), [integer()]) :: {:ok, integer()}
  def create_inherited_instances(%Block{} = parent_block, child_sheet_ids)
      when is_list(child_sheet_ids) do
    if child_sheet_ids == [] do
      {:ok, 0}
    else
      now = TimeHelpers.now()

      # Batch check which sheets already have instances for this parent block
      existing_sheet_ids =
        from(b in Block,
          where:
            b.inherited_from_block_id == ^parent_block.id and
              b.sheet_id in ^child_sheet_ids and
              is_nil(b.deleted_at),
          select: b.sheet_id
        )
        |> Repo.all()
        |> MapSet.new()

      sheets_to_create =
        child_sheet_ids
        |> Enum.reject(&MapSet.member?(existing_sheet_ids, &1))

      entries =
        Enum.map(sheets_to_create, fn sheet_id ->
          position = next_block_position(sheet_id)
          variable_name = derive_unique_variable_name(parent_block, sheet_id)

          %{
            type: parent_block.type,
            config: parent_block.config,
            value: Block.default_value(parent_block.type),
            position: position,
            is_constant: parent_block.is_constant,
            variable_name: variable_name,
            scope: "self",
            inherited_from_block_id: parent_block.id,
            detached: false,
            required: parent_block.required,
            column_group_id: nil,
            column_index: 0,
            sheet_id: sheet_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      if entries == [] do
        {:ok, 0}
      else
        {count, _} = Repo.insert_all(Block, entries)
        copy_table_structure_to_instances(parent_block)
        {:ok, count}
      end
    end
  end

  @doc """
  Bulk creates inherited instances for selected existing descendants.
  """
  @spec propagate_to_descendants(Block.t(), [integer()]) :: {:ok, integer()}
  def propagate_to_descendants(%Block{} = parent_block, selected_sheet_ids) do
    # Validate that all selected IDs are actual descendants
    valid_descendant_ids =
      MapSet.new(get_descendant_sheet_ids(parent_block.sheet_id))

    validated_ids =
      Enum.filter(selected_sheet_ids, &MapSet.member?(valid_descendant_ids, &1))

    create_inherited_instances(parent_block, validated_ids)
  end

  @doc """
  Syncs definition changes from a parent block to all non-detached instances.

  When parent block config/type changes, updates all instances that haven't been detached.
  If type changed, clears the value (incompatible data).
  """
  @spec sync_definition_change(Block.t()) :: {:ok, integer()}
  def sync_definition_change(%Block{} = parent_block) do
    Repo.transaction(fn ->
      instances = list_non_detached_instances(parent_block.id)

      if instances == [] do
        0
      else
        do_sync_definition(parent_block, instances)
      end
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Detaches an inherited block, making it a local copy.
  Keeps `inherited_from_block_id` for provenance (allows re-attach).
  """
  @spec detach_block(Block.t()) :: {:ok, Block.t()} | {:error, Ecto.Changeset.t()}
  def detach_block(%Block{} = block) do
    block
    |> Ecto.Changeset.change(%{detached: true})
    |> Repo.update()
  end

  @doc """
  Re-attaches a previously detached block, syncing it with the parent definition.
  """
  @spec reattach_block(Block.t()) :: {:ok, Block.t()} | {:error, :source_not_found}
  def reattach_block(%Block{inherited_from_block_id: nil}), do: {:error, :source_not_found}

  def reattach_block(%Block{} = block) do
    case Repo.get(Block, block.inherited_from_block_id) do
      nil ->
        {:error, :source_not_found}

      source ->
        updates = build_reattach_updates(source)

        block
        |> Ecto.Changeset.change(updates)
        |> BlockCrud.ensure_unique_variable_name_public(block.sheet_id, block.id)
        |> Repo.update()
        |> maybe_reset_table_structure(source.id)
    end
  end

  @doc """
  Adds an ancestor block ID to the sheet's hidden list, stopping it from cascading
  to this sheet's children.
  """
  @spec hide_for_children(Sheet.t(), integer()) :: {:ok, Sheet.t()}
  def hide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    current = sheet.hidden_inherited_block_ids || []

    if ancestor_block_id in current do
      {:ok, sheet}
    else
      sheet
      |> Ecto.Changeset.change(%{hidden_inherited_block_ids: [ancestor_block_id | current]})
      |> Repo.update()
    end
  end

  @doc """
  Removes an ancestor block ID from the sheet's hidden list.
  """
  @spec unhide_for_children(Sheet.t(), integer()) :: {:ok, Sheet.t()}
  def unhide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    current = sheet.hidden_inherited_block_ids || []
    updated = List.delete(current, ancestor_block_id)

    if updated == current do
      {:ok, sheet}
    else
      sheet
      |> Ecto.Changeset.change(%{hidden_inherited_block_ids: updated})
      |> Repo.update()
    end
  end

  @doc """
  Soft-deletes all inherited instances when a parent block with `scope: "children"` is deleted.
  """
  @spec delete_inherited_instances(Block.t()) :: {:ok, integer()}
  def delete_inherited_instances(%Block{} = parent_block) do
    Repo.transaction(fn ->
      now = TimeHelpers.now()

      # Get instance IDs before soft-deleting
      instance_ids =
        from(b in Block,
          where:
            b.inherited_from_block_id == ^parent_block.id and
              is_nil(b.deleted_at),
          select: b.id
        )
        |> Repo.all()

      if instance_ids != [] do
        cleanup_instance_references(instance_ids)
        cleanup_hidden_block_ids(parent_block.id)
      end

      # Soft-delete all instances
      {count, _} =
        from(b in Block,
          where:
            b.inherited_from_block_id == ^parent_block.id and
              is_nil(b.deleted_at)
        )
        |> Repo.update_all(set: [deleted_at: now])

      count
    end)
  end

  @doc """
  Restores all inherited instances when a parent block is restored.
  """
  @spec restore_inherited_instances(Block.t()) :: {:ok, integer()}
  def restore_inherited_instances(%Block{} = parent_block) do
    {count, _} =
      from(b in Block,
        where:
          b.inherited_from_block_id == ^parent_block.id and
            not is_nil(b.deleted_at)
      )
      |> Repo.update_all(set: [deleted_at: nil])

    {:ok, count}
  end

  @doc """
  Returns the sheet that owns the source block for an inherited block.
  """
  @spec get_source_sheet(Block.t()) :: Sheet.t() | nil
  def get_source_sheet(%Block{inherited_from_block_id: nil}), do: nil

  def get_source_sheet(%Block{inherited_from_block_id: source_id}) do
    case Repo.get(Block, source_id) do
      nil -> nil
      source_block -> Repo.get(Sheet, source_block.sheet_id)
    end
  end

  @doc """
  Returns all descendant sheet IDs for a given sheet (non-deleted).
  """
  @spec get_descendant_sheet_ids(integer()) :: [integer()]
  def get_descendant_sheet_ids(sheet_id) do
    anchor =
      from(s in "sheets",
        where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
        select: %{id: s.id}
      )

    recursion =
      from(s in "sheets",
        join: d in "descendants",
        on: s.parent_id == d.id,
        where: is_nil(s.deleted_at),
        select: %{id: s.id}
      )

    cte_query = anchor |> union_all(^recursion)

    from("descendants")
    |> recursive_ctes(true)
    |> with_cte("descendants", as: ^cte_query)
    |> select([d], d.id)
    |> Repo.all()
  end

  @doc """
  Creates inherited instances on a newly created child sheet from all ancestor
  inheritable blocks.
  """
  @spec inherit_blocks_for_new_sheet(Sheet.t()) :: {:ok, integer()}
  def inherit_blocks_for_new_sheet(%Sheet{parent_id: nil}), do: {:ok, 0}

  def inherit_blocks_for_new_sheet(%Sheet{} = sheet) do
    ancestors = build_ancestor_list(sheet)
    hidden_block_ids = collect_hidden_block_ids([sheet | ancestors])

    inheritable_blocks =
      ancestors
      |> Enum.flat_map(&load_children_scope_blocks/1)
      |> Enum.reject(fn b -> b.id in hidden_block_ids end)

    do_inherit_blocks(sheet, inheritable_blocks)
  end

  @doc """
  Recalculates inherited blocks when a sheet is moved to a new parent.

  1. Removes inherited instances from old ancestor chain (keeps detached blocks)
  2. Creates inherited instances from new ancestor chain
  """
  @spec recalculate_on_move(Sheet.t()) :: {:ok, integer()}
  def recalculate_on_move(%Sheet{} = sheet) do
    Repo.transaction(fn ->
      total = recalculate_sheet_inheritance(sheet.id)

      # Cascade to all descendants (parents before children)
      descendant_ids = get_descendant_sheet_ids(sheet.id)

      Enum.reduce(descendant_ids, total, fn descendant_id, acc ->
        acc + recalculate_sheet_inheritance(descendant_id)
      end)
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  # Recalculates inheritance for a single sheet: soft-deletes non-detached
  # inherited instances and re-inherits from the current ancestor chain.
  defp recalculate_sheet_inheritance(sheet_id) do
    now = TimeHelpers.now()

    # Soft-delete non-detached inherited instances (preserves data)
    from(b in Block,
      where:
        b.sheet_id == ^sheet_id and
          not is_nil(b.inherited_from_block_id) and
          b.detached == false and
          is_nil(b.deleted_at)
    )
    |> Repo.update_all(set: [deleted_at: now])

    # Re-inherit from new ancestor chain
    sheet = Repo.get!(Sheet, sheet_id)
    {:ok, count} = inherit_blocks_for_new_sheet(sheet)
    count
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp build_ancestor_list(%Sheet{parent_id: nil}), do: []
  defp build_ancestor_list(%Sheet{} = sheet), do: SheetQueries.list_ancestors(sheet.id)

  defp collect_hidden_block_ids(sheets) do
    sheets
    |> Enum.flat_map(fn sheet ->
      sheet.hidden_inherited_block_ids || []
    end)
    |> Enum.uniq()
  end

  defp next_block_position(sheet_id) do
    BlockCrud.next_block_position(sheet_id)
  end

  defp derive_variable_name(%Block{} = parent_block, _sheet_id) do
    if Block.can_be_variable?(parent_block.type) and not parent_block.is_constant do
      label = get_in(parent_block.config, ["label"])
      NameNormalizer.variablify(label)
    else
      nil
    end
  end

  # Derives variable name and deduplicates against existing names on the target sheet
  defp derive_unique_variable_name(%Block{} = parent_block, sheet_id) do
    base_name = derive_variable_name(parent_block, sheet_id)

    if base_name do
      existing_names = BlockCrud.list_variable_names(sheet_id)
      BlockCrud.find_unique_variable_name(base_name, existing_names)
    else
      nil
    end
  end

  # Loads children-scope blocks for an ancestor sheet (used in resolve_inherited_blocks)
  defp ancestor_to_block_group(ancestor, hidden_block_ids) do
    blocks =
      from(b in Block,
        where:
          b.sheet_id == ^ancestor.id and
            b.scope == "children" and
            is_nil(b.deleted_at),
        order_by: [asc: b.position]
      )
      |> Repo.all()
      |> Enum.reject(fn b -> b.id in hidden_block_ids end)

    %{source_sheet: ancestor, blocks: blocks}
  end

  # Lists non-detached instances for a parent block
  defp list_non_detached_instances(parent_block_id) do
    from(b in Block,
      where:
        b.inherited_from_block_id == ^parent_block_id and
          b.detached == false and
          is_nil(b.deleted_at)
    )
    |> Repo.all()
  end

  # Core sync logic extracted from sync_definition_change
  defp do_sync_definition(parent_block, instances) do
    variable_name = derive_sync_variable_name(parent_block)
    common_updates = build_common_updates(parent_block, instances)

    from(b in Block,
      where:
        b.inherited_from_block_id == ^parent_block.id and
          b.detached == false and
          is_nil(b.deleted_at)
    )
    |> Repo.update_all(common_updates)

    sync_instance_variable_names(parent_block.id, instances, variable_name)

    length(instances)
  end

  defp derive_sync_variable_name(parent_block) do
    label = get_in(parent_block.config, ["label"])
    base_variable_name = NameNormalizer.variablify(label)

    if Block.can_be_variable?(parent_block.type) and not parent_block.is_constant do
      base_variable_name
    else
      nil
    end
  end

  defp build_common_updates(parent_block, instances) do
    base = [
      set: [
        config: parent_block.config,
        required: parent_block.required,
        is_constant: parent_block.is_constant
      ]
    ]

    type_changed? = Enum.any?(instances, &(&1.type != parent_block.type))

    if type_changed? do
      Keyword.update!(base, :set, fn sets ->
        sets ++ [type: parent_block.type, value: Block.default_value(parent_block.type)]
      end)
    else
      base
    end
  end

  defp sync_instance_variable_names(parent_block_id, _instances, nil) do
    from(b in Block,
      where:
        b.inherited_from_block_id == ^parent_block_id and
          b.detached == false and
          is_nil(b.deleted_at)
    )
    |> Repo.update_all(set: [variable_name: nil])
  end

  defp sync_instance_variable_names(_parent_block_id, instances, variable_name) do
    instances
    |> Enum.group_by(& &1.sheet_id)
    |> Enum.each(fn {sheet_id, sheet_instances} ->
      dedup_variable_names_for_sheet(sheet_instances, sheet_id, variable_name)
    end)
  end

  defp dedup_variable_names_for_sheet(sheet_instances, sheet_id, variable_name) do
    existing_names = MapSet.new(BlockCrud.list_variable_names(sheet_id))

    Enum.reduce(sheet_instances, existing_names, fn instance, taken ->
      taken = MapSet.delete(taken, instance.variable_name)
      unique = BlockCrud.find_unique_variable_name(variable_name, taken)

      from(b in Block, where: b.id == ^instance.id)
      |> Repo.update_all(set: [variable_name: unique])

      MapSet.put(taken, unique)
    end)
  end

  # Cleans up entity references for deleted instance blocks
  defp cleanup_instance_references(instance_ids) do
    from(r in EntityReference,
      where: r.source_type == "block" and r.source_id in ^instance_ids
    )
    |> Repo.delete_all()
  end

  # Cleans orphaned hidden_inherited_block_ids on sheets referencing the parent block
  defp cleanup_hidden_block_ids(parent_block_id) do
    from(s in Sheet,
      where: ^parent_block_id in s.hidden_inherited_block_ids
    )
    |> Repo.all()
    |> Enum.each(fn sheet ->
      updated_ids = List.delete(sheet.hidden_inherited_block_ids, parent_block_id)

      sheet
      |> Ecto.Changeset.change(%{hidden_inherited_block_ids: updated_ids})
      |> Repo.update!()
    end)
  end

  # Loads children-scope blocks for an ancestor (used in inherit_blocks_for_new_sheet)
  defp load_children_scope_blocks(ancestor) do
    from(b in Block,
      where:
        b.sheet_id == ^ancestor.id and
          b.scope == "children" and
          is_nil(b.deleted_at),
      order_by: [asc: b.position]
    )
    |> Repo.all()
  end

  # Creates inherited block entries from inheritable blocks
  defp do_inherit_blocks(_sheet, []), do: {:ok, 0}

  defp do_inherit_blocks(sheet, inheritable_blocks) do
    now = TimeHelpers.now()

    start_position = next_block_position(sheet.id)
    existing_names = MapSet.new(BlockCrud.list_variable_names(sheet.id))

    {entries, _} =
      inheritable_blocks
      |> Enum.with_index(start_position)
      |> Enum.map_reduce(existing_names, fn {parent_block, index}, taken_names ->
        build_inherited_entry(parent_block, sheet.id, index, taken_names, now)
      end)

    {count, _} = Repo.insert_all(Block, entries)

    # Copy table structure for any table-type parent blocks
    inheritable_blocks
    |> Enum.filter(&(&1.type == "table"))
    |> Enum.each(&copy_table_structure_to_instances/1)

    {:ok, count}
  end

  defp build_inherited_entry(parent_block, sheet_id, position, taken_names, now) do
    base_name = derive_variable_name(parent_block, sheet_id)

    {variable_name, updated_taken} =
      resolve_unique_variable(base_name, taken_names)

    entry = %{
      type: parent_block.type,
      config: parent_block.config,
      value: Block.default_value(parent_block.type),
      position: position,
      is_constant: parent_block.is_constant,
      variable_name: variable_name,
      scope: "self",
      inherited_from_block_id: parent_block.id,
      detached: false,
      required: parent_block.required,
      column_group_id: nil,
      column_index: 0,
      sheet_id: sheet_id,
      inserted_at: now,
      updated_at: now
    }

    {entry, updated_taken}
  end

  defp resolve_unique_variable(nil, taken_names), do: {nil, taken_names}

  defp resolve_unique_variable(base_name, taken_names) do
    unique = BlockCrud.find_unique_variable_name(base_name, taken_names)
    {unique, MapSet.put(taken_names, unique)}
  end

  # =============================================================================
  # Table Structure Inheritance
  # =============================================================================

  # Copies table columns and rows from a parent block to all its non-detached instances
  # that don't already have columns (idempotent).
  defp copy_table_structure_to_instances(%Block{type: "table"} = parent_block) do
    {source_columns, source_rows} = load_table_structure(parent_block.id)
    instances = list_non_detached_instances(parent_block.id)

    for instance <- instances do
      existing_count =
        from(c in TableColumn, where: c.block_id == ^instance.id, select: count())
        |> Repo.one()

      if existing_count == 0 do
        insert_table_structure(instance.id, source_columns, source_rows)
      end
    end

    :ok
  end

  defp copy_table_structure_to_instances(_), do: :ok

  defp build_reattach_updates(source) do
    label = get_in(source.config, ["label"])
    variable_name = NameNormalizer.variablify(label)

    variable_name =
      if Block.can_be_variable?(source.type) and not source.is_constant do
        variable_name
      else
        nil
      end

    %{
      type: source.type,
      config: source.config,
      required: source.required,
      is_constant: source.is_constant,
      detached: false,
      variable_name: variable_name
    }
  end

  defp maybe_reset_table_structure({:ok, %{type: "table"}} = result, source_id) do
    reset_table_structure_from_source(result |> elem(1) |> Map.get(:id), source_id)
    result
  end

  defp maybe_reset_table_structure(result, _source_id), do: result

  # Resets table structure on an instance block to match the source block.
  defp reset_table_structure_from_source(instance_block_id, source_block_id) do
    Repo.delete_all(from(c in TableColumn, where: c.block_id == ^instance_block_id))
    Repo.delete_all(from(r in TableRow, where: r.block_id == ^instance_block_id))

    {source_columns, source_rows} = load_table_structure(source_block_id)
    insert_table_structure(instance_block_id, source_columns, source_rows)
  end

  defp load_table_structure(block_id) do
    columns =
      from(c in TableColumn, where: c.block_id == ^block_id, order_by: c.position)
      |> Repo.all()

    rows =
      from(r in TableRow, where: r.block_id == ^block_id, order_by: r.position)
      |> Repo.all()

    {columns, rows}
  end

  defp insert_table_structure(target_block_id, source_columns, source_rows) do
    now = TimeHelpers.now()

    col_entries =
      Enum.map(source_columns, fn col ->
        %{
          name: col.name,
          slug: col.slug,
          type: col.type,
          is_constant: col.is_constant,
          required: col.required,
          position: col.position,
          config: col.config,
          block_id: target_block_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if col_entries != [], do: Repo.insert_all(TableColumn, col_entries)

    row_entries =
      Enum.map(source_rows, fn row ->
        %{
          name: row.name,
          slug: row.slug,
          position: row.position,
          cells: row.cells,
          block_id: target_block_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if row_entries != [], do: Repo.insert_all(TableRow, row_entries)

    :ok
  end
end

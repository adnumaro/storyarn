defmodule Storyarn.Sheets.PropertyInheritance do
  @moduledoc """
  Core logic for property (block) inheritance between parent and child sheets.

  When a block has `scope: "children"`, it cascades to all descendant sheets.
  Each child gets its own instance block with `inherited_from_block_id` pointing
  back to the source definition. Values are always local to each child.
  """

  import Ecto.Query, warn: false

  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockCrud
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.FormulaBindingRewriter
  alias Storyarn.Sheets.ReferenceTracker
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetQueries
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

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
  @spec create_inherited_instances(Block.t(), [integer()]) ::
          {:ok, integer()} | {:error, term()}
  def create_inherited_instances(%Block{} = parent_block, child_sheet_ids) when is_list(child_sheet_ids) do
    if child_sheet_ids == [] do
      {:ok, 0}
    else
      fn ->
        child_sheet_ids = normalize_inheritance_target_ids!(child_sheet_ids)
        locked_parent_block = lock_inheritance_scope(parent_block, child_sheet_ids)
        do_create_inherited_instances(locked_parent_block, child_sheet_ids)
      end
      |> Repo.transaction()
      |> case do
        {:ok, count} -> {:ok, count}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc false
  @spec create_inherited_instances_for_all_descendants(Block.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def create_inherited_instances_for_all_descendants(%Block{} = parent_block) do
    fn ->
      {project_id, source_sheet_id} =
        fetch_inheritance_source_owner!(
          parent_block,
          {:inheritance_source_not_active, parent_block.id}
        )

      lock_active_project!(project_id)

      descendant_ids =
        all_descendant_sheet_ids(project_id, source_sheet_id)

      lock_source_write_sheets!(project_id, source_sheet_id, descendant_ids)
      source = lock_inheritance_parent_block!(parent_block, source_sheet_id)
      do_create_inherited_instances(source, descendant_ids)
    end
    |> Repo.transaction()
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_create_inherited_instances(parent_block, child_sheet_ids) do
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

    sheets_to_create = Enum.reject(child_sheet_ids, &MapSet.member?(existing_sheet_ids, &1))

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
      0
    else
      {count, _} = Repo.insert_all(Block, entries)
      copy_table_structure_to_instances(parent_block)
      count
    end
  end

  defp lock_inheritance_scope(parent_block, child_sheet_ids) do
    {project_id, source_sheet_id} =
      fetch_inheritance_source_owner!(parent_block, {:inheritance_source_not_active, parent_block.id})

    lock_active_project!(project_id)

    source_sheet =
      active_inheritance_source_sheet!(
        parent_block,
        project_id,
        source_sheet_id
      )

    validate_inheritance_targets!(source_sheet, child_sheet_ids)
    lock_active_inheritance_sheets!(project_id, source_sheet.id, child_sheet_ids)

    lock_inheritance_parent_block!(parent_block, source_sheet.id)
  end

  defp active_inheritance_source_sheet!(parent_block, project_id, source_sheet_id) do
    if parent_block.sheet_id != source_sheet_id do
      Repo.rollback({:inheritance_source_not_active, parent_block.id})
    end

    case Repo.one(
           from(sheet in Sheet,
             where:
               sheet.id == ^source_sheet_id and
                 sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at)
           )
         ) do
      %Sheet{} = source_sheet ->
        source_sheet

      nil ->
        Repo.rollback({:inheritance_source_not_active, parent_block.id})
    end
  end

  defp validate_inheritance_targets!(source_sheet, child_sheet_ids) do
    valid_target_ids =
      from(sheet in Sheet,
        where:
          sheet.id in ^child_sheet_ids and
            sheet.id != ^source_sheet.id and
            sheet.project_id == ^source_sheet.project_id and
            is_nil(sheet.deleted_at),
        select: sheet.id
      )
      |> Repo.all()
      |> MapSet.new()

    invalid_target_ids =
      child_sheet_ids
      |> Enum.reject(&MapSet.member?(valid_target_ids, &1))
      |> Enum.sort()

    if invalid_target_ids != [] do
      Repo.rollback({:invalid_inheritance_targets, invalid_target_ids})
    end
  end

  defp lock_inheritance_parent_block!(parent_block, source_sheet_id) do
    case Repo.one(
           from(block in Block,
             where:
               block.id == ^parent_block.id and
                 block.sheet_id == ^source_sheet_id and
                 is_nil(block.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Block{} = locked_parent_block ->
        locked_parent_block

      nil ->
        Repo.rollback({:inheritance_source_not_active, parent_block.id})
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
  @spec sync_definition_change(Block.t(), keyword()) :: {:ok, integer()}
  def sync_definition_change(%Block{} = parent_block, opts \\ []) do
    fn ->
      {locked_parent_block, instances, _project_id} =
        lock_active_source_and_instances!(parent_block, opts)

      if instances == [] do
        0
      else
        do_sync_definition(locked_parent_block, instances)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Detaches an inherited block, making it a local copy.
  Keeps `inherited_from_block_id` for provenance (allows re-attach).
  """
  @spec detach_block(Block.t()) :: {:ok, Block.t()} | {:error, term()}
  def detach_block(%Block{} = block) do
    Repo.transaction(fn ->
      locked_block = lock_active_inherited_instance!(block)

      case locked_block
           |> Ecto.Changeset.change(%{detached: true})
           |> Repo.update() do
        {:ok, detached} -> detached
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Re-attaches a previously detached block, syncing it with the parent definition.
  """
  @spec reattach_block(Block.t()) :: {:ok, Block.t()} | {:error, :source_not_found}
  def reattach_block(%Block{inherited_from_block_id: nil}), do: {:error, :source_not_found}

  def reattach_block(%Block{} = block) do
    Repo.transaction(fn ->
      {locked_block, source} = lock_reattach_scope!(block)

      updates =
        source
        |> build_reattach_updates()
        |> Map.put(:word_count, WordCount.for_block(source.type, locked_block.value))

      case locked_block
           |> Ecto.Changeset.change(updates)
           |> BlockCrud.ensure_unique_variable_name_public(locked_block.sheet_id, locked_block.id)
           |> Repo.update()
           |> maybe_reset_table_structure(source.id) do
        {:ok, reattached} -> reattached
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Adds an ancestor block ID to the sheet's hidden list, stopping it from cascading
  to this sheet's children.
  """
  @spec hide_for_children(Sheet.t(), integer()) :: {:ok, Sheet.t()}
  def hide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    update_hidden_inherited_block_ids(sheet, ancestor_block_id, :hide)
  end

  @doc """
  Removes an ancestor block ID from the sheet's hidden list.
  """
  @spec unhide_for_children(Sheet.t(), integer()) :: {:ok, Sheet.t()}
  def unhide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    update_hidden_inherited_block_ids(sheet, ancestor_block_id, :unhide)
  end

  @doc """
  Soft-deletes all inherited instances when a parent block with `scope: "children"` is deleted.
  """
  @spec delete_inherited_instances(Block.t()) :: {:ok, integer()}
  def delete_inherited_instances(%Block{} = parent_block) do
    Repo.transaction(fn ->
      now = TimeHelpers.now()

      {locked_parent_block, instances, project_id} =
        lock_active_source_and_instances!(parent_block, lock_hidden_sheets: true)

      instance_ids = Enum.map(instances, & &1.id)

      if instance_ids != [] do
        cleanup_instance_references(instance_ids)
      end

      cleanup_hidden_block_ids(locked_parent_block, project_id)

      {count, _} =
        Repo.update_all(
          from(b in Block,
            where:
              b.id in ^instance_ids and
                b.inherited_from_block_id == ^locked_parent_block.id and
                b.detached == false and
                is_nil(b.deleted_at)
          ),
          set: [deleted_at: now]
        )

      count
    end)
  end

  @doc """
  Restores all inherited instances when a parent block is restored.
  """
  @spec restore_inherited_instances(Block.t()) :: {:ok, integer()}
  def restore_inherited_instances(%Block{} = parent_block) do
    Repo.transaction(fn ->
      {locked_parent_block, instances, project_id} =
        lock_restorable_source_and_instances!(parent_block)

      instance_ids = Enum.map(instances, & &1.id)

      {count, _} =
        Repo.update_all(
          from(block in Block,
            where:
              block.id in ^instance_ids and
                block.inherited_from_block_id == ^locked_parent_block.id and
                block.detached == false and
                not is_nil(block.deleted_at)
          ),
          set: [deleted_at: nil]
        )

      rebuild_restored_instance_references!(project_id, instance_ids)
      count
    end)
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
    case active_sheet_project_id(sheet_id) do
      nil ->
        []

      project_id ->
        anchor =
          from(s in "sheets",
            where:
              s.parent_id == ^sheet_id and
                s.project_id == ^project_id and
                is_nil(s.deleted_at),
            select: %{id: s.id}
          )

        recursion =
          from(s in "sheets",
            join: d in "descendants",
            on: s.parent_id == d.id,
            where:
              s.project_id == ^project_id and
                is_nil(s.deleted_at),
            select: %{id: s.id}
          )

        cte_query = union_all(anchor, ^recursion)

        from("descendants")
        |> recursive_ctes(true)
        |> with_cte("descendants", as: ^cte_query)
        |> select([d], d.id)
        |> Repo.all()
    end
  end

  defp all_descendant_sheet_ids(project_id, sheet_id) do
    anchor =
      from(sheet in "sheets",
        where:
          sheet.parent_id == ^sheet_id and
            sheet.project_id == ^project_id,
        select: %{id: sheet.id}
      )

    recursion =
      from(sheet in "sheets",
        join: descendant in "all_descendants",
        on: sheet.parent_id == descendant.id,
        where: sheet.project_id == ^project_id,
        select: %{id: sheet.id}
      )

    cte_query = union_all(anchor, ^recursion)

    from("all_descendants")
    |> recursive_ctes(true)
    |> with_cte("all_descendants", as: ^cte_query)
    |> select([descendant], descendant.id)
    |> Repo.all()
    |> Enum.sort()
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
    case recalculate_on_move_with_sheet_ids(sheet) do
      {:ok, %{count: count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec recalculate_on_move_with_sheet_ids(Sheet.t()) ::
          {:ok, %{count: integer(), sheet_ids: [integer()]}} | {:error, term()}
  def recalculate_on_move_with_sheet_ids(%Sheet{} = sheet) do
    fn ->
      total = recalculate_sheet_inheritance(sheet.id)

      # Cascade to all descendants (parents before children)
      descendant_ids = get_descendant_sheet_ids(sheet.id)

      count =
        Enum.reduce(descendant_ids, total, fn descendant_id, acc ->
          acc + recalculate_sheet_inheritance(descendant_id)
        end)

      %{count: count, sheet_ids: [sheet.id | descendant_ids]}
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec verify_restored_sheet_inheritance!(Sheet.t()) :: :ok
  def verify_restored_sheet_inheritance!(%Sheet{deleted_at: nil} = sheet) do
    ensure_restore_transaction!()
    sheet = lock_restored_sheet!(sheet)
    eligible_sources = eligible_restored_sheet_sources(sheet)
    instances = lock_restored_sheet_instances!(sheet.id)

    verify_restored_sheet_instances!(eligible_sources, instances)

    :ok
  end

  # Recalculates inheritance for a single sheet: soft-deletes non-detached
  # inherited instances and re-inherits from the current ancestor chain.
  defp recalculate_sheet_inheritance(sheet_id) do
    detach_stale_inherited_blocks(sheet_id)

    sheet = Repo.get!(Sheet, sheet_id)
    ancestors = build_ancestor_list(sheet)
    hidden_block_ids = collect_hidden_block_ids([sheet | ancestors])
    existing_source_ids = existing_inherited_source_ids(sheet_id)

    inheritable_blocks =
      ancestors
      |> Enum.flat_map(&load_children_scope_blocks/1)
      |> Enum.reject(fn b -> b.id in hidden_block_ids or MapSet.member?(existing_source_ids, b.id) end)

    {:ok, count} = do_inherit_blocks(sheet, inheritable_blocks)
    count
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp ensure_restore_transaction! do
    if !Repo.in_transaction?() do
      raise ArgumentError,
            "verify_restored_sheet_inheritance!/1 must run inside the sheet restore transaction"
    end
  end

  defp lock_restored_sheet!(sheet) do
    Repo.one(
      from(current in Sheet,
        where:
          current.id == ^sheet.id and current.project_id == ^sheet.project_id and
            is_nil(current.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:sheet_not_active)
  end

  defp eligible_restored_sheet_sources(sheet) do
    ancestors = build_ancestor_list(sheet)
    hidden_block_ids = collect_hidden_block_ids([sheet | ancestors])

    ancestors
    |> Enum.flat_map(&load_children_scope_blocks/1)
    |> Enum.reject(&(&1.id in hidden_block_ids))
    |> Enum.sort_by(& &1.id)
    |> lock_restored_sheet_sources!(sheet.project_id)
  end

  defp lock_restored_sheet_instances!(sheet_id) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and
            not is_nil(block.inherited_from_block_id) and
            block.detached == false and is_nil(block.deleted_at),
        order_by: [asc: block.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp verify_restored_sheet_instances!(eligible_sources, instances) do
    instances_by_source = unique_instances_by_source!(instances)
    eligible_source_ids = MapSet.new(eligible_sources, & &1.id)

    verify_instances_have_eligible_sources!(instances, eligible_source_ids)
    verify_eligible_sources_have_current_instances!(eligible_sources, instances_by_source)
  end

  defp verify_instances_have_eligible_sources!(instances, eligible_source_ids) do
    Enum.each(instances, fn instance ->
      if !MapSet.member?(eligible_source_ids, instance.inherited_from_block_id) do
        Repo.rollback({:inheritance_source_not_active, instance.inherited_from_block_id})
      end
    end)
  end

  defp verify_eligible_sources_have_current_instances!(eligible_sources, instances_by_source) do
    Enum.each(eligible_sources, fn source ->
      instance =
        Map.get(instances_by_source, source.id) ||
          Repo.rollback({:stale_inherited_blocks, [source.id]})

      verify_inherited_definition!(source, instance)
      verify_inherited_table_structure!(source, instance)
    end)
  end

  defp active_sheet_project_id(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where:
          sheet.id == ^sheet_id and
            is_nil(sheet.deleted_at),
        select: sheet.project_id
      )
    )
  end

  defp lock_restored_sheet_sources!(sources, _project_id) when sources == [], do: []

  defp lock_restored_sheet_sources!(sources, project_id) do
    source_ids = Enum.map(sources, & &1.id)

    locked_sources =
      Repo.all(
        from(block in Block,
          join: owner_sheet in Sheet,
          on: owner_sheet.id == block.sheet_id,
          where:
            block.id in ^source_ids and block.scope == "children" and
              is_nil(block.deleted_at) and owner_sheet.project_id == ^project_id and
              is_nil(owner_sheet.deleted_at),
          order_by: [asc: block.id],
          lock: "FOR UPDATE",
          select: block
        )
      )

    if Enum.map(locked_sources, & &1.id) == source_ids do
      locked_sources
    else
      missing_id = Enum.find(source_ids, &(&1 not in Enum.map(locked_sources, fn block -> block.id end)))
      Repo.rollback({:inheritance_source_not_active, missing_id})
    end
  end

  defp unique_instances_by_source!(instances) do
    Enum.reduce(instances, %{}, fn instance, by_source ->
      case Map.fetch(by_source, instance.inherited_from_block_id) do
        :error ->
          Map.put(by_source, instance.inherited_from_block_id, instance)

        {:ok, _duplicate} ->
          Repo.rollback({:duplicate_inherited_instances, instance.inherited_from_block_id})
      end
    end)
  end

  defp verify_inherited_definition!(source, instance) do
    current? =
      instance.type == source.type and
        instance.config == source.config and
        instance.required == source.required and
        instance.is_constant == source.is_constant and
        instance.scope == "self"

    if !current?, do: Repo.rollback({:stale_inherited_definition, instance.id})
  end

  defp verify_inherited_table_structure!(%Block{type: "table"} = source, %Block{type: "table"} = instance) do
    block_ids = Enum.sort([source.id, instance.id])

    columns =
      Repo.all(
        from(column in TableColumn,
          where: column.block_id in ^block_ids,
          order_by: [asc: column.block_id, asc: column.id],
          lock: "FOR UPDATE"
        )
      )

    rows =
      Repo.all(
        from(row in TableRow,
          where: row.block_id in ^block_ids,
          order_by: [asc: row.block_id, asc: row.id],
          lock: "FOR UPDATE"
        )
      )

    source_columns = table_columns_for_block(columns, source.id)
    instance_columns = table_columns_for_block(columns, instance.id)
    source_rows = table_rows_for_block(rows, source.id)
    instance_rows = table_rows_for_block(rows, instance.id)

    column_definitions_match? =
      Enum.map(source_columns, &table_column_signature/1) ==
        Enum.map(instance_columns, &table_column_signature/1)

    row_definitions_match? =
      Enum.map(source_rows, &table_row_signature/1) ==
        Enum.map(instance_rows, &table_row_signature/1)

    expected_cell_keys = MapSet.new(source_columns, & &1.slug)

    cell_keys_match? =
      Enum.all?(instance_rows, fn row ->
        MapSet.new(Map.keys(row.cells || %{})) == expected_cell_keys
      end)

    if !column_definitions_match? or !row_definitions_match? or !cell_keys_match? do
      Repo.rollback({:stale_inherited_table, instance.id})
    end
  end

  defp verify_inherited_table_structure!(_source, _instance), do: :ok

  defp table_columns_for_block(columns, block_id) do
    columns
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  defp table_rows_for_block(rows, block_id) do
    rows
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  defp table_column_signature(column) do
    {
      column.slug,
      column.name,
      column.type,
      column.is_constant,
      column.required,
      column.position,
      column.config
    }
  end

  defp table_row_signature(row), do: {row.slug, row.name, row.position}

  defp normalize_inheritance_target_ids!(sheet_ids) do
    if Enum.all?(sheet_ids, &(is_integer(&1) and &1 > 0)) and
         length(sheet_ids) == length(Enum.uniq(sheet_ids)) do
      sheet_ids
    else
      Repo.rollback({:invalid_inheritance_targets, sheet_ids})
    end
  end

  defp fetch_inheritance_source_owner!(%Block{} = parent_block, error_reason) do
    case Repo.one(
           from(block in Block,
             join: sheet in Sheet,
             on: sheet.id == block.sheet_id,
             where: block.id == ^parent_block.id,
             select: {sheet.project_id, sheet.id}
           )
         ) do
      {project_id, sheet_id} when sheet_id == parent_block.sheet_id ->
        {project_id, sheet_id}

      _not_found_or_forged ->
        Repo.rollback(error_reason)
    end
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_active_inheritance_sheets!(project_id, source_sheet_id, target_sheet_ids) do
    requested_ids = Enum.sort([source_sheet_id | target_sheet_ids])

    locked_ids =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.id in ^requested_ids and
              sheet.project_id == ^project_id and
              is_nil(sheet.deleted_at),
          order_by: [asc: sheet.id],
          lock: "FOR UPDATE",
          select: sheet.id
        )
      )

    cond do
      source_sheet_id not in locked_ids ->
        Repo.rollback({:inheritance_source_not_active, source_sheet_id})

      locked_ids != requested_ids ->
        Repo.rollback({:invalid_inheritance_targets, requested_ids -- locked_ids})

      true ->
        :ok
    end
  end

  defp lock_source_write_sheets!(project_id, source_sheet_id, target_sheet_ids) do
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

    cond do
      locked_ids != requested_ids ->
        Repo.rollback({:invalid_inheritance_targets, requested_ids -- locked_ids})

      Enum.any?(locked_sheets, fn {id, deleted_at} ->
        id == source_sheet_id and not is_nil(deleted_at)
      end) ->
        Repo.rollback({:inheritance_source_not_active, source_sheet_id})

      true ->
        :ok
    end
  end

  defp lock_active_source_and_instances!(parent_block, opts) do
    {project_id, source_sheet_id} =
      fetch_inheritance_source_owner!(
        parent_block,
        {:inheritance_source_not_active, parent_block.id}
      )

    lock_active_project!(project_id)

    instance_metadata = managed_instance_metadata(parent_block.id, project_id, opts)

    hidden_sheet_ids =
      if Keyword.get(opts, :lock_hidden_sheets, false) do
        active_hidden_sheet_ids(parent_block.id, project_id)
      else
        []
      end

    instance_sheet_ids = Enum.map(instance_metadata, &elem(&1, 1))

    lock_source_write_sheets!(
      project_id,
      source_sheet_id,
      Enum.uniq(instance_sheet_ids ++ hidden_sheet_ids)
    )

    source = lock_inheritance_parent_block!(parent_block, source_sheet_id)
    instances = lock_active_instance_rows!(source.id, instance_metadata)
    {source, instances, project_id}
  end

  defp managed_instance_metadata(parent_block_id, project_id, opts) do
    query =
      from(block in Block,
        join: owner_sheet in Sheet,
        on: owner_sheet.id == block.sheet_id,
        join: source in Block,
        on: source.id == ^parent_block_id,
        where:
          block.inherited_from_block_id == ^parent_block_id and
            block.detached == false and
            is_nil(source.deleted_at) and
            owner_sheet.project_id == ^project_id and
            is_nil(block.deleted_at),
        order_by: [asc: block.id],
        select: {block.id, block.sheet_id}
      )

    query =
      if Keyword.get(opts, :active_owner_sheets_only, false) do
        where(query, [_block, owner_sheet, _source], is_nil(owner_sheet.deleted_at))
      else
        query
      end

    Repo.all(query)
  end

  defp active_hidden_sheet_ids(parent_block_id, project_id) do
    Repo.all(
      from(sheet in Sheet,
        where:
          sheet.project_id == ^project_id and
            ^parent_block_id in sheet.hidden_inherited_block_ids,
        order_by: [asc: sheet.id],
        select: sheet.id
      )
    )
  end

  defp lock_active_instance_rows!(_parent_block_id, []), do: []

  defp lock_active_instance_rows!(parent_block_id, instance_metadata) do
    instance_ids = Enum.map(instance_metadata, &elem(&1, 0))

    instances =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^instance_ids and
              block.inherited_from_block_id == ^parent_block_id and
              block.detached == false,
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    if Enum.map(instances, & &1.id) == instance_ids do
      instances
    else
      Repo.rollback(:inheritance_instances_changed)
    end
  end

  defp lock_active_inherited_instance!(%Block{} = block) do
    case Repo.one(
           from(instance in Block,
             join: sheet in Sheet,
             on: sheet.id == instance.sheet_id,
             where: instance.id == ^block.id,
             select: {sheet.project_id, sheet.id, instance.inherited_from_block_id}
           )
         ) do
      {project_id, sheet_id, source_id}
      when sheet_id == block.sheet_id and is_integer(source_id) ->
        lock_active_project!(project_id)
        lock_active_inheritance_sheets!(project_id, sheet_id, [])

        Repo.one(
          from(instance in Block,
            where:
              instance.id == ^block.id and
                instance.sheet_id == ^sheet_id and
                not is_nil(instance.inherited_from_block_id) and
                is_nil(instance.deleted_at),
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:block_not_active)

      _not_found_or_local ->
        Repo.rollback(:block_not_active)
    end
  end

  defp lock_reattach_scope!(%Block{} = block) do
    case Repo.one(
           from(instance in Block,
             join: instance_sheet in Sheet,
             on: instance_sheet.id == instance.sheet_id,
             left_join: source in Block,
             on: source.id == instance.inherited_from_block_id,
             left_join: source_sheet in Sheet,
             on: source_sheet.id == source.sheet_id,
             where: instance.id == ^block.id,
             select:
               {instance_sheet.project_id, instance_sheet.id, instance.inherited_from_block_id, source_sheet.project_id,
                source_sheet.id}
           )
         ) do
      {project_id, instance_sheet_id, source_id, project_id, source_sheet_id}
      when instance_sheet_id == block.sheet_id and is_integer(source_id) ->
        lock_active_project!(project_id)

        lock_active_inheritance_sheets!(
          project_id,
          instance_sheet_id,
          [source_sheet_id]
        )

        lock_reattach_blocks!(block.id, source_id, instance_sheet_id, source_sheet_id)

      _missing_or_foreign_source ->
        Repo.rollback(:source_not_found)
    end
  end

  defp lock_reattach_blocks!(instance_id, source_id, instance_sheet_id, source_sheet_id) do
    blocks =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^Enum.sort([instance_id, source_id]) and
              is_nil(block.deleted_at),
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    instance =
      Enum.find(
        blocks,
        &(&1.id == instance_id and &1.sheet_id == instance_sheet_id and
            &1.inherited_from_block_id == source_id)
      )

    source =
      Enum.find(
        blocks,
        &(&1.id == source_id and &1.sheet_id == source_sheet_id)
      )

    if instance && source do
      {instance, source}
    else
      Repo.rollback(:source_not_found)
    end
  end

  defp lock_restorable_source_and_instances!(parent_block) do
    {project_id, source_sheet_id} =
      fetch_inheritance_source_owner!(
        parent_block,
        {:inheritance_source_not_active, parent_block.id}
      )

    lock_active_project!(project_id)

    deleted_at = parent_block.deleted_at || TimeHelpers.now()
    lower_threshold = DateTime.add(deleted_at, -2, :second)
    upper_threshold = DateTime.add(deleted_at, 2, :second)

    metadata =
      Repo.all(
        from(block in Block,
          join: owner_sheet in Sheet,
          on: owner_sheet.id == block.sheet_id,
          where:
            block.inherited_from_block_id == ^parent_block.id and
              block.detached == false and
              not is_nil(block.deleted_at) and
              block.deleted_at >= ^lower_threshold and
              block.deleted_at <= ^upper_threshold and
              owner_sheet.project_id == ^project_id,
          order_by: [asc: block.id],
          select: {block.id, block.sheet_id}
        )
      )

    lock_source_write_sheets!(
      project_id,
      source_sheet_id,
      Enum.map(metadata, &elem(&1, 1))
    )

    source = lock_inheritance_parent_block!(parent_block, source_sheet_id)
    instances = lock_restorable_instance_rows!(source.id, metadata, lower_threshold, upper_threshold)
    {source, instances, project_id}
  end

  defp lock_restorable_instance_rows!(_parent_block_id, [], _lower_threshold, _upper_threshold), do: []

  defp lock_restorable_instance_rows!(parent_block_id, metadata, lower_threshold, upper_threshold) do
    instance_ids = Enum.map(metadata, &elem(&1, 0))

    instances =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^instance_ids and
              block.inherited_from_block_id == ^parent_block_id and
              block.detached == false and
              not is_nil(block.deleted_at) and
              block.deleted_at >= ^lower_threshold and
              block.deleted_at <= ^upper_threshold,
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    if Enum.map(instances, & &1.id) == instance_ids do
      instances
    else
      Repo.rollback(:inheritance_instances_changed)
    end
  end

  defp rebuild_restored_instance_references!(_project_id, []), do: :ok

  defp rebuild_restored_instance_references!(project_id, instance_ids) do
    active_instances =
      Repo.all(
        from(block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            block.id in ^instance_ids and is_nil(block.deleted_at) and
              sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          order_by: [asc: block.id],
          select: block
        )
      )

    Enum.each(active_instances, fn instance ->
      normalized_value =
        case ReferenceTracker.lock_and_normalize_block_value(
               project_id,
               instance.type,
               instance.value
             ) do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end

      instance =
        if normalized_value == instance.value do
          instance
        else
          instance
          |> Block.value_changeset(%{value: normalized_value})
          |> Repo.update!()
        end

      case ReferenceTracker.update_block_references(instance, project_id: project_id) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp build_ancestor_list(%Sheet{parent_id: nil}), do: []
  defp build_ancestor_list(%Sheet{} = sheet), do: SheetQueries.list_ancestors(sheet.id)

  defp detach_stale_inherited_blocks(sheet_id) do
    new_source_block_ids = current_ancestor_source_block_ids(sheet_id)

    Repo.update_all(
      from(b in Block,
        where:
          b.sheet_id == ^sheet_id and not is_nil(b.inherited_from_block_id) and
            b.detached == false and is_nil(b.deleted_at) and
            b.inherited_from_block_id not in ^new_source_block_ids
      ),
      set: [detached: true]
    )
  end

  defp current_ancestor_source_block_ids(sheet_id) do
    sheet_id
    |> ancestor_sheet_ids()
    |> children_scope_block_ids()
  end

  defp ancestor_sheet_ids(sheet_id) do
    case Repo.get!(Sheet, sheet_id) do
      %Sheet{parent_id: nil} -> []
      sheet -> sheet.id |> SheetQueries.list_ancestors() |> Enum.map(& &1.id)
    end
  end

  defp children_scope_block_ids([]), do: []

  defp children_scope_block_ids(ancestor_ids) do
    Repo.all(
      from(b in Block,
        where: b.sheet_id in ^ancestor_ids and b.scope == "children" and is_nil(b.deleted_at),
        select: b.id
      )
    )
  end

  defp existing_inherited_source_ids(sheet_id) do
    from(b in Block,
      where:
        b.sheet_id == ^sheet_id and
          not is_nil(b.inherited_from_block_id) and
          is_nil(b.deleted_at),
      select: b.inherited_from_block_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp collect_hidden_block_ids(sheets) do
    sheets
    |> Enum.flat_map(fn sheet ->
      sheet.hidden_inherited_block_ids || []
    end)
    |> Enum.uniq()
  end

  defp update_hidden_inherited_block_ids(%Sheet{} = sheet, ancestor_block_id, operation)
       when operation in [:hide, :unhide] do
    Repo.transaction(fn ->
      {project_id, sheet_id} = fetch_sheet_owner!(sheet)
      lock_active_project!(project_id)

      case operation do
        :hide ->
          lock_hide_scope!(project_id, sheet_id, ancestor_block_id)

        :unhide ->
          lock_active_inheritance_sheets!(project_id, sheet_id, [])
      end

      locked_sheet = Repo.get!(Sheet, sheet_id)
      current = locked_sheet.hidden_inherited_block_ids || []
      updated = update_hidden_ids(current, ancestor_block_id, operation)

      persist_hidden_inherited_block_ids!(locked_sheet, current, updated)
    end)
  end

  defp update_hidden_inherited_block_ids(_sheet, _ancestor_block_id, _operation), do: {:error, :invalid_inherited_block}

  defp persist_hidden_inherited_block_ids!(sheet, current, current), do: sheet

  defp persist_hidden_inherited_block_ids!(sheet, _current, updated) do
    case sheet
         |> Ecto.Changeset.change(%{hidden_inherited_block_ids: updated})
         |> Repo.update() do
      {:ok, updated_sheet} -> updated_sheet
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp fetch_sheet_owner!(%Sheet{} = sheet) do
    case Repo.one(
           from(persisted_sheet in Sheet,
             where: persisted_sheet.id == ^sheet.id,
             select: {persisted_sheet.project_id, persisted_sheet.id}
           )
         ) do
      {project_id, sheet_id}
      when project_id == sheet.project_id and sheet_id == sheet.id ->
        {project_id, sheet_id}

      _not_found_or_forged ->
        Repo.rollback(:sheet_not_active)
    end
  end

  defp lock_hide_scope!(project_id, target_sheet_id, ancestor_block_id)
       when is_integer(ancestor_block_id) and ancestor_block_id > 0 do
    case Repo.one(
           from(block in Block,
             join: source_sheet in Sheet,
             on: source_sheet.id == block.sheet_id,
             where:
               block.id == ^ancestor_block_id and
                 source_sheet.project_id == ^project_id,
             select: {source_sheet.id, block.scope}
           )
         ) do
      {source_sheet_id, "children"} ->
        lock_active_inheritance_sheets!(
          project_id,
          target_sheet_id,
          [source_sheet_id]
        )

        Repo.one(
          from(block in Block,
            where:
              block.id == ^ancestor_block_id and
                block.sheet_id == ^source_sheet_id and
                block.scope == "children" and
                is_nil(block.deleted_at),
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:invalid_inherited_block)

      _not_found_or_invalid_scope ->
        Repo.rollback(:invalid_inherited_block)
    end
  end

  defp lock_hide_scope!(_project_id, _target_sheet_id, _ancestor_block_id), do: Repo.rollback(:invalid_inherited_block)

  defp update_hidden_ids(current, ancestor_block_id, :hide) do
    if ancestor_block_id in current, do: current, else: [ancestor_block_id | current]
  end

  defp update_hidden_ids(current, ancestor_block_id, :unhide), do: List.delete(current, ancestor_block_id)

  defp next_block_position(sheet_id) do
    BlockCrud.next_block_position(sheet_id)
  end

  defp derive_variable_name(%Block{} = parent_block, _sheet_id) do
    if Block.can_be_variable?(parent_block.type) and not parent_block.is_constant do
      label = get_in(parent_block.config, ["label"])
      NameNormalizer.variablify(label)
    end
  end

  # Derives variable name and deduplicates against existing names on the target sheet
  defp derive_unique_variable_name(%Block{} = parent_block, sheet_id) do
    base_name = derive_variable_name(parent_block, sheet_id)

    if base_name do
      existing_names = BlockCrud.list_variable_names(sheet_id)
      BlockCrud.find_unique_variable_name(base_name, existing_names)
    end
  end

  # Loads children-scope blocks for an ancestor sheet (used in resolve_inherited_blocks)
  defp ancestor_to_block_group(ancestor, hidden_block_ids) do
    blocks =
      ancestor
      |> load_children_scope_blocks()
      |> Enum.reject(fn b -> b.id in hidden_block_ids end)

    %{source_sheet: ancestor, blocks: blocks}
  end

  # Lists active, non-detached instances in the source sheet's project.
  # A target sheet may be in trash: source writes still maintain its hidden
  # materialized instance so restore never has to recreate structure or IDs.
  defp list_non_detached_instances(%Block{} = parent_block) do
    case active_sheet_project_id(parent_block.sheet_id) do
      nil ->
        []

      project_id ->
        Repo.all(
          from(block in Block,
            join: owner_sheet in Sheet,
            on: owner_sheet.id == block.sheet_id,
            where:
              block.inherited_from_block_id == ^parent_block.id and
                block.detached == false and
                is_nil(block.deleted_at) and
                owner_sheet.project_id == ^project_id,
            order_by: [asc: block.id],
            lock: "FOR UPDATE",
            select: block
          )
        )
    end
  end

  # Core sync logic extracted from sync_definition_change
  defp do_sync_definition(parent_block, instances) do
    variable_name = derive_sync_variable_name(parent_block)
    common_updates = build_common_updates(parent_block, instances)
    instance_ids = Enum.map(instances, & &1.id)

    Repo.update_all(
      from(b in Block,
        where:
          b.id in ^instance_ids and
            b.inherited_from_block_id == ^parent_block.id and
            b.detached == false
      ),
      common_updates
    )

    sync_instance_variable_names(parent_block.id, instances, variable_name)

    length(instances)
  end

  defp derive_sync_variable_name(parent_block) do
    label = get_in(parent_block.config, ["label"])
    base_variable_name = NameNormalizer.variablify(label)

    if Block.can_be_variable?(parent_block.type) and not parent_block.is_constant do
      base_variable_name
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
        sets ++ [type: parent_block.type, value: Block.default_value(parent_block.type), word_count: 0]
      end)
    else
      base
    end
  end

  defp sync_instance_variable_names(_parent_block_id, instances, nil) do
    instance_ids = Enum.map(instances, & &1.id)

    Repo.update_all(
      from(b in Block,
        where:
          b.id in ^instance_ids and
            b.detached == false
      ),
      set: [variable_name: nil]
    )
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

      Repo.update_all(from(b in Block, where: b.id == ^instance.id), set: [variable_name: unique])
      MapSet.put(taken, unique)
    end)
  end

  # Cleans up entity references for deleted instance blocks
  defp cleanup_instance_references(instance_ids) do
    Repo.delete_all(from(r in EntityReference, where: r.source_type == "block" and r.source_id in ^instance_ids))
  end

  # Cleans orphaned hidden IDs inside every sheet in the source project,
  # including sheets in trash.
  defp cleanup_hidden_block_ids(%Block{} = parent_block, project_id) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(s in Sheet,
        where:
          s.project_id == ^project_id and
            ^parent_block.id in s.hidden_inherited_block_ids,
        update: [
          set: [
            hidden_inherited_block_ids:
              fragment(
                "array_remove(?, ?)",
                s.hidden_inherited_block_ids,
                ^parent_block.id
              ),
            updated_at: ^now
          ]
        ]
      ),
      []
    )
  end

  # Loads children-scope blocks for an ancestor (used in inherit_blocks_for_new_sheet)
  defp load_children_scope_blocks(ancestor) do
    Repo.all(
      from(b in Block,
        where: b.sheet_id == ^ancestor.id and b.scope == "children" and is_nil(b.deleted_at),
        order_by: [asc: b.position]
      )
    )
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
      word_count: 0,
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
  # that don't already have columns (idempotent). Rewrites formula bindings if needed.
  defp copy_table_structure_to_instances(%Block{type: "table"} = parent_block) do
    {source_columns, source_rows} = load_table_structure(parent_block.id)
    instances = list_non_detached_instances(parent_block)

    instance_ids = Enum.map(instances, & &1.id)

    instances_with_columns =
      from(c in TableColumn,
        where: c.block_id in ^instance_ids,
        distinct: true,
        select: c.block_id
      )
      |> Repo.all()
      |> MapSet.new()

    # Only load rewrite context if any formula cells with variable bindings exist
    rewrite_ctx = build_rewrite_context_if_needed(parent_block, source_rows, instances)

    for instance <- instances do
      if not MapSet.member?(instances_with_columns, instance.id) do
        rows = maybe_rewrite_rows(source_rows, instance, rewrite_ctx)
        insert_table_structure(instance.id, source_columns, rows)
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
    result |> elem(1) |> Map.get(:id) |> reset_table_structure_from_source(source_id)
    result
  end

  defp maybe_reset_table_structure(result, _source_id), do: result

  # Resets table structure on an instance block to match the source block.
  # Rewrites formula bindings if the source and instance are on different sheets.
  defp reset_table_structure_from_source(instance_block_id, source_block_id) do
    Repo.delete_all(from(c in TableColumn, where: c.block_id == ^instance_block_id))
    Repo.delete_all(from(r in TableRow, where: r.block_id == ^instance_block_id))

    {source_columns, source_rows} = load_table_structure(source_block_id)

    rows = maybe_rewrite_rows_for_single_instance(source_rows, instance_block_id, source_block_id)
    insert_table_structure(instance_block_id, source_columns, rows)
  end

  defp load_table_structure(block_id) do
    columns = Repo.all(from(c in TableColumn, where: c.block_id == ^block_id, order_by: c.position))

    rows = Repo.all(from(r in TableRow, where: r.block_id == ^block_id, order_by: r.position))

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

  # =============================================================================
  # Formula Binding Rewrite Helpers
  # =============================================================================

  # Builds rewrite context only if source rows contain formula variable bindings.
  # Returns nil if no rewriting is needed (zero overhead for non-formula tables).
  defp build_rewrite_context_if_needed(_parent_block, source_rows, instances) do
    has_formulas = FormulaBindingRewriter.any_rows_have_formula_bindings?(source_rows)

    parent_sheet_id =
      if has_formulas and instances != [], do: get_parent_sheet_id_from_instance(hd(instances))

    if parent_sheet_id do
      do_build_rewrite_context(parent_sheet_id, instances)
    end
  end

  defp do_build_rewrite_context(parent_sheet_id, instances) do
    parent_shortcut = get_sheet_shortcut(parent_sheet_id)
    child_sheet_ids = instances |> Enum.map(& &1.sheet_id) |> Enum.uniq()

    child_shortcuts =
      from(s in Sheet, where: s.id in ^child_sheet_ids, select: {s.id, s.shortcut})
      |> Repo.all()
      |> Map.new()

    children =
      Map.new(child_sheet_ids, fn sheet_id ->
        mapping = FormulaBindingRewriter.build_var_name_mapping(parent_sheet_id, sheet_id)
        {sheet_id, %{shortcut: Map.get(child_shortcuts, sheet_id), mapping: mapping}}
      end)

    %{parent_shortcut: parent_shortcut, children: children}
  end

  # Rewrites rows for a specific instance using the batch rewrite context.
  # Returns original rows unchanged if rewrite_ctx is nil.
  defp maybe_rewrite_rows(source_rows, _instance, nil), do: source_rows

  defp maybe_rewrite_rows(source_rows, instance, rewrite_ctx) do
    case Map.get(rewrite_ctx.children, instance.sheet_id) do
      nil ->
        source_rows

      %{shortcut: nil} ->
        source_rows

      %{shortcut: child_shortcut, mapping: mapping} when map_size(mapping) > 0 ->
        Enum.map(source_rows, fn row ->
          new_cells =
            FormulaBindingRewriter.rewrite_cells(
              row.cells,
              rewrite_ctx.parent_shortcut,
              child_shortcut,
              mapping
            )

          %{row | cells: new_cells}
        end)

      _ ->
        source_rows
    end
  end

  # Rewrites rows for a single instance (used by reset_table_structure_from_source).
  defp maybe_rewrite_rows_for_single_instance(source_rows, instance_block_id, source_block_id) do
    if FormulaBindingRewriter.any_rows_have_formula_bindings?(source_rows) do
      do_rewrite_for_single_instance(source_rows, instance_block_id, source_block_id)
    else
      source_rows
    end
  end

  defp do_rewrite_for_single_instance(source_rows, instance_block_id, source_block_id) do
    block_sheets =
      from(b in Block,
        where: b.id in ^[instance_block_id, source_block_id],
        select: {b.id, b.sheet_id}
      )
      |> Repo.all()
      |> Map.new()

    source_sheet_id = Map.get(block_sheets, source_block_id)
    instance_sheet_id = Map.get(block_sheets, instance_block_id)

    cond do
      is_nil(source_sheet_id) or is_nil(instance_sheet_id) -> source_rows
      source_sheet_id == instance_sheet_id -> source_rows
      true -> apply_single_instance_rewrite(source_rows, source_sheet_id, instance_sheet_id)
    end
  end

  defp apply_single_instance_rewrite(source_rows, source_sheet_id, instance_sheet_id) do
    parent_shortcut = get_sheet_shortcut(source_sheet_id)
    child_shortcut = get_sheet_shortcut(instance_sheet_id)
    mapping = FormulaBindingRewriter.build_var_name_mapping(source_sheet_id, instance_sheet_id)

    if parent_shortcut && child_shortcut && map_size(mapping) > 0 do
      Enum.map(source_rows, fn row ->
        %{
          row
          | cells:
              FormulaBindingRewriter.rewrite_cells(
                row.cells,
                parent_shortcut,
                child_shortcut,
                mapping
              )
        }
      end)
    else
      source_rows
    end
  end

  # Gets the parent sheet ID by looking up the source block of an inherited instance.
  defp get_parent_sheet_id_from_instance(%Block{inherited_from_block_id: nil}), do: nil

  defp get_parent_sheet_id_from_instance(%Block{inherited_from_block_id: source_id}) do
    Repo.one(from(b in Block, where: b.id == ^source_id, select: b.sheet_id))
  end

  defp get_sheet_shortcut(sheet_id) do
    Repo.one(from(s in Sheet, where: s.id == ^sheet_id, select: s.shortcut))
  end
end

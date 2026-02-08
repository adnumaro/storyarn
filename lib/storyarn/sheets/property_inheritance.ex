defmodule Storyarn.Sheets.PropertyInheritance do
  @moduledoc """
  Core logic for property (block) inheritance between parent and child sheets.

  When a block has `scope: "children"`, it cascades to all descendant sheets.
  Each child gets its own instance block with `inherited_from_block_id` pointing
  back to the source definition. Values are always local to each child.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Sheets.{Block, Sheet, BlockCrud, EntityReference}
  alias Storyarn.Repo

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
      |> Enum.map(fn ancestor ->
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
      end)
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
      now = DateTime.utc_now() |> DateTime.truncate(:second)

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
            sheet_id: sheet_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      if entries == [] do
        {:ok, 0}
      else
        {count, _} = Repo.insert_all(Block, entries)
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
      instances_query =
        from(b in Block,
          where:
            b.inherited_from_block_id == ^parent_block.id and
              b.detached == false and
              is_nil(b.deleted_at)
        )

      instances = Repo.all(instances_query)

      if instances == [] do
        0
      else
        # Derive variable name from parent config
        label = get_in(parent_block.config, ["label"])
        base_variable_name = Block.slugify(label)

        variable_name =
          if Block.can_be_variable?(parent_block.type) and not parent_block.is_constant do
            base_variable_name
          else
            nil
          end

        # Check if any instance has a different type (type change)
        type_changed? = Enum.any?(instances, &(&1.type != parent_block.type))

        # Batch update common fields with update_all
        common_updates =
          [
            set: [
              config: parent_block.config,
              required: parent_block.required,
              is_constant: parent_block.is_constant
            ]
          ]

        common_updates =
          if type_changed? do
            Keyword.update!(common_updates, :set, fn sets ->
              sets ++
                [
                  type: parent_block.type,
                  value: Block.default_value(parent_block.type)
                ]
            end)
          else
            common_updates
          end

        from(b in Block,
          where:
            b.inherited_from_block_id == ^parent_block.id and
              b.detached == false and
              is_nil(b.deleted_at)
        )
        |> Repo.update_all(common_updates)

        # Handle variable name dedup per-instance (different sheets may have different conflicts)
        if variable_name do
          # Group instances by sheet_id for efficient dedup
          instances
          |> Enum.group_by(& &1.sheet_id)
          |> Enum.each(fn {sheet_id, sheet_instances} ->
            existing_names =
              MapSet.new(BlockCrud.list_variable_names(sheet_id))

            Enum.reduce(sheet_instances, existing_names, fn instance, taken ->
              # Remove the instance's own current name from taken (we're replacing it)
              taken = MapSet.delete(taken, instance.variable_name)
              unique = BlockCrud.find_unique_variable_name(variable_name, taken)

              from(b in Block, where: b.id == ^instance.id)
              |> Repo.update_all(set: [variable_name: unique])

              MapSet.put(taken, unique)
            end)
          end)
        else
          # Clear variable names
          from(b in Block,
            where:
              b.inherited_from_block_id == ^parent_block.id and
                b.detached == false and
                is_nil(b.deleted_at)
          )
          |> Repo.update_all(set: [variable_name: nil])
        end

        length(instances)
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
        updates = %{
          type: source.type,
          config: source.config,
          required: source.required,
          is_constant: source.is_constant,
          detached: false
        }

        # Derive variable name
        label = get_in(source.config, ["label"])
        variable_name = Block.slugify(label)

        updates =
          if Block.can_be_variable?(source.type) and not source.is_constant do
            Map.put(updates, :variable_name, variable_name)
          else
            Map.put(updates, :variable_name, nil)
          end

        block
        |> Ecto.Changeset.change(updates)
        |> BlockCrud.ensure_unique_variable_name_public(block.sheet_id, block.id)
        |> Repo.update()
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
      now = DateTime.utc_now() |> DateTime.truncate(:second)

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
        # Clean up entity references from these blocks
        from(r in EntityReference,
          where: r.source_type == "block" and r.source_id in ^instance_ids
        )
        |> Repo.delete_all()

        # Clean orphaned hidden_inherited_block_ids on sheets that reference the parent block
        from(s in Sheet,
          where: ^parent_block.id in s.hidden_inherited_block_ids
        )
        |> Repo.all()
        |> Enum.each(fn sheet ->
          updated_ids = List.delete(sheet.hidden_inherited_block_ids, parent_block.id)

          sheet
          |> Ecto.Changeset.change(%{hidden_inherited_block_ids: updated_ids})
          |> Repo.update!()
        end)
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
    direct_children_ids =
      from(s in Sheet,
        where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
        select: s.id
      )
      |> Repo.all()

    Enum.flat_map(direct_children_ids, fn child_id ->
      [child_id | get_descendant_sheet_ids(child_id)]
    end)
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
      |> Enum.flat_map(fn ancestor ->
        from(b in Block,
          where:
            b.sheet_id == ^ancestor.id and
              b.scope == "children" and
              is_nil(b.deleted_at),
          order_by: [asc: b.position]
        )
        |> Repo.all()
      end)
      |> Enum.reject(fn b -> b.id in hidden_block_ids end)

    if inheritable_blocks == [] do
      {:ok, 0}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      start_position = next_block_position(sheet.id)
      existing_names = MapSet.new(BlockCrud.list_variable_names(sheet.id))

      {entries, _} =
        inheritable_blocks
        |> Enum.with_index(start_position)
        |> Enum.map_reduce(existing_names, fn {parent_block, index}, taken_names ->
          base_name = derive_variable_name(parent_block, sheet.id)

          {variable_name, updated_taken} =
            if base_name do
              unique = BlockCrud.find_unique_variable_name(base_name, taken_names)
              {unique, MapSet.put(taken_names, unique)}
            else
              {nil, taken_names}
            end

          entry = %{
            type: parent_block.type,
            config: parent_block.config,
            value: Block.default_value(parent_block.type),
            position: index,
            is_constant: parent_block.is_constant,
            variable_name: variable_name,
            scope: "self",
            inherited_from_block_id: parent_block.id,
            detached: false,
            required: parent_block.required,
            sheet_id: sheet.id,
            inserted_at: now,
            updated_at: now
          }

          {entry, updated_taken}
        end)

      {count, _} = Repo.insert_all(Block, entries)
      {:ok, count}
    end
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
    now = DateTime.utc_now() |> DateTime.truncate(:second)

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

  defp build_ancestor_list(%Sheet{parent_id: parent_id}) do
    case Repo.get(Sheet, parent_id) do
      nil ->
        []

      parent ->
        if Sheet.deleted?(parent) do
          []
        else
          [parent | build_ancestor_list(parent)]
        end
    end
  end

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
      Block.slugify(label)
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
end

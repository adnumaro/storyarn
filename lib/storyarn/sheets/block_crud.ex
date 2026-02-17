defmodule Storyarn.Sheets.BlockCrud do
  @moduledoc false

  import Ecto.Query, warn: false
  require Logger

  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Repo
  alias Storyarn.Sheets.{Block, PropertyInheritance, ReferenceTracker, Sheet}

  # =============================================================================
  # Query Operations
  # =============================================================================

  def list_blocks(sheet_id) do
    from(b in Block,
      where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at),
      order_by: [asc: b.position]
    )
    |> Repo.all()
  end

  def get_block(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([b], is_nil(b.deleted_at))
    |> Repo.one()
  end

  def get_block!(block_id) do
    Block
    |> where(id: ^block_id)
    |> where([b], is_nil(b.deleted_at))
    |> Repo.one!()
  end

  @doc """
  Gets a block by ID, ensuring it belongs to the specified project.
  Returns nil if not found or not in project.
  """
  def get_block_in_project(block_id, project_id) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: b.id == ^block_id and s.project_id == ^project_id,
      where: is_nil(b.deleted_at) and is_nil(s.deleted_at),
      select: b
    )
    |> Repo.one()
  end

  @doc """
  Gets a block by ID with project validation. Raises if not found.
  """
  def get_block_in_project!(block_id, project_id) do
    case get_block_in_project(block_id, project_id) do
      nil -> raise Ecto.NoResultsError, queryable: Block
      block -> block
    end
  end

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_block(%Sheet{} = sheet, attrs) do
    position = attrs[:position] || next_block_position(sheet.id)

    block_type = attrs[:type] || attrs["type"]
    config = attrs[:config] || Block.default_config(block_type)
    value = attrs[:value] || Block.default_value(block_type)

    result =
      %Block{sheet_id: sheet.id}
      |> Block.create_changeset(
        attrs
        |> Map.put(:position, position)
        |> Map.put_new(:config, config)
        |> Map.put_new(:value, value)
      )
      |> ensure_unique_variable_name(sheet.id, nil)
      |> Repo.insert()

    # If block has scope: "children" and is not itself an inherited instance,
    # auto-create instances on all descendant sheets
    maybe_propagate_to_descendants(result, sheet.id)

    result
  end

  def update_block(%Block{} = block, attrs) do
    old_scope = block.scope

    result =
      block
      |> Block.update_changeset(attrs)
      |> ensure_unique_variable_name(block.sheet_id, block.id)
      |> Repo.update()

    # Handle scope changes
    case result do
      {:ok, updated_block} ->
        handle_scope_change(updated_block, old_scope)
        maybe_sync_definition(updated_block, old_scope)

      _ ->
        :ok
    end

    result
  end

  defp maybe_propagate_to_descendants({:ok, block}, sheet_id)
       when block.scope == "children" and is_nil(block.inherited_from_block_id) do
    descendant_ids = PropertyInheritance.get_descendant_sheet_ids(sheet_id)

    if descendant_ids != [] do
      {:ok, _count} = PropertyInheritance.create_inherited_instances(block, descendant_ids)
    end
  end

  defp maybe_propagate_to_descendants(_result, _sheet_id), do: :ok

  # Sync definition to instances if scope remained "children"
  defp maybe_sync_definition(%Block{scope: "children"} = updated_block, "children") do
    case PropertyInheritance.sync_definition_change(updated_block) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.error("Failed to sync definition change: #{inspect(reason)}")
    end
  end

  defp maybe_sync_definition(_block, _old_scope), do: :ok

  defp handle_scope_change(%Block{scope: "children"}, "self") do
    # Scope changed from "self" to "children" - instances created via propagation modal
    :ok
  end

  defp handle_scope_change(%Block{scope: "self"} = block, "children") do
    # Scope changed from "children" to "self" - remove all inherited instances
    PropertyInheritance.delete_inherited_instances(block)
  end

  defp handle_scope_change(_block, _old_scope), do: :ok

  def update_block_value(%Block{} = block, value) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:block, Block.value_changeset(block, %{value: value}))
    |> Ecto.Multi.run(:update_references, fn _repo, %{block: updated_block} ->
      if updated_block.type in ["reference", "rich_text"] do
        ReferenceTracker.update_block_references(updated_block)
      end

      {:ok, :done}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{block: updated_block}} ->
        TextExtractor.extract_block(updated_block)
        {:ok, updated_block}

      {:error, :block, changeset, _} ->
        {:error, changeset}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  def update_block_config(%Block{} = block, config) do
    result =
      block
      |> Block.config_changeset(%{config: config})
      |> ensure_unique_variable_name(block.sheet_id, block.id)
      |> Repo.update()

    # Sync definition change to inherited instances
    case result do
      {:ok, %{scope: "children"} = updated_block} ->
        case PropertyInheritance.sync_definition_change(updated_block) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.error("Failed to sync config change: #{inspect(reason)}")
        end

        TextExtractor.extract_block(updated_block)

      {:ok, updated_block} ->
        TextExtractor.extract_block(updated_block)

      _ ->
        :ok
    end

    result
  end

  @doc """
  Soft-deletes a block by setting deleted_at timestamp.
  """
  def delete_block(%Block{} = block) do
    # Clean up references and localization texts before soft-deleting
    ReferenceTracker.delete_block_references(block.id)
    TextExtractor.delete_block_texts(block.id)

    # If this is a parent block with scope: "children", soft-delete all instances
    if block.scope == "children" do
      PropertyInheritance.delete_inherited_instances(block)
    end

    result =
      block
      |> Block.delete_changeset()
      |> Repo.update()

    # If the block was in a column group, check if the group should dissolve
    case result do
      {:ok, deleted_block} ->
        maybe_dissolve_column_group(deleted_block.sheet_id, deleted_block.column_group_id)
        {:ok, deleted_block}

      error ->
        error
    end
  end

  @doc """
  Permanently deletes a block from the database.
  """
  def permanently_delete_block(%Block{} = block) do
    ReferenceTracker.delete_block_references(block.id)
    Repo.delete(block)
  end

  @doc """
  Restores a soft-deleted block.
  If the block has scope "children", also restores its inherited instances.
  """
  def restore_block(%Block{} = block) do
    result =
      block
      |> Block.restore_changeset()
      |> Repo.update()

    case result do
      {:ok, restored_block} when restored_block.scope == "children" ->
        PropertyInheritance.restore_inherited_instances(restored_block)

      _ ->
        :ok
    end

    result
  end

  def change_block(%Block{} = block, attrs \\ %{}) do
    Block.update_changeset(block, attrs)
  end

  @doc false
  def ensure_unique_variable_name_public(changeset, sheet_id, exclude_block_id) do
    ensure_unique_variable_name(changeset, sheet_id, exclude_block_id)
  end

  @doc """
  Returns the next available block position for a sheet.
  """
  def next_block_position(sheet_id) do
    query =
      from(b in Block,
        where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at),
        select: max(b.position)
      )

    (Repo.one(query) || -1) + 1
  end

  @doc """
  Returns all existing variable names for a sheet, optionally excluding a block ID.
  """
  def list_variable_names(sheet_id, exclude_block_id \\ nil) do
    query =
      from(b in Block,
        where:
          b.sheet_id == ^sheet_id and
            is_nil(b.deleted_at) and
            not is_nil(b.variable_name),
        select: b.variable_name
      )

    query =
      if exclude_block_id do
        where(query, [b], b.id != ^exclude_block_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Finds a unique variable name by appending _2, _3, etc. if collisions exist.
  `existing_names` can be a list or a MapSet of names already taken.
  """
  def find_unique_variable_name(base_name, existing_names) do
    member? =
      case existing_names do
        %MapSet{} -> MapSet.member?(existing_names, base_name)
        names when is_list(names) -> base_name in names
      end

    if member? do
      find_unique_with_suffix(base_name, existing_names, 2)
    else
      base_name
    end
  end

  # =============================================================================
  # Column Layout Operations
  # =============================================================================

  @doc """
  Reorders blocks with column layout information.

  Accepts a list of maps with `id`, `column_group_id`, and `column_index`.
  Updates each block's position (= list index), column_group_id, and column_index.
  Only updates blocks that belong to the given sheet.
  """
  def reorder_blocks_with_columns(sheet_id, items) when is_list(items) do
    Repo.transaction(fn ->
      items
      |> Enum.with_index()
      |> Enum.each(fn {item, index} ->
        block_id = item.id
        column_group_id = item.column_group_id
        column_index = item[:column_index] || 0
        column_index = max(0, min(column_index, 2))

        from(b in Block,
          where: b.id == ^block_id and b.sheet_id == ^sheet_id and is_nil(b.deleted_at)
        )
        |> Repo.update_all(
          set: [position: index, column_group_id: column_group_id, column_index: column_index]
        )
      end)

      list_blocks(sheet_id)
    end)
  end

  @doc """
  Creates a column group from a list of blocks.
  Generates a new UUID for the group and assigns column indices.
  Returns {:ok, group_id} or {:error, reason}.
  """
  def create_column_group(sheet_id, block_ids) when is_list(block_ids) do
    group_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      total_updated =
        block_ids
        |> Enum.with_index()
        |> Enum.reduce(0, fn {block_id, idx}, acc ->
          {count, _} =
            from(b in Block,
              where: b.id == ^block_id and b.sheet_id == ^sheet_id and is_nil(b.deleted_at)
            )
            |> Repo.update_all(set: [column_group_id: group_id, column_index: idx])

          acc + count
        end)

      if total_updated < 2 do
        Repo.rollback(:not_enough_blocks)
      else
        group_id
      end
    end)
  end

  @doc """
  Dissolves a column group by resetting column fields for all blocks in the group.
  """
  def dissolve_column_group(sheet_id, column_group_id) do
    from(b in Block,
      where:
        b.sheet_id == ^sheet_id and
          b.column_group_id == ^column_group_id and
          is_nil(b.deleted_at)
    )
    |> Repo.update_all(set: [column_group_id: nil, column_index: 0])

    :ok
  end

  # =============================================================================
  # Reordering
  # =============================================================================

  def reorder_blocks(sheet_id, block_ids) when is_list(block_ids) do
    Repo.transaction(fn ->
      block_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(fn {block_id, index} ->
        from(b in Block,
          where: b.id == ^block_id and b.sheet_id == ^sheet_id and is_nil(b.deleted_at)
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_blocks(sheet_id)
    end)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  # Ensures the variable_name is unique within the sheet.
  # If a collision exists, adds suffix _2, _3, etc.
  defp ensure_unique_variable_name(changeset, sheet_id, exclude_block_id) do
    import Ecto.Changeset, only: [get_field: 2, put_change: 3]

    variable_name = get_field(changeset, :variable_name)

    if is_nil(variable_name) do
      changeset
    else
      existing_names = list_variable_names(sheet_id, exclude_block_id)
      unique_name = find_unique_variable_name(variable_name, existing_names)

      if unique_name != variable_name do
        put_change(changeset, :variable_name, unique_name)
      else
        changeset
      end
    end
  end

  # Dissolves a column group if it has fewer than 2 active blocks remaining.
  defp maybe_dissolve_column_group(_sheet_id, nil), do: :ok

  defp maybe_dissolve_column_group(sheet_id, column_group_id) do
    count =
      from(b in Block,
        where:
          b.sheet_id == ^sheet_id and
            b.column_group_id == ^column_group_id and
            is_nil(b.deleted_at),
        select: count(b.id)
      )
      |> Repo.one()

    if count < 2 do
      dissolve_column_group(sheet_id, column_group_id)
    else
      :ok
    end
  end

  defp find_unique_with_suffix(base_name, existing_names, suffix) do
    candidate = "#{base_name}_#{suffix}"

    member? =
      case existing_names do
        %MapSet{} -> MapSet.member?(existing_names, candidate)
        names when is_list(names) -> candidate in names
      end

    if member? do
      find_unique_with_suffix(base_name, existing_names, suffix + 1)
    else
      candidate
    end
  end
end

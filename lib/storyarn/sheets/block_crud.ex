defmodule Storyarn.Sheets.BlockCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TreeOperations
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  # =============================================================================
  # Query Operations
  # =============================================================================

  def list_blocks(sheet_id) do
    Repo.all(
      from(b in Block,
        where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at),
        order_by: [asc: b.position],
        preload: [:inherited_from_block]
      )
    )
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
    Repo.one(
      from(b in Block,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: b.id == ^block_id and s.project_id == ^project_id,
        where: is_nil(b.deleted_at) and is_nil(s.deleted_at),
        select: b
      )
    )
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
    block_type = attrs[:type] || attrs["type"]
    config = attrs[:config] || Block.default_config(block_type)
    value = attrs[:value] || Block.default_value(block_type)
    word_count = WordCount.for_block(block_type, value)

    enriched_attrs =
      attrs
      |> Map.put_new(:config, config)
      |> Map.put_new(:value, value)

    sheet
    |> insert_block_in_transaction(enriched_attrs, word_count)
    |> broadcast_block_result()
  end

  def update_block(%Block{} = block, attrs) do
    old_scope = block.scope

    fn ->
      changeset =
        block
        |> Block.update_changeset(attrs)
        |> maybe_sync_variable_name(block)
        |> ensure_unique_variable_name(block.sheet_id, block.id)
        |> put_block_word_count()

      with {:ok, updated_block} <- Repo.update(changeset),
           :ok <- handle_scope_change(updated_block, old_scope),
           :ok <- maybe_sync_definition(updated_block, old_scope),
           :ok <- extract_updated_block(updated_block, old_scope) do
        updated_block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  defp insert_block_in_transaction(sheet, attrs, word_count) do
    Repo.transaction(fn ->
      Repo.one!(from(s in Sheet, where: s.id == ^sheet.id, lock: "FOR UPDATE"))
      position = attrs[:position] || attrs["position"] || next_block_position(sheet.id)
      insert_block(sheet, Map.put(attrs, :position, position), word_count)
    end)
  end

  defp insert_block(sheet, attrs, word_count) do
    case %Block{sheet_id: sheet.id}
         |> Block.create_changeset(attrs)
         |> Ecto.Changeset.put_change(:word_count, word_count)
         |> ensure_unique_variable_name(sheet.id, nil)
         |> Repo.insert() do
      {:ok, block} ->
        maybe_create_default_table_structure({:ok, block})
        maybe_propagate_to_descendants({:ok, block}, sheet.id)

        case Localization.extract_block_tree(block.id) do
          :ok -> block
          {:error, reason} -> Repo.rollback(reason)
        end

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_propagate_to_descendants({:ok, block}, sheet_id)
       when block.scope == "children" and is_nil(block.inherited_from_block_id) do
    descendant_ids = PropertyInheritance.get_descendant_sheet_ids(sheet_id)

    if descendant_ids != [] do
      {:ok, _count} = PropertyInheritance.create_inherited_instances(block, descendant_ids)
    end
  end

  defp maybe_propagate_to_descendants(_result, _sheet_id), do: :ok

  defp put_block_word_count(changeset) do
    type = Ecto.Changeset.get_field(changeset, :type)
    value = Ecto.Changeset.get_field(changeset, :value)
    Ecto.Changeset.put_change(changeset, :word_count, WordCount.for_block(type, value))
  end

  # Sync definition to instances if scope remained "children"
  defp maybe_sync_definition(%Block{scope: "children"} = updated_block, "children") do
    updated_block
    |> PropertyInheritance.sync_definition_change()
    |> normalize_side_effect()
  end

  defp maybe_sync_definition(_block, _old_scope), do: :ok

  defp handle_scope_change(%Block{scope: "children"}, "self") do
    # Scope changed from "self" to "children" - instances created via propagation modal
    :ok
  end

  defp handle_scope_change(%Block{scope: "self"} = block, "children") do
    # Scope changed from "children" to "self" - remove all inherited instances
    block
    |> PropertyInheritance.delete_inherited_instances()
    |> normalize_side_effect()
  end

  defp handle_scope_change(_block, _old_scope), do: :ok

  defp extract_updated_block(updated_block, old_scope) do
    if old_scope == "children" or updated_block.scope == "children" do
      Localization.extract_block_tree(updated_block.id)
    else
      Localization.extract_block(updated_block)
    end
  end

  defp normalize_side_effect({:ok, _result}), do: :ok
  defp normalize_side_effect({:error, reason}), do: {:error, reason}
  defp normalize_side_effect(:ok), do: :ok

  def update_block_value(%Block{} = block, value) do
    word_count = WordCount.for_block(block.type, value)

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :block,
      block
      |> Block.value_changeset(%{value: value})
      |> Ecto.Changeset.put_change(:word_count, word_count)
    )
    |> Ecto.Multi.run(:update_references, fn _repo, %{block: updated_block} ->
      if updated_block.type in ["reference", "rich_text"] do
        References.update_block_references(updated_block)
      end

      {:ok, :done}
    end)
    |> Ecto.Multi.run(:localization, fn _repo, %{block: updated_block} ->
      case Localization.extract_block(updated_block) do
        :ok -> {:ok, :done}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{block: updated_block}} ->
        broadcast_block_change(updated_block)
        {:ok, updated_block}

      {:error, :block, changeset, _} ->
        {:error, changeset}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  def update_block_config(%Block{} = block, config) do
    fn ->
      changeset =
        block
        |> Block.config_changeset(%{config: config})
        |> maybe_sync_variable_name(block)
        |> ensure_unique_variable_name(block.sheet_id, block.id)

      with {:ok, updated_block} <- Repo.update(changeset),
           :ok <- maybe_sync_config_definition(updated_block),
           :ok <- extract_updated_block(updated_block, block.scope) do
        updated_block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  defp maybe_sync_config_definition(%Block{scope: "children"} = updated_block) do
    updated_block
    |> PropertyInheritance.sync_definition_change()
    |> normalize_side_effect()
  end

  defp maybe_sync_config_definition(_updated_block), do: :ok

  @doc """
  Soft-deletes a block by setting deleted_at timestamp.
  """
  def delete_block(%Block{} = block) do
    fn ->
      # Clean up references and localization texts before soft-deleting
      References.delete_block_references(block.id)
      Localization.delete_block_tree_texts(block.id)

      # If this is a parent block with scope: "children", soft-delete all instances
      if block.scope == "children" do
        PropertyInheritance.delete_inherited_instances(block)
      end

      case block |> Block.delete_changeset() |> Repo.update() do
        {:ok, deleted_block} ->
          maybe_dissolve_column_group(deleted_block.sheet_id, deleted_block.column_group_id)
          deleted_block

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc """
  Permanently deletes a block from the database.
  """
  def permanently_delete_block(%Block{} = block) do
    fn ->
      References.delete_block_references(block.id)
      Localization.purge_texts_for_source("block", block.id)

      case Repo.delete(block) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc """
  Restores a soft-deleted block.
  If the block has scope "children", also restores its inherited instances.
  """
  def restore_block(%Block{} = block) do
    fn ->
      with {:ok, restored_block} <- block |> Block.restore_changeset() |> Repo.update(),
           :ok <- maybe_restore_inherited_instances(block),
           :ok <- extract_updated_block(restored_block, block.scope) do
        restored_block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  defp maybe_restore_inherited_instances(%Block{scope: "children"} = deleted_block) do
    deleted_block
    |> PropertyInheritance.restore_inherited_instances()
    |> normalize_side_effect()
  end

  defp maybe_restore_inherited_instances(_deleted_block), do: :ok

  @doc """
  Recreates a block from a snapshot (for undo/redo).
  First tries to restore a soft-deleted block with the same ID.
  Falls back to creating a new block if the original doesn't exist.
  """
  def create_block_from_snapshot(%Sheet{} = sheet, snapshot) do
    case Repo.get(Block, snapshot.id) do
      %Block{deleted_at: d} = block when not is_nil(d) ->
        # Block exists but is soft-deleted — restore it
        restore_block(block)

      nil ->
        # Block doesn't exist, create from scratch
        attrs = %{
          type: snapshot.type,
          position: snapshot.position,
          config: snapshot.config,
          value: snapshot.value,
          is_constant: Map.get(snapshot, :is_constant, false),
          variable_name: snapshot.variable_name,
          scope: Map.get(snapshot, :scope, "self"),
          column_group_id: snapshot.column_group_id,
          column_index: Map.get(snapshot, :column_index, 0)
        }

        insert_block_from_snapshot(sheet, snapshot, attrs)

      _active_block ->
        # Block exists and is active — shouldn't happen in normal undo/redo
        {:error, :block_already_exists}
    end
  end

  defp insert_block_from_snapshot(sheet, snapshot, attrs) do
    fn ->
      changeset =
        %Block{sheet_id: sheet.id}
        |> Block.create_changeset(attrs)
        |> Ecto.Changeset.put_change(:word_count, WordCount.for_block(snapshot.type, snapshot.value))

      with {:ok, block} <- Repo.insert(changeset),
           :ok <- extract_updated_block(block, block.scope) do
        block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc """
  Duplicates a block, placing the copy immediately after the original.
  Shifts subsequent blocks' positions by +1.
  Generates a unique variable_name for the copy.
  Does NOT copy inherited_from_block_id (duplicate is always "own").
  """
  def duplicate_block(%Block{} = block) do
    sheet_id = block.sheet_id

    fn ->
      # Shift all blocks after the original position by +1
      Repo.update_all(
        from(b in Block, where: b.sheet_id == ^sheet_id and b.position > ^block.position and is_nil(b.deleted_at)),
        inc: [position: 1]
      )

      attrs = %{
        type: block.type,
        config: block.config,
        value: block.value,
        scope: block.scope,
        is_constant: block.is_constant,
        position: block.position + 1,
        column_group_id: block.column_group_id,
        column_index: block.column_index
      }

      sheet = Repo.get!(Sheet, sheet_id)
      word_count = WordCount.for_block(block.type, block.value)

      case insert_block_in_transaction(sheet, attrs, word_count) do
        {:ok, new_block} -> new_block
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc """
  Moves a block up by swapping positions with the previous block.
  Returns `{:ok, :moved}`, `{:ok, :already_first}`, or `{:error, :not_found}`.
  """
  def move_block_up(block_id, sheet_id) do
    blocks = list_blocks(sheet_id)

    case Enum.find_index(blocks, &(&1.id == block_id)) do
      nil ->
        {:error, :not_found}

      0 ->
        {:ok, :already_first}

      idx ->
        swap_block_positions(Enum.at(blocks, idx), Enum.at(blocks, idx - 1))
    end
  end

  @doc """
  Moves a block down by swapping positions with the next block.
  Returns `{:ok, :moved}`, `{:ok, :already_last}`, or `{:error, :not_found}`.
  """
  def move_block_down(block_id, sheet_id) do
    blocks = list_blocks(sheet_id)
    last_idx = length(blocks) - 1

    case Enum.find_index(blocks, &(&1.id == block_id)) do
      nil ->
        {:error, :not_found}

      ^last_idx ->
        {:ok, :already_last}

      idx ->
        swap_block_positions(Enum.at(blocks, idx), Enum.at(blocks, idx + 1))
    end
  end

  defp swap_block_positions(%Block{} = a, %Block{} = b) do
    Repo.transaction(fn ->
      # Use a large negative sentinel to avoid unique constraint collisions
      temp_pos = -999_999

      Repo.update!(Block.position_changeset(a, %{position: temp_pos}))
      Repo.update!(Block.position_changeset(b, %{position: a.position}))
      Repo.update!(Block.position_changeset(a, %{position: b.position}))
    end)

    {:ok, :moved}
  end

  def change_block(%Block{} = block, attrs \\ %{}) do
    Block.update_changeset(block, attrs)
  end

  @doc """
  Updates a block's variable_name directly (user-initiated rename).
  Normalizes via variablify and ensures uniqueness within the sheet.
  """
  def update_variable_name(%Block{} = block, variable_name) do
    normalized = NameNormalizer.variablify(variable_name)

    # Fall back to auto-generated name from label when input is cleared
    normalized = normalized || default_variable_name(block)

    fn -> update_variable_name_transaction(block, normalized) end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  defp update_variable_name_transaction(block, variable_name) do
    with {:ok, updated_block} <-
           block
           |> Block.variable_changeset(%{variable_name: variable_name})
           |> ensure_unique_variable_name(block.sheet_id, block.id)
           |> Repo.update(),
         :ok <- Localization.extract_block(updated_block) do
      updated_block
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp default_variable_name(block) do
    label = get_in(block.config || %{}, ["label"])
    NameNormalizer.variablify(label) || "variable"
  end

  @doc false
  def ensure_unique_variable_name_public(changeset, sheet_id, exclude_block_id) do
    ensure_unique_variable_name(changeset, sheet_id, exclude_block_id)
  end

  # Syncs variable_name from label only if the block has no variable references.
  defp maybe_sync_variable_name(changeset, block) do
    config = Ecto.Changeset.get_field(changeset, :config) || %{}
    label = Map.get(config, "label")

    if label do
      referenced? = Flows.count_variable_usage(block.id) != %{}

      new_name =
        NameNormalizer.maybe_regenerate(
          block.variable_name,
          label,
          referenced?,
          &NameNormalizer.variablify/1
        )

      Ecto.Changeset.put_change(changeset, :variable_name, new_name)
    else
      changeset
    end
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
  @reorder_blocks_with_columns_sql """
  UPDATE blocks
  SET position = data.pos,
      column_group_id = data.gid::uuid,
      column_index = data.cidx
  FROM unnest($1::bigint[], $2::int[], $3::text[], $4::int[]) AS data(id, pos, gid, cidx)
  WHERE blocks.id = data.id AND blocks.sheet_id = $5 AND blocks.deleted_at IS NULL
  """

  def reorder_blocks_with_columns(sheet_id, items) when is_list(items) do
    Repo.transaction(fn ->
      {ids, positions, group_ids, col_indexes} =
        items
        |> Enum.with_index()
        |> Enum.reduce({[], [], [], []}, fn {item, index}, {ids, pos, gids, cidxs} ->
          col_idx = max(0, min(item[:column_index] || 0, 2))

          {
            [item.id | ids],
            [index | pos],
            [item.column_group_id | gids],
            [col_idx | cidxs]
          }
        end)

      Repo.query!(@reorder_blocks_with_columns_sql, [
        Enum.reverse(ids),
        Enum.reverse(positions),
        Enum.reverse(group_ids),
        Enum.reverse(col_indexes),
        sheet_id
      ])

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
            Repo.update_all(
              from(b in Block, where: b.id == ^block_id and b.sheet_id == ^sheet_id and is_nil(b.deleted_at)),
              set: [column_group_id: group_id, column_index: idx]
            )

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
    Repo.update_all(
      from(b in Block,
        where:
          b.sheet_id == ^sheet_id and b.column_group_id == ^column_group_id and
            is_nil(b.deleted_at)
      ),
      set: [column_group_id: nil, column_index: 0]
    )

    :ok
  end

  # =============================================================================
  # Reordering
  # =============================================================================

  def reorder_blocks(sheet_id, block_ids) when is_list(block_ids) do
    pairs =
      block_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()

    Repo.transaction(fn ->
      TreeOperations.batch_set_positions("blocks", pairs,
        scope: {"sheet_id", sheet_id},
        soft_delete: true
      )

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

      if unique_name == variable_name do
        changeset
      else
        put_change(changeset, :variable_name, unique_name)
      end
    end
  end

  # Dissolves a column group if it has fewer than 2 active blocks remaining.
  defp maybe_dissolve_column_group(_sheet_id, nil), do: :ok

  defp maybe_dissolve_column_group(sheet_id, column_group_id) do
    count =
      Repo.one(
        from(b in Block,
          where: b.sheet_id == ^sheet_id and b.column_group_id == ^column_group_id and is_nil(b.deleted_at),
          select: count(b.id)
        )
      )

    if count < 2 do
      dissolve_column_group(sheet_id, column_group_id)
    else
      :ok
    end
  end

  defp maybe_create_default_table_structure({:ok, %Block{type: "table"} = block}) do
    %TableColumn{block_id: block.id}
    |> TableColumn.create_changeset(%{
      name: "Value",
      type: "number",
      is_constant: false,
      position: 0
    })
    |> Repo.insert!()

    %TableRow{block_id: block.id}
    |> TableRow.create_changeset(%{name: "Row 1", position: 0, cells: %{"value" => nil}})
    |> Repo.insert!()
  end

  defp maybe_create_default_table_structure(_result), do: :ok

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

  # =============================================================================
  # Dashboard broadcast helpers
  # =============================================================================

  defp broadcast_block_change(%Block{} = block) do
    project_id = Repo.one(from(s in Sheet, where: s.id == ^block.sheet_id, select: s.project_id))

    if project_id, do: Collaboration.broadcast_dashboard_change(project_id, :sheets)
  end

  defp broadcast_block_result({:ok, %Block{} = block} = result) do
    broadcast_block_change(block)
    result
  end

  defp broadcast_block_result(result), do: result

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a block for import. Raw insert — no auto-position, no default config/value,
  no variable name uniqueness, no property propagation.
  Returns `{:ok, block}` or `{:error, changeset}`.
  """
  def import_block(sheet_id, attrs) do
    type = attrs[:type] || attrs["type"]
    value = attrs[:value] || attrs["value"]

    %Block{sheet_id: sheet_id}
    |> Block.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:word_count, WordCount.for_block(type, value))
    |> Repo.insert()
  end
end

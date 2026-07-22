defmodule Storyarn.Sheets.BlockCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TreeOperations
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.ReferenceTracker
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
    fn ->
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, sheet} = lock_active_block!(block.id, project_id)
      old_scope = block.scope

      changeset =
        block
        |> Block.update_changeset(attrs)
        |> validate_and_normalize_block_references!(sheet.project_id)
        |> maybe_sync_variable_name(block)
        |> ensure_unique_variable_name(block.sheet_id, block.id)
        |> put_block_word_count()

      with {:ok, updated_block} <- Repo.update(changeset),
           :ok <- maybe_update_block_references(updated_block, sheet.project_id),
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
      lock_active_project!(sheet.project_id)

      sheet =
        Repo.one(
          from(s in Sheet,
            where:
              s.id == ^sheet.id and s.project_id == ^sheet.project_id and
                is_nil(s.deleted_at),
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:sheet_not_active)

      position = attrs[:position] || attrs["position"] || next_block_position(sheet.id)

      attrs =
        attrs
        |> Map.put(:position, position)
        |> normalize_new_block_references!(sheet.project_id)

      insert_block(sheet, attrs, word_count)
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
        :ok = maybe_update_block_references(block, sheet.project_id)

        case Localization.extract_block_tree(block.id) do
          :ok -> block
          {:error, reason} -> Repo.rollback(reason)
        end

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_propagate_to_descendants({:ok, block}, _sheet_id)
       when block.scope == "children" and is_nil(block.inherited_from_block_id) do
    case PropertyInheritance.create_inherited_instances_for_all_descendants(block) do
      {:ok, _count} -> :ok
      {:error, reason} -> Repo.rollback(reason)
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

  defp handle_scope_change(%Block{scope: "children"}, "self"), do: :ok

  defp handle_scope_change(%Block{scope: "self"} = block, "children") do
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

  defp validate_and_normalize_block_references!(changeset, project_id) do
    type = Ecto.Changeset.get_field(changeset, :type)
    value = Ecto.Changeset.get_field(changeset, :value)

    case ReferenceTracker.lock_and_normalize_block_value(project_id, type, value) do
      {:ok, normalized_value} ->
        Ecto.Changeset.put_change(changeset, :value, normalized_value)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp normalize_new_block_references!(attrs, project_id) do
    type = attrs[:type] || attrs["type"]
    value = attrs[:value] || attrs["value"]

    case ReferenceTracker.lock_and_normalize_block_value(project_id, type, value) do
      {:ok, normalized_value} -> Map.put(attrs, :value, normalized_value)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp fetch_block_project_id!(block_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id,
        select: sheet.project_id
      )
    ) || Repo.rollback(:block_not_found)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_active_block!(block_id, project_id) do
    case Repo.one(
           from(block in Block,
             join: sheet in Sheet,
             on: sheet.id == block.sheet_id,
             where:
               block.id == ^block_id and is_nil(block.deleted_at) and
                 sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
             lock: "FOR UPDATE",
             select: {block, sheet}
           )
         ) do
      {%Block{} = block, %Sheet{} = sheet} -> {block, sheet}
      nil -> Repo.rollback(:block_not_active)
    end
  end

  def update_block_value(%Block{} = block, value) do
    fn ->
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, sheet} = lock_active_block!(block.id, project_id)

      value =
        case ReferenceTracker.lock_and_normalize_block_value(
               sheet.project_id,
               block.type,
               value
             ) do
          {:ok, normalized_value} -> normalized_value
          {:error, reason} -> Repo.rollback(reason)
        end

      word_count = WordCount.for_block(block.type, value)

      with {:ok, updated_block} <-
             block
             |> Block.value_changeset(%{value: value})
             |> Ecto.Changeset.put_change(:word_count, word_count)
             |> Repo.update(),
           :ok <- maybe_update_block_references(updated_block, sheet.project_id),
           :ok <- Localization.extract_block(updated_block) do
        updated_block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, updated_block} ->
        broadcast_block_change(updated_block)
        {:ok, updated_block}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_update_block_references(%Block{} = block, project_id) do
    References.update_block_references(block, project_id: project_id)
  end

  def update_block_config(%Block{} = block, config) do
    fn ->
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, sheet} = lock_active_block!(block.id, project_id)

      changeset =
        block
        |> Block.config_changeset(%{config: config})
        |> validate_and_normalize_block_references!(sheet.project_id)
        |> maybe_sync_variable_name(block)
        |> ensure_unique_variable_name(block.sheet_id, block.id)

      with {:ok, updated_block} <- Repo.update(changeset),
           :ok <- maybe_update_block_references(updated_block, sheet.project_id),
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
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, _sheet} = lock_active_block!(block.id, project_id)

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
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, sheet} = lock_deleted_block!(block.id, project_id)
      do_restore_block(block, sheet)
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc false
  @spec reconcile_active_blocks_for_sheet(Sheet.t()) :: [Block.t()]
  def reconcile_active_blocks_for_sheet(%Sheet{deleted_at: nil} = sheet) do
    if !Repo.in_transaction?() do
      raise ArgumentError,
            "reconcile_active_blocks_for_sheet/1 must run inside the sheet restore transaction"
    end

    active_blocks =
      Repo.all(
        from(block in Block,
          where: block.sheet_id == ^sheet.id and is_nil(block.deleted_at),
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.map(active_blocks, &reconcile_active_block(&1, sheet))
  end

  defp do_restore_block(block, sheet) do
    lock_active_inheritance_source!(block, sheet.project_id)

    normalized_value =
      case ReferenceTracker.lock_and_normalize_block_value(
             sheet.project_id,
             block.type,
             block.value
           ) do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end

    with {:ok, restored_block} <-
           block
           |> Block.restore_changeset()
           |> Ecto.Changeset.put_change(:value, normalized_value)
           |> Repo.update(),
         :ok <- maybe_update_block_references(restored_block, sheet.project_id),
         :ok <- maybe_restore_inherited_instances(block),
         :ok <- extract_updated_block(restored_block, block.scope) do
      restored_block
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reconcile_active_block(block, sheet) do
    lock_active_inheritance_source!(block, sheet.project_id)

    normalized_value =
      case ReferenceTracker.lock_and_normalize_block_value(
             sheet.project_id,
             block.type,
             block.value
           ) do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end

    block =
      if normalized_value == block.value do
        block
      else
        block
        |> Block.value_changeset(%{value: normalized_value})
        |> Repo.update!()
      end

    case maybe_update_block_references(block, sheet.project_id) do
      :ok -> block
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_deleted_block!(block_id, project_id) do
    case Repo.one(
           from(block in Block,
             join: sheet in Sheet,
             on: sheet.id == block.sheet_id,
             where:
               block.id == ^block_id and not is_nil(block.deleted_at) and
                 sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
             lock: "FOR UPDATE",
             select: {block, sheet}
           )
         ) do
      {%Block{} = block, %Sheet{} = sheet} -> {block, sheet}
      nil -> Repo.rollback(:block_not_restorable)
    end
  end

  defp lock_active_inheritance_source!(%Block{inherited_from_block_id: source_id, detached: false}, project_id)
       when is_integer(source_id) do
    case Repo.one(
           from(source in Block,
             join: source_sheet in Sheet,
             on: source_sheet.id == source.sheet_id,
             where:
               source.id == ^source_id and is_nil(source.deleted_at) and
                 source_sheet.project_id == ^project_id and is_nil(source_sheet.deleted_at),
             lock: "FOR SHARE",
             select: source.id
           )
         ) do
      ^source_id -> :ok
      nil -> Repo.rollback({:inheritance_source_not_active, source_id})
    end
  end

  defp lock_active_inheritance_source!(_block, _project_id), do: :ok

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
    fn ->
      lock_active_project!(sheet.project_id)
      locked_sheet = lock_active_sheet!(sheet.id, sheet.project_id)

      existing_block =
        Repo.one(
          from(block in Block,
            where: block.id == ^snapshot.id,
            lock: "FOR UPDATE"
          )
        )

      case existing_block do
        %Block{sheet_id: sheet_id, deleted_at: deleted_at} = block
        when sheet_id == locked_sheet.id and not is_nil(deleted_at) ->
          do_restore_block(block, locked_sheet)

        nil ->
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

          insert_block_from_snapshot(locked_sheet, snapshot, attrs)

        _existing_block ->
          Repo.rollback(:block_already_exists)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  defp insert_block_from_snapshot(sheet, snapshot, attrs) do
    attrs = normalize_new_block_references!(attrs, sheet.project_id)

    block =
      if is_integer(snapshot.id) and snapshot.id > 0 do
        %Block{id: snapshot.id, sheet_id: sheet.id}
      else
        %Block{sheet_id: sheet.id}
      end

    changeset =
      block
      |> Block.create_changeset(attrs)
      |> Ecto.Changeset.put_change(:word_count, WordCount.for_block(snapshot.type, attrs.value))
      |> ensure_unique_variable_name(sheet.id, nil)

    with {:ok, block} <- Repo.insert(changeset),
         :ok <- maybe_update_block_references(block, sheet.project_id),
         :ok <- extract_updated_block(block, block.scope) do
      block
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_active_sheet!(sheet_id, project_id) do
    Repo.one(
      from(sheet in Sheet,
        where:
          sheet.id == ^sheet_id and sheet.project_id == ^project_id and
            is_nil(sheet.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:sheet_not_active)
  end

  @doc """
  Duplicates a block, placing the copy immediately after the original.
  Shifts subsequent blocks' positions by +1.
  Generates a unique variable_name for the copy.
  Does NOT copy inherited_from_block_id (duplicate is always "own").
  """
  def duplicate_block(%Block{} = block) do
    fn ->
      project_id = fetch_block_project_id!(block.id)
      lock_active_project!(project_id)
      {block, sheet} = lock_active_block!(block.id, project_id)

      # Shift all blocks after the original position by +1
      Repo.update_all(
        from(candidate in Block,
          where:
            candidate.sheet_id == ^sheet.id and
              candidate.position > ^block.position and
              is_nil(candidate.deleted_at)
        ),
        inc: [position: 1]
      )

      attrs =
        normalize_new_block_references!(
          %{
            type: block.type,
            config: block.config,
            value: block.value,
            scope: block.scope,
            is_constant: block.is_constant,
            position: block.position + 1,
            column_group_id: block.column_group_id,
            column_index: block.column_index
          },
          sheet.project_id
        )

      word_count = WordCount.for_block(block.type, block.value)

      insert_block(sheet, attrs, word_count)
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  @doc """
  Moves a block up by swapping positions with the previous block.
  Returns `{:ok, :moved}`, `{:ok, :already_first}`, or `{:error, :not_found}`.
  """
  def move_block_up(block_id, sheet_id)
      when is_integer(block_id) and block_id > 0 and is_integer(sheet_id) and sheet_id > 0,
      do: move_block(block_id, sheet_id, :up)

  def move_block_up(_block_id, _sheet_id), do: {:error, :not_found}

  @doc """
  Moves a block down by swapping positions with the next block.
  Returns `{:ok, :moved}`, `{:ok, :already_last}`, or `{:error, :not_found}`.
  """
  def move_block_down(block_id, sheet_id)
      when is_integer(block_id) and block_id > 0 and is_integer(sheet_id) and sheet_id > 0,
      do: move_block(block_id, sheet_id, :down)

  def move_block_down(_block_id, _sheet_id), do: {:error, :not_found}

  defp move_block(block_id, sheet_id, direction) do
    Repo.transaction(fn ->
      project_id = fetch_sheet_project_id!(sheet_id)
      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)

      blocks =
        sheet_id
        |> lock_active_blocks!()
        |> Enum.sort_by(&{&1.position, &1.id})

      case {direction, Enum.find_index(blocks, &(&1.id == block_id))} do
        {_direction, nil} ->
          Repo.rollback(:not_found)

        {:up, 0} ->
          :already_first

        {:down, index} when index == length(blocks) - 1 ->
          :already_last

        {:up, index} ->
          swap_locked_block_positions!(Enum.at(blocks, index), Enum.at(blocks, index - 1))
          :moved

        {:down, index} ->
          swap_locked_block_positions!(Enum.at(blocks, index), Enum.at(blocks, index + 1))
          :moved
      end
    end)
  end

  defp swap_locked_block_positions!(%Block{} = first, %Block{} = second) do
    Repo.update!(Block.position_changeset(first, %{position: second.position}))
    Repo.update!(Block.position_changeset(second, %{position: first.position}))
  end

  def change_block(%Block{} = block, attrs \\ %{}) do
    Block.update_changeset(block, attrs)
  end

  @doc """
  Updates a block's variable_name directly (user-initiated rename).
  Normalizes via variablify and ensures uniqueness within the sheet.
  """
  def update_variable_name(%Block{id: block_id, sheet_id: sheet_id} = block, variable_name)
      when is_integer(block_id) and block_id > 0 and is_integer(sheet_id) and sheet_id > 0 and
             (is_binary(variable_name) or is_nil(variable_name)) do
    fn ->
      {project_id, sheet_id} = fetch_block_owner!(block.id)

      if block.sheet_id != sheet_id do
        Repo.rollback(:block_not_active)
      end

      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)
      locked_block = lock_active_block_in_sheet!(block.id, sheet_id)

      normalized = NameNormalizer.variablify(variable_name)
      normalized = normalized || default_variable_name(locked_block)

      update_variable_name_transaction(locked_block, normalized)
    end
    |> Repo.transaction()
    |> broadcast_block_result()
  end

  def update_variable_name(%Block{}, _variable_name), do: {:error, :invalid_variable_name_update}

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
  The payload must describe every active block in the sheet exactly once.
  Invalid, partial, foreign, or stale payloads are rejected atomically.
  """
  @reorder_blocks_with_columns_sql """
  UPDATE blocks
  SET position = data.pos,
      column_group_id = data.gid::uuid,
      column_index = data.cidx
  FROM unnest($1::bigint[], $2::int[], $3::text[], $4::int[]) AS data(id, pos, gid, cidx)
  WHERE blocks.id = data.id AND blocks.sheet_id = $5 AND blocks.deleted_at IS NULL
  """

  def reorder_blocks_with_columns(sheet_id, items) when is_integer(sheet_id) and sheet_id > 0 and is_list(items) do
    Repo.transaction(fn ->
      normalized_items = normalize_layout_items!(items)
      validate_layout_contract!(normalized_items, items)
      project_id = fetch_sheet_project_id!(sheet_id)

      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)

      locked_ids =
        sheet_id
        |> lock_active_blocks!()
        |> Enum.map(& &1.id)

      normalized_ids = Enum.map(normalized_items, & &1.id)
      ensure_complete_block_set!(normalized_ids, locked_ids, {:invalid_block_layout, items})

      {ids, positions, group_ids, col_indexes} =
        normalized_items
        |> Enum.with_index()
        |> Enum.reduce({[], [], [], []}, fn {item, index}, {ids, pos, gids, cidxs} ->
          {
            [item.id | ids],
            [index | pos],
            [item.column_group_id | gids],
            [item.column_index | cidxs]
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

  def reorder_blocks_with_columns(_sheet_id, items), do: {:error, {:invalid_block_layout, items}}

  @doc """
  Creates a column group from a list of blocks.
  Generates a new UUID for the group and assigns column indices.
  Returns {:ok, group_id} or {:error, reason}.
  """
  def create_column_group(sheet_id, block_ids) when is_integer(sheet_id) and sheet_id > 0 and is_list(block_ids) do
    Repo.transaction(fn ->
      if length(block_ids) < 2 do
        Repo.rollback(:not_enough_blocks)
      end

      normalized_ids =
        normalize_block_ids!(block_ids, {:invalid_column_group, block_ids})

      if length(normalized_ids) > 3 do
        Repo.rollback({:invalid_column_group, block_ids})
      end

      project_id = fetch_sheet_project_id!(sheet_id)
      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)

      locked_ids = lock_requested_active_block_ids!(sheet_id, normalized_ids)

      if locked_ids != Enum.sort(normalized_ids) do
        Repo.rollback({:invalid_column_group, block_ids})
      end

      group_id = Ecto.UUID.generate()

      normalized_ids
      |> Enum.with_index()
      |> Enum.each(fn {block_id, index} ->
        Repo.update_all(
          from(block in Block,
            where:
              block.id == ^block_id and block.sheet_id == ^sheet_id and
                is_nil(block.deleted_at)
          ),
          set: [column_group_id: group_id, column_index: index]
        )
      end)

      group_id
    end)
  end

  def create_column_group(_sheet_id, block_ids), do: {:error, {:invalid_column_group, block_ids}}

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

  def reorder_blocks(sheet_id, block_ids) when is_integer(sheet_id) and sheet_id > 0 and is_list(block_ids) do
    Repo.transaction(fn ->
      normalized_ids =
        normalize_block_ids!(block_ids, {:invalid_block_reorder, block_ids})

      project_id = fetch_sheet_project_id!(sheet_id)
      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)

      locked_ids =
        sheet_id
        |> lock_active_blocks!()
        |> Enum.map(& &1.id)

      ensure_complete_block_set!(
        normalized_ids,
        locked_ids,
        {:invalid_block_reorder, block_ids}
      )

      pairs = Enum.with_index(normalized_ids)

      TreeOperations.batch_set_positions("blocks", pairs,
        scope: {"sheet_id", sheet_id},
        soft_delete: true
      )

      list_blocks(sheet_id)
    end)
  end

  def reorder_blocks(_sheet_id, block_ids), do: {:error, {:invalid_block_reorder, block_ids}}

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp fetch_sheet_project_id!(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where: sheet.id == ^sheet_id,
        select: sheet.project_id
      )
    ) || Repo.rollback(:sheet_not_found)
  end

  defp fetch_block_owner!(block_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id,
        select: {sheet.project_id, sheet.id}
      )
    ) || Repo.rollback(:block_not_found)
  end

  defp lock_active_block_in_sheet!(block_id, sheet_id) do
    Repo.one(
      from(block in Block,
        where:
          block.id == ^block_id and block.sheet_id == ^sheet_id and
            is_nil(block.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:block_not_active)
  end

  defp lock_active_blocks!(sheet_id) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and
            is_nil(block.deleted_at) and
            (is_nil(block.inherited_from_block_id) or block.detached == true),
        order_by: [asc: block.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_requested_active_block_ids!(sheet_id, block_ids) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and block.id in ^block_ids and
            is_nil(block.deleted_at),
        order_by: [asc: block.id],
        lock: "FOR UPDATE",
        select: block.id
      )
    )
  end

  defp normalize_block_ids!(block_ids, error_reason) do
    if Enum.all?(block_ids, &(is_integer(&1) and &1 > 0)) and
         length(block_ids) == length(Enum.uniq(block_ids)) do
      block_ids
    else
      Repo.rollback(error_reason)
    end
  end

  defp normalize_layout_items!(items) do
    normalized =
      Enum.reduce_while(items, [], fn item, acc ->
        case normalize_layout_item(item) do
          {:ok, normalized_item} -> {:cont, [normalized_item | acc]}
          :error -> {:halt, :error}
        end
      end)

    case normalized do
      :error ->
        Repo.rollback({:invalid_block_layout, items})

      reversed_items ->
        normalized_items = Enum.reverse(reversed_items)
        ids = Enum.map(normalized_items, & &1.id)

        if length(ids) == length(Enum.uniq(ids)) do
          normalized_items
        else
          Repo.rollback({:invalid_block_layout, items})
        end
    end
  end

  defp normalize_layout_item(item) when is_map(item) do
    id = layout_item_value(item, :id)
    column_group_id = layout_item_value(item, :column_group_id)
    column_index = layout_item_value(item, :column_index)

    with true <- is_integer(id) and id > 0,
         {:ok, normalized_group_id} <- normalize_column_group_id(column_group_id),
         {:ok, normalized_column_index} <- normalize_column_index(column_index) do
      {:ok,
       %{
         id: id,
         column_group_id: normalized_group_id,
         column_index: normalized_column_index
       }}
    else
      _error -> :error
    end
  end

  defp normalize_layout_item(_item), do: :error

  defp layout_item_value(item, key) do
    case Map.fetch(item, key) do
      {:ok, value} -> value
      :error -> Map.get(item, Atom.to_string(key))
    end
  end

  defp normalize_column_group_id(nil), do: {:ok, nil}

  defp normalize_column_group_id(column_group_id) do
    Ecto.UUID.cast(column_group_id)
  end

  defp normalize_column_index(column_index) when is_integer(column_index) do
    {:ok, column_index}
  end

  defp normalize_column_index(_column_index), do: :error

  defp validate_layout_contract!(items, original_items) do
    valid_full_width_items? =
      Enum.all?(items, fn
        %{column_group_id: nil, column_index: 0} -> true
        %{column_group_id: nil} -> false
        _grouped_item -> true
      end)

    valid_groups? =
      items
      |> Enum.with_index()
      |> Enum.reject(fn {item, _position} -> is_nil(item.column_group_id) end)
      |> Enum.group_by(fn {item, _position} -> item.column_group_id end)
      |> Enum.all?(fn {_group_id, positioned_items} ->
        group_size = length(positioned_items)
        positions = Enum.map(positioned_items, &elem(&1, 1))
        column_indexes = Enum.map(positioned_items, fn {item, _position} -> item.column_index end)

        group_size in 2..3 and
          positions == Enum.to_list(hd(positions)..List.last(positions)) and
          column_indexes == Enum.to_list(0..(group_size - 1))
      end)

    if not valid_full_width_items? or not valid_groups? do
      Repo.rollback({:invalid_block_layout, original_items})
    end
  end

  defp ensure_complete_block_set!(requested_ids, locked_ids, error_reason) do
    if Enum.sort(requested_ids) != locked_ids do
      Repo.rollback(error_reason)
    end
  end

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

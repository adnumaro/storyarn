defmodule Storyarn.Projects.SheetProjectTrash do
  @moduledoc """
  Project-owned trash lifecycle for Sheets.

  Duplicates the Sheet tool's restore and permanent-purge semantics exactly,
  over Project-owned persistence records, so the Project trash surfaces stop
  depending on the Sheets boundary. Every guard the tool enforces — reference
  normalization, asset restore locks, inheritance verification, block
  reconciliation, localization re-extraction — runs here identically.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.LocalizationProjection
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.EntityVersionRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Persistence.TableColumnRecord
  alias Storyarn.Projects.Persistence.TableRowRecord
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo

  @doc "Gets a trashed Sheet scoped to its project, with avatars preloaded."
  def get_trashed(project_id, sheet_id) do
    SheetRecord
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([sheet], not is_nil(sheet.deleted_at))
    |> preload(avatars: :asset)
    |> Repo.one()
  end

  @doc """
  Restores a soft-deleted sheet.

  Note: Does not automatically restore descendant sheets.
  """
  def restore(%SheetRecord{} = sheet) do
    result =
      Repo.transaction(fn ->
        project_id =
          Repo.one(from(current in SheetRecord, where: current.id == ^sheet.id, select: current.project_id)) ||
            Repo.rollback(:sheet_not_found)

        lock_active_project!(project_id)
        locked_sheet = lock_deleted_sheet!(sheet.id, project_id)

        _normalized_references = lock_and_normalize_sheet_references!(project_id, locked_sheet)

        case Assets.lock_active_asset_references_for_restore(project_id, sheet_ids: [locked_sheet.id]) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        restored_sheet =
          case locked_sheet |> SheetRecord.restore_changeset() |> Repo.update() do
            {:ok, restored_sheet} -> restored_sheet
            {:error, reason} -> Repo.rollback(reason)
          end

        :ok = verify_restored_sheet_inheritance!(restored_sheet)
        active_blocks = reconcile_active_blocks_for_sheet(restored_sheet)

        with :ok <- LocalizationProjection.extract_sheet_blocks(restored_sheet.id),
             :ok <- LocalizationProjection.sync_sheet_names(restored_sheet.project_id) do
          %{
            sheet: restored_sheet,
            active_blocks: length(active_blocks)
          }
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %{sheet: restored_sheet}} ->
        Collaboration.broadcast_dashboard_result(
          {:ok, restored_sheet},
          restored_sheet.project_id,
          :sheets
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Permanently deletes a sheet. Descendants are retained and detached by the
  database parent foreign key.
  Use with caution - this cannot be undone.
  """
  def hard_delete(%SheetRecord{} = sheet) do
    fn ->
      block_ids = Repo.all(from(block in BlockRecord, where: block.sheet_id == ^sheet.id, select: block.id))

      # Delete all versions first
      Repo.delete_all(
        from(version in EntityVersionRecord,
          where: version.entity_type == "sheet" and version.entity_id == ^sheet.id
        )
      )

      # Delete references where this sheet is the target
      References.delete_target_references("sheet", sheet.id)
      LocalizationProjection.purge_texts_for_sources("block", block_ids)
      LocalizationProjection.purge_texts_for_source("sheet", sheet.id)

      # Delete the sheet (blocks cascade via FK)
      case Repo.delete(sheet) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  @doc """
  Soft-deletes a sheet and all its active descendants inside the caller's
  transaction, archiving their localization rows — the exact cascade the Sheet
  tool performs when trashing a subtree.
  """
  def delete_subtree_in_transaction(%SheetRecord{} = sheet) do
    lock_active_project!(sheet.project_id)
    sheet = lock_active_sheet!(sheet.id, sheet.project_id)

    # Get all descendant IDs before deleting (under the locks above)
    descendant_ids = get_descendant_ids(sheet.id, sheet.project_id)

    # Soft delete all descendants
    now = TimeHelpers.now()

    if descendant_ids != [] do
      Repo.update_all(from(s in SheetRecord, where: s.id in ^descendant_ids), set: [deleted_at: now])
    end

    archive_block_texts_for_sheets(sheet.project_id, [sheet.id | descendant_ids])

    Enum.each(
      [sheet.id | descendant_ids],
      &LocalizationProjection.archive_texts_for_sources("sheet", [&1], "source_deleted")
    )

    # Soft delete the sheet itself
    deleted =
      sheet
      |> SheetRecord.delete_changeset()
      |> Repo.update!()

    %{entity: deleted, deleted_ids: [deleted.id | descendant_ids]}
  end

  defp lock_active_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in SheetRecord,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %SheetRecord{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_active)
    end
  end

  defp get_descendant_ids(sheet_id, project_id) do
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

  defp archive_block_texts_for_sheets(project_id, sheet_ids) do
    :ok = LocalizationProjection.lock_inventory!(project_id)

    block_ids =
      Repo.all(
        from(block in BlockRecord,
          where: block.sheet_id in ^sheet_ids,
          select: block.id
        )
      )

    LocalizationProjection.archive_texts_for_sources("block", block_ids, "source_deleted")
    :ok
  end

  # ===========================================================================
  # Restore locks and reference normalization
  # ===========================================================================

  defp lock_active_project!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} -> :ok
      %Project{} -> Repo.rollback(:project_not_active)
      nil -> Repo.rollback(:project_not_found)
    end
  end

  defp lock_deleted_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in SheetRecord,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 not is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %SheetRecord{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_deleted)
    end
  end

  defp lock_and_normalize_sheet_references!(project_id, current_sheet) do
    parent_id = current_sheet.parent_id
    banner_asset_id = current_sheet.banner_asset_id

    case References.ProjectReferenceIntegrity.lock_active_references(project_id, [
           {:sheet, :parent_id, parent_id},
           {:asset, :banner_asset_id, banner_asset_id}
         ]) do
      {:ok, [normalized_parent_id, normalized_banner_asset_id]} ->
        validate_sheet_parent!(current_sheet, normalized_parent_id)

        case References.ProjectReferenceIntegrity.ensure_locked_asset_content_type(
               project_id,
               normalized_banner_asset_id,
               :banner_asset_id,
               "image/%"
             ) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp validate_sheet_parent!(%SheetRecord{}, nil), do: :ok

  defp validate_sheet_parent!(%SheetRecord{id: id}, id), do: Repo.rollback(:cannot_be_own_parent)

  defp validate_sheet_parent!(%SheetRecord{id: sheet_id}, parent_id) do
    if descendant?(parent_id, sheet_id), do: Repo.rollback(:would_create_cycle), else: :ok
  end

  defp descendant?(id, potential_ancestor_id, depth \\ 0)
  defp descendant?(_id, _potential_ancestor_id, depth) when depth > 100, do: false

  defp descendant?(id, potential_ancestor_id, depth) do
    case Repo.get(SheetRecord, id) do
      nil -> false
      %{id: ^potential_ancestor_id} -> true
      %{parent_id: nil} -> false
      %{parent_id: parent_id} -> descendant?(parent_id, potential_ancestor_id, depth + 1)
    end
  end

  # ===========================================================================
  # Inheritance verification (mirror of the Sheet tool's restore audit)
  # ===========================================================================

  defp verify_restored_sheet_inheritance!(%SheetRecord{deleted_at: nil} = sheet) do
    sheet = lock_restored_sheet!(sheet)
    eligible_sources = eligible_restored_sheet_sources(sheet)
    instances = lock_restored_sheet_instances!(sheet.id)

    verify_restored_sheet_instances!(eligible_sources, instances)

    :ok
  end

  defp lock_restored_sheet!(sheet) do
    Repo.one(
      from(current in SheetRecord,
        where:
          current.id == ^sheet.id and current.project_id == ^sheet.project_id and
            is_nil(current.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:sheet_not_active)
  end

  defp eligible_restored_sheet_sources(sheet) do
    ancestors = list_ancestors(sheet.id)
    hidden_block_ids = collect_hidden_block_ids([sheet | ancestors])

    ancestors
    |> Enum.flat_map(&load_children_scope_blocks/1)
    |> Enum.reject(&(&1.id in hidden_block_ids))
    |> Enum.sort_by(& &1.id)
    |> lock_restored_sheet_sources!(sheet.project_id)
  end

  defp lock_restored_sheet_instances!(sheet_id) do
    Repo.all(
      from(block in BlockRecord,
        where:
          block.sheet_id == ^sheet_id and
            not is_nil(block.inherited_from_block_id) and
            block.detached == false and is_nil(block.deleted_at),
        order_by: [asc: block.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_restored_sheet_sources!(sources, _project_id) when sources == [], do: []

  defp lock_restored_sheet_sources!(sources, project_id) do
    source_ids = Enum.map(sources, & &1.id)

    locked_sources =
      Repo.all(
        from(block in BlockRecord,
          join: owner_sheet in SheetRecord,
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
      Repo.rollback({:inheritance_sources_changed, source_ids})
    end
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

    if !current? do
      Repo.rollback({:stale_inherited_definition, instance.id})
    end
  end

  defp verify_inherited_table_structure!(%BlockRecord{type: "table"} = source, %BlockRecord{type: "table"} = instance) do
    block_ids = Enum.sort([source.id, instance.id])

    columns =
      Repo.all(
        from(column in TableColumnRecord,
          where: column.block_id in ^block_ids,
          order_by: [asc: column.block_id, asc: column.id],
          lock: "FOR UPDATE"
        )
      )

    rows =
      Repo.all(
        from(row in TableRowRecord,
          where: row.block_id in ^block_ids,
          order_by: [asc: row.block_id, asc: row.id],
          lock: "FOR UPDATE"
        )
      )

    source_columns = columns_for_block(columns, source.id)
    instance_columns = columns_for_block(columns, instance.id)
    source_rows = rows_for_block(rows, source.id)
    instance_rows = rows_for_block(rows, instance.id)

    column_definitions_match? =
      Enum.map(source_columns, &column_signature/1) ==
        Enum.map(instance_columns, &column_signature/1)

    row_definitions_match? =
      Enum.map(source_rows, &row_signature/1) ==
        Enum.map(instance_rows, &row_signature/1)

    if !column_definitions_match? or !row_definitions_match? or
         !cell_keys_current?(source_columns, instance_rows) do
      Repo.rollback({:stale_inherited_table, instance.id})
    end
  end

  defp verify_inherited_table_structure!(_source, _instance), do: :ok

  defp columns_for_block(columns, block_id) do
    columns
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  defp rows_for_block(rows, block_id) do
    rows
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  defp column_signature(column) do
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

  defp row_signature(row), do: {row.slug, row.name, row.position}

  defp cell_keys_current?(source_columns, instance_rows) do
    expected_cell_keys = MapSet.new(source_columns, & &1.slug)
    Enum.all?(instance_rows, &(MapSet.new(Map.keys(&1.cells || %{})) == expected_cell_keys))
  end

  # ===========================================================================
  # Ancestor chain (mirror of the Sheet tool's recursive CTE)
  # ===========================================================================

  defp list_ancestors(sheet_id) do
    anchor =
      from(s in "sheets",
        where: s.id == ^sheet_id and is_nil(s.deleted_at),
        select: %{parent_id: s.parent_id, depth: 0}
      )

    recursion =
      from(s in "sheets",
        join: a in "ancestors",
        on: s.id == a.parent_id,
        where: is_nil(s.deleted_at),
        select: %{parent_id: s.parent_id, depth: a.depth + 1}
      )

    cte_query = union_all(anchor, ^recursion)

    ancestor_ids =
      from("ancestors")
      |> recursive_ctes(true)
      |> with_cte("ancestors", as: ^cte_query)
      |> where([a], not is_nil(a.parent_id))
      |> select([a], a.parent_id)
      |> Repo.all()

    if ancestor_ids == [] do
      []
    else
      ancestors_map =
        from(s in SheetRecord,
          where: s.id in ^ancestor_ids and is_nil(s.deleted_at),
          preload: [avatars: :asset]
        )
        |> Repo.all()
        |> Map.new(fn s -> {s.id, s} end)

      # Reconstruct order from CTE result (child-first)
      ancestor_ids
      |> Enum.map(&Map.get(ancestors_map, &1))
      |> Enum.reject(&is_nil/1)
    end
  end

  defp collect_hidden_block_ids(sheets) do
    sheets
    |> Enum.flat_map(fn sheet ->
      sheet.hidden_inherited_block_ids || []
    end)
    |> Enum.uniq()
  end

  defp load_children_scope_blocks(ancestor) do
    Repo.all(
      from(block in BlockRecord,
        where: block.sheet_id == ^ancestor.id and block.scope == "children" and is_nil(block.deleted_at),
        order_by: [asc: block.position]
      )
    )
  end

  # ===========================================================================
  # Block reconciliation (mirror of the Sheet tool's restore reconcile)
  # ===========================================================================

  defp reconcile_active_blocks_for_sheet(%SheetRecord{deleted_at: nil} = sheet) do
    active_blocks =
      Repo.all(
        from(block in BlockRecord,
          where: block.sheet_id == ^sheet.id and is_nil(block.deleted_at),
          order_by: [asc: block.position, asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.map(active_blocks, &reconcile_active_block(&1, sheet))
  end

  defp reconcile_active_block(block, sheet) do
    lock_active_inheritance_source!(block, sheet.project_id)

    normalized_value =
      case References.lock_and_normalize_block_value(
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
        |> BlockRecord.value_changeset(%{value: normalized_value})
        |> Repo.update!()
      end

    case References.update_block_references(block, project_id: sheet.project_id) do
      :ok -> block
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_active_inheritance_source!(%BlockRecord{inherited_from_block_id: source_id, detached: false}, project_id)
       when is_integer(source_id) do
    case Repo.one(
           from(source in BlockRecord,
             join: source_sheet in SheetRecord,
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
end

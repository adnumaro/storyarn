defmodule Storyarn.Sheets.SheetCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Localization
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.ShortcutHelpers
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Sheets.BlockCrud
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Shortcuts
  alias Storyarn.Versioning.EntityVersion

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_sheet(%Project{} = project, attrs) do
    result = Repo.transaction(fn -> create_sheet_in_transaction(project, attrs) end)

    case result do
      {:ok, sheet} ->
        Localization.extract_sheet_blocks(sheet.id)
        Localization.sync_sheet_names(project.id)
        Collaboration.broadcast_dashboard_change(project.id, :sheets)

      _ ->
        :ok
    end

    case result do
      {:error, {:limit_reached, details}} -> {:error, :limit_reached, details}
      other -> other
    end
  end

  @doc false
  def create_sheet_in_transaction(%Project{} = project, attrs) do
    # A project row is the serialization point for both quota accounting and
    # sibling position allocation.
    locked_project = Repo.one!(from(p in Project, where: p.id == ^project.id, lock: "FOR UPDATE"))

    case Billing.can_create_item?(locked_project) do
      :ok -> :ok
      {:error, reason, details} -> Repo.rollback({reason, details})
    end

    if not is_nil(locked_project.deleted_at), do: Repo.rollback(:project_not_active)

    # Normalize keys to strings for changeset
    attrs = stringify_keys(attrs)
    attrs = lock_and_normalize_sheet_references!(project.id, nil, attrs)
    parent_id = attrs["parent_id"]
    position = attrs["position"] || next_position(project.id, parent_id)

    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    sheet_result =
      %Sheet{project_id: project.id}
      |> Sheet.create_changeset(Map.put(attrs, "position", position))
      |> Repo.insert()

    with {:ok, sheet} <- sheet_result,
         {:ok, _count} <- PropertyInheritance.inherit_blocks_for_new_sheet(sheet) do
      sheet
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def update_sheet(%Sheet{} = sheet, attrs) do
    result =
      Repo.transaction(fn ->
        lock_active_project!(sheet.project_id)
        locked_sheet = lock_active_sheet!(sheet.id, sheet.project_id)

        attrs =
          locked_sheet
          |> maybe_generate_shortcut_on_update(attrs)
          |> stringify_keys()
          |> then(&lock_and_normalize_sheet_references!(sheet.project_id, locked_sheet, &1))

        case locked_sheet
             |> Sheet.update_changeset(attrs)
             |> Repo.update() do
          {:ok, updated_sheet} -> updated_sheet
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, updated_sheet} -> Localization.sync_sheet_names(updated_sheet.project_id)
      _ -> :ok
    end

    Collaboration.broadcast_dashboard_result(result, sheet.project_id, :sheets)
  end

  @doc """
  Soft deletes a sheet (moves to trash).
  Also soft deletes all descendant sheets.
  """
  def delete_sheet(%Sheet{} = sheet) do
    trash_sheet(sheet)
  end

  @doc """
  Soft deletes a sheet and all its descendants (moves to trash).
  """
  def trash_sheet(%Sheet{} = sheet) do
    with {:ok, %{entity: entity}} <- delete_sheet_subtree(sheet), do: {:ok, entity}
  end

  @doc """
  Same soft-delete as `trash_sheet/1`, additionally returning `deleted_ids` —
  the committed cascade set, collected under the same project/sheet locks as
  the delete. Callers that broadcast about the deletion MUST use these ids: a
  separate pre-delete traversal can desync from concurrent tree changes.
  """
  def delete_sheet_subtree(%Sheet{} = sheet) do
    fn -> delete_sheet_subtree_in_transaction(sheet) end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  @doc false
  def delete_sheet_subtree_in_transaction(%Sheet{} = sheet) do
    lock_active_project!(sheet.project_id)
    sheet = lock_active_sheet!(sheet.id, sheet.project_id)

    # Get all descendant IDs before deleting (under the locks above)
    descendant_ids = get_descendant_ids(sheet.id)

    # Soft delete all descendants
    now = TimeHelpers.now()

    if descendant_ids != [] do
      Repo.update_all(from(s in Sheet, where: s.id in ^descendant_ids), set: [deleted_at: now])
    end

    Localization.delete_block_texts_for_sheets([sheet.id | descendant_ids])

    Enum.each([sheet.id | descendant_ids], &Localization.delete_texts_for_source("sheet", &1))

    # Soft delete the sheet itself
    deleted =
      sheet
      |> Sheet.delete_changeset()
      |> Repo.update!()

    %{entity: deleted, deleted_ids: [deleted.id | descendant_ids]}
  end

  @doc """
  Restores a soft-deleted sheet from trash.
  Revalidates all active blocks before making them visible again.
  Individually deleted blocks remain deleted.
  Note: Does not automatically restore descendant sheets.
  """
  def restore_sheet(%Sheet{} = sheet) do
    result =
      Repo.transaction(fn ->
        project_id =
          Repo.one(from(current in Sheet, where: current.id == ^sheet.id, select: current.project_id)) ||
            Repo.rollback(:sheet_not_found)

        lock_active_project!(project_id)
        locked_sheet = lock_deleted_sheet!(sheet.id, project_id)

        _normalized_references =
          lock_and_normalize_sheet_references!(project_id, locked_sheet, %{})

        restored_sheet =
          case locked_sheet |> Sheet.restore_changeset() |> Repo.update() do
            {:ok, restored_sheet} -> restored_sheet
            {:error, reason} -> Repo.rollback(reason)
          end

        :ok = PropertyInheritance.verify_restored_sheet_inheritance!(restored_sheet)
        active_blocks = BlockCrud.reconcile_active_blocks_for_sheet(restored_sheet)

        with :ok <- Localization.extract_sheet_blocks(restored_sheet.id),
             :ok <- Localization.sync_sheet_names(restored_sheet.project_id) do
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
  def permanently_delete_sheet(%Sheet{} = sheet) do
    fn ->
      block_ids = Repo.all(from(b in Storyarn.Sheets.Block, where: b.sheet_id == ^sheet.id, select: b.id))

      # Delete all versions first
      Repo.delete_all(from(v in EntityVersion, where: v.entity_type == "sheet" and v.entity_id == ^sheet.id))

      # Delete references where this sheet is the target
      References.delete_target_references("sheet", sheet.id)
      Localization.purge_texts_for_sources("block", block_ids)
      Localization.purge_texts_for_source("sheet", sheet.id)

      # Delete the sheet (blocks cascade via FK)
      case Repo.delete(sheet) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  def move_sheet(%Sheet{} = sheet, parent_id, position \\ nil) do
    fn ->
      lock_active_project!(sheet.project_id)
      current_sheet = lock_active_sheet!(sheet.id, sheet.project_id)

      %{"parent_id" => normalized_parent_id} =
        lock_and_normalize_sheet_references!(
          sheet.project_id,
          current_sheet,
          %{"parent_id" => parent_id}
        )

      move_sheet_transaction(current_sheet, normalized_parent_id, position)
    end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  defp move_sheet_transaction(sheet, parent_id, position) do
    position = position || next_position(sheet.project_id, parent_id)

    with {:ok, moved_sheet} <-
           sheet
           |> Sheet.move_changeset(%{parent_id: parent_id, position: position})
           |> Repo.update(),
         {:ok, %{sheet_ids: affected_sheet_ids}} <-
           PropertyInheritance.recalculate_on_move_with_sheet_ids(moved_sheet),
         :ok <- Localization.extract_sheet_blocks_for_sheets(affected_sheet_ids) do
      moved_sheet
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def change_sheet(%Sheet{} = sheet, attrs \\ %{}) do
    Sheet.update_changeset(sheet, attrs)
  end

  # =============================================================================
  # Validation
  # =============================================================================

  def validate_parent(%Sheet{} = sheet, parent_id) do
    cond do
      is_nil(parent_id) ->
        :ok

      parent_id == sheet.id ->
        {:error, :cannot_be_own_parent}

      true ->
        case Repo.get(Sheet, parent_id) do
          nil ->
            {:error, :parent_not_found}

          parent ->
            validate_parent_sheet(sheet, parent)
        end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp validate_parent_sheet(sheet, parent) do
    cond do
      not is_nil(parent.deleted_at) ->
        {:error, :parent_not_found}

      parent.project_id != sheet.project_id ->
        {:error, :parent_different_project}

      descendant?(parent.id, sheet.id) ->
        {:error, :would_create_cycle}

      true ->
        :ok
    end
  end

  defp get_descendant_ids(sheet_id) do
    PropertyInheritance.get_descendant_sheet_ids(sheet_id)
  end

  defp descendant?(potential_descendant_id, ancestor_id) do
    SharedTree.descendant?(Sheet, potential_descendant_id, ancestor_id)
  end

  defp next_position(project_id, parent_id) do
    SharedTree.next_position(Sheet, project_id, parent_id)
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

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

  defp lock_active_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in Sheet,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Sheet{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_active)
    end
  end

  defp lock_deleted_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in Sheet,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 not is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Sheet{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_deleted)
    end
  end

  defp lock_and_normalize_sheet_references!(project_id, current_sheet, attrs) do
    parent_id = effective_attr(attrs, "parent_id", current_sheet && current_sheet.parent_id)
    banner_asset_id = effective_attr(attrs, "banner_asset_id", current_sheet && current_sheet.banner_asset_id)

    case ProjectReferenceIntegrity.lock_active_references(project_id, [
           {:sheet, :parent_id, parent_id},
           {:asset, :banner_asset_id, banner_asset_id}
         ]) do
      {:ok, [normalized_parent_id, normalized_banner_asset_id]} ->
        validate_sheet_parent!(current_sheet, normalized_parent_id)

        case ProjectReferenceIntegrity.ensure_locked_asset_content_type(
               project_id,
               normalized_banner_asset_id,
               :banner_asset_id,
               "image/%"
             ) do
          :ok ->
            attrs
            |> maybe_put_normalized_reference("parent_id", normalized_parent_id)
            |> maybe_put_normalized_reference(
              "banner_asset_id",
              normalized_banner_asset_id
            )

          {:error, reason} ->
            Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp validate_sheet_parent!(nil, _parent_id), do: :ok
  defp validate_sheet_parent!(%Sheet{}, nil), do: :ok

  defp validate_sheet_parent!(%Sheet{id: id}, id), do: Repo.rollback(:cannot_be_own_parent)

  defp validate_sheet_parent!(%Sheet{id: sheet_id}, parent_id) do
    if descendant?(parent_id, sheet_id), do: Repo.rollback(:would_create_cycle), else: :ok
  end

  defp effective_attr(attrs, key, current) do
    if Map.has_key?(attrs, key), do: Map.get(attrs, key), else: current
  end

  defp maybe_put_normalized_reference(attrs, key, value) do
    if Map.has_key?(attrs, key), do: Map.put(attrs, key, value), else: attrs
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_sheet_id) do
    attrs
    |> stringify_keys()
    |> ShortcutHelpers.maybe_generate_shortcut(
      project_id,
      exclude_sheet_id,
      &Shortcuts.generate_sheet_shortcut/3
    )
  end

  defp maybe_generate_shortcut_on_update(%Sheet{} = sheet, attrs) do
    ShortcutHelpers.maybe_generate_shortcut_on_update(
      sheet,
      attrs,
      &Shortcuts.generate_sheet_shortcut/3,
      check_backlinks_fn: &(References.count_backlinks("sheet", &1.id) > 0)
    )
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a sheet for import. Raw insert — no auto-shortcut, no auto-position,
  no property inheritance. Returns `{:ok, sheet}` or `{:error, changeset}`.
  """
  def import_sheet(project_id, attrs) do
    %Sheet{project_id: project_id}
    |> Sheet.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a sheet's parent_id after import (two-pass parent linking).
  """
  def link_import_parent(%Sheet{} = sheet, parent_id) do
    sheet
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end
end

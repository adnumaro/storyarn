defmodule Storyarn.Sheets.SheetCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Localization
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.ShortcutHelpers
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Shortcuts
  alias Storyarn.Versioning.EntityVersion

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_sheet(%Project{} = project, attrs) do
    with :ok <- Billing.can_create_item?(project) do
      # Normalize keys to strings for changeset
      attrs = stringify_keys(attrs)
      parent_id = attrs["parent_id"]
      position = attrs["position"] || next_position(project.id, parent_id)

      # Auto-generate shortcut from name if not provided
      attrs = maybe_generate_shortcut(attrs, project.id, nil)

      result =
        %Sheet{project_id: project.id}
        |> Sheet.create_changeset(Map.put(attrs, "position", position))
        |> Repo.insert()

      # Auto-inherit blocks from ancestor chain
      with {:ok, sheet} <- result do
        PropertyInheritance.inherit_blocks_for_new_sheet(sheet)
      end

      case result do
        {:ok, sheet} ->
          Localization.extract_sheet_blocks(sheet.id)
          Localization.sync_sheet_names(project.id)
          Collaboration.broadcast_dashboard_change(project.id, :sheets)

        _ ->
          :ok
      end

      result
    end
  end

  def update_sheet(%Sheet{} = sheet, attrs) do
    # Auto-generate shortcut if sheet has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(sheet, attrs)

    result =
      sheet
      |> Sheet.update_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_sheet} -> Localization.sync_sheet_names(updated_sheet.project_id)
      _ -> :ok
    end

    result
  end

  @doc """
  Soft deletes a sheet (moves to trash).
  Also soft deletes all descendant sheets.
  """
  def delete_sheet(%Sheet{} = sheet) do
    result = trash_sheet(sheet)

    case result do
      {:ok, _} -> Collaboration.broadcast_dashboard_change(sheet.project_id, :sheets)
      _ -> :ok
    end

    result
  end

  @doc """
  Soft deletes a sheet and all its descendants (moves to trash).
  """
  def trash_sheet(%Sheet{} = sheet) do
    Repo.transaction(fn ->
      # Get all descendant IDs before deleting
      descendant_ids = get_descendant_ids(sheet.id)

      # Soft delete all descendants
      now = TimeHelpers.now()

      if descendant_ids != [] do
        Repo.update_all(from(s in Sheet, where: s.id in ^descendant_ids), set: [deleted_at: now])
      end

      Localization.delete_block_texts_for_sheets([sheet.id | descendant_ids])

      Enum.each([sheet.id | descendant_ids], &Localization.delete_texts_for_source("sheet", &1))

      # Soft delete the sheet itself
      sheet
      |> Sheet.delete_changeset()
      |> Repo.update!()
    end)
  end

  @doc """
  Restores a soft-deleted sheet from trash.
  Also restores all soft-deleted blocks for this sheet.
  Note: Does not automatically restore descendant sheets.
  """
  def restore_sheet(%Sheet{} = sheet) do
    alias Storyarn.Sheets.Block

    # Only restore blocks deleted within 2 seconds of the sheet's deletion,
    # to avoid restoring blocks that were individually deleted by the user.
    since = sheet.deleted_at || TimeHelpers.now()
    since_threshold = DateTime.add(since, -2, :second)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:sheet, Sheet.restore_changeset(sheet))
    |> Ecto.Multi.run(:restore_blocks, fn repo, _changes ->
      {count, _} =
        repo.update_all(
          from(b in Block,
            where: b.sheet_id == ^sheet.id and not is_nil(b.deleted_at) and b.deleted_at >= ^since_threshold
          ),
          set: [deleted_at: nil]
        )

      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{sheet: sheet}} ->
        Localization.extract_sheet_blocks(sheet.id)
        Localization.sync_sheet_names(sheet.project_id)
        {:ok, sheet}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Permanently deletes a sheet. Descendants are retained and detached by the
  database parent foreign key.
  Use with caution - this cannot be undone.
  """
  def permanently_delete_sheet(%Sheet{} = sheet) do
    Repo.transaction(fn ->
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
    end)
  end

  def move_sheet(%Sheet{} = sheet, parent_id, position \\ nil) do
    with :ok <- validate_parent(sheet, parent_id) do
      position = position || next_position(sheet.project_id, parent_id)

      result =
        sheet
        |> Sheet.move_changeset(%{parent_id: parent_id, position: position})
        |> Repo.update()

      with {:ok, moved_sheet} <- result,
           {:ok, %{sheet_ids: affected_sheet_ids}} <-
             PropertyInheritance.recalculate_on_move_with_sheet_ids(moved_sheet),
           :ok <- Localization.extract_sheet_blocks_for_sheets(affected_sheet_ids) do
        {:ok, moved_sheet}
      end
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
    descendant_ids = get_descendant_ids(ancestor_id)
    potential_descendant_id in descendant_ids
  end

  defp next_position(project_id, parent_id) do
    SharedTree.next_position(Sheet, project_id, parent_id)
  end

  defp stringify_keys(map), do: MapUtils.stringify_keys(map)

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

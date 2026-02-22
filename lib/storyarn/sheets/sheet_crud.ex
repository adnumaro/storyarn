defmodule Storyarn.Sheets.SheetCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.TextExtractor
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.{MapUtils, NameNormalizer, ShortcutHelpers, TimeHelpers}
  alias Storyarn.Sheets.{PropertyInheritance, ReferenceTracker, Sheet}
  alias Storyarn.Shortcuts

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_sheet(%Project{} = project, attrs) do
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

    result
  end

  def update_sheet(%Sheet{} = sheet, attrs) do
    # Auto-generate shortcut if sheet has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(sheet, attrs)

    result =
      sheet
      |> Sheet.update_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_sheet} -> TextExtractor.extract_sheet(updated_sheet)
      _ -> :ok
    end

    result
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
    Repo.transaction(fn ->
      # Get all descendant IDs before deleting
      descendant_ids = get_descendant_ids(sheet.id)

      # Soft delete all descendants
      now = TimeHelpers.now()

      if descendant_ids != [] do
        from(s in Sheet, where: s.id in ^descendant_ids)
        |> Repo.update_all(set: [deleted_at: now])

        # Clean up localization texts for descendants
        Enum.each(descendant_ids, &TextExtractor.delete_sheet_texts/1)
      end

      # Clean up localization texts for this sheet
      TextExtractor.delete_sheet_texts(sheet.id)

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

    Ecto.Multi.new()
    |> Ecto.Multi.update(:sheet, Sheet.restore_changeset(sheet))
    |> Ecto.Multi.run(:restore_blocks, fn repo, _changes ->
      # Restore all soft-deleted blocks for this sheet
      {count, _} =
        from(b in Block,
          where: b.sheet_id == ^sheet.id and not is_nil(b.deleted_at)
        )
        |> repo.update_all(set: [deleted_at: nil])

      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{sheet: sheet}} -> {:ok, sheet}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Permanently deletes a sheet and all its descendants.
  Use with caution - this cannot be undone.
  """
  def permanently_delete_sheet(%Sheet{} = sheet) do
    alias Storyarn.Sheets.{ReferenceTracker, SheetVersion}

    # Delete all versions first
    from(v in SheetVersion, where: v.sheet_id == ^sheet.id)
    |> Repo.delete_all()

    # Delete references where this sheet is the target
    ReferenceTracker.delete_target_references("sheet", sheet.id)

    # Delete the sheet (blocks cascade via FK)
    Repo.delete(sheet)
  end

  def move_sheet(%Sheet{} = sheet, parent_id, position \\ nil) do
    with :ok <- validate_parent(sheet, parent_id) do
      position = position || next_position(sheet.project_id, parent_id)

      result =
        sheet
        |> Sheet.move_changeset(%{parent_id: parent_id, position: position})
        |> Repo.update()

      # Recalculate inherited blocks for the moved sheet
      with {:ok, moved_sheet} <- result do
        PropertyInheritance.recalculate_on_move(moved_sheet)
      end

      result
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
    query =
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        select: max(s.position)
      )

    query =
      if is_nil(parent_id) do
        where(query, [s], is_nil(s.parent_id))
      else
        where(query, [s], s.parent_id == ^parent_id)
      end

    (Repo.one(query) || -1) + 1
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
    attrs = stringify_keys(attrs)

    cond do
      Map.has_key?(attrs, "shortcut") ->
        attrs

      ShortcutHelpers.name_changing?(attrs, sheet) ->
        referenced? = ReferenceTracker.count_backlinks("sheet", sheet.id) > 0

        shortcut =
          NameNormalizer.maybe_regenerate(
            sheet.shortcut,
            attrs["name"],
            referenced?,
            &NameNormalizer.shortcutify/1
          )

        # Only check uniqueness if the shortcut actually changed
        shortcut =
          if shortcut != sheet.shortcut do
            Shortcuts.generate_sheet_shortcut(attrs["name"], sheet.project_id, sheet.id)
          else
            shortcut
          end

        Map.put(attrs, "shortcut", shortcut)

      ShortcutHelpers.missing_shortcut?(sheet) ->
        ShortcutHelpers.generate_shortcut_from_name(
          sheet,
          attrs,
          &Shortcuts.generate_sheet_shortcut/3
        )

      true ->
        attrs
    end
  end
end

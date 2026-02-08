defmodule Storyarn.Sheets.SheetCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Sheets.Sheet
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
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

    %Sheet{project_id: project.id}
    |> Sheet.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_sheet(%Sheet{} = sheet, attrs) do
    # Auto-generate shortcut if sheet has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(sheet, attrs)

    sheet
    |> Sheet.update_changeset(attrs)
    |> Repo.update()
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
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      if descendant_ids != [] do
        from(s in Sheet, where: s.id in ^descendant_ids)
        |> Repo.update_all(set: [deleted_at: now])
      end

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
    alias Storyarn.Sheets.{SheetVersion, ReferenceTracker}

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

      sheet
      |> Sheet.move_changeset(%{parent_id: parent_id, position: position})
      |> Repo.update()
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
    direct_children_ids =
      from(s in Sheet,
        where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
        select: s.id
      )
      |> Repo.all()

    Enum.flat_map(direct_children_ids, fn child_id ->
      [child_id | get_descendant_ids(child_id)]
    end)
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
    # Only generate if shortcut is not provided and name is available
    has_shortcut = Map.has_key?(attrs, "shortcut") || Map.has_key?(attrs, :shortcut)
    name = attrs["name"] || attrs[:name]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_sheet_shortcut(name, project_id, exclude_sheet_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Sheet{} = sheet, attrs) do
    attrs = stringify_keys(attrs)

    # If attrs explicitly set shortcut, use that
    if Map.has_key?(attrs, "shortcut") do
      attrs
    else
      # If name is changing, regenerate shortcut from new name
      new_name = attrs["name"]

      if new_name && new_name != "" && new_name != sheet.name do
        shortcut = Shortcuts.generate_sheet_shortcut(new_name, sheet.project_id, sheet.id)
        Map.put(attrs, "shortcut", shortcut)
      else
        # If sheet has no shortcut yet, generate one from current name
        if is_nil(sheet.shortcut) || sheet.shortcut == "" do
          name = sheet.name

          if name && name != "" do
            shortcut = Shortcuts.generate_sheet_shortcut(name, sheet.project_id, sheet.id)
            Map.put(attrs, "shortcut", shortcut)
          else
            attrs
          end
        else
          attrs
        end
      end
    end
  end
end

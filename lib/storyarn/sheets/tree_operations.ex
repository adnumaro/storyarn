defmodule Storyarn.Sheets.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Project
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Sheets.Sheet

  @doc """
  Reorders sheets within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of sheet IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, sheets}` with the reordered sheets or `{:error, reason}`.
  """
  def reorder_sheets(project_id, parent_id, sheet_ids) when is_list(sheet_ids) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      normalized_parent_id = lock_parent_reference!(project_id, parent_id)
      normalized_sheet_ids = normalize_reorder_ids!(sheet_ids)
      lock_exact_sibling_set!(project_id, normalized_parent_id, normalized_sheet_ids)

      case SharedTree.reorder(
             Sheet,
             project_id,
             normalized_parent_id,
             normalized_sheet_ids,
             &list_sheets_by_parent/2
           ) do
        {:ok, sheets} -> sheets
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Moves a sheet to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the sheet's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, sheet}` with the moved sheet or `{:error, reason}`.
  """
  def move_sheet_to_position(%Sheet{} = sheet, new_parent_id, new_position) do
    Repo.transaction(fn ->
      lock_active_project!(sheet.project_id)
      locked_sheet = lock_active_sheet!(sheet.id, sheet.project_id)
      normalized_parent_id = lock_parent_reference!(sheet.project_id, new_parent_id)

      validate_parent_cycle!(locked_sheet.id, normalized_parent_id)

      case SharedTree.move_to_position(
             Sheet,
             locked_sheet,
             normalized_parent_id,
             new_position,
             &list_sheets_by_parent/2
           ) do
        {:ok, moved_sheet} -> moved_sheet
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp list_sheets_by_parent(project_id, parent_id) do
    SharedTree.list_by_parent(Sheet, project_id, parent_id)
  end

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

  defp lock_parent_reference!(project_id, parent_id) do
    case ProjectReferenceIntegrity.lock_active_references(project_id, [
           {:sheet, :parent_id, parent_id}
         ]) do
      {:ok, [normalized_parent_id]} -> normalized_parent_id
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_reorder_ids!(sheet_ids) do
    normalized_ids =
      Enum.reduce_while(sheet_ids, [], fn sheet_id, ids ->
        case ProjectReferenceIntegrity.normalize_optional_id(sheet_id) do
          {:ok, normalized_id} when is_integer(normalized_id) ->
            {:cont, [normalized_id | ids]}

          _error ->
            {:halt, :error}
        end
      end)

    case normalized_ids do
      :error ->
        Repo.rollback({:invalid_sheet_reorder, sheet_ids})

      reversed_ids ->
        normalized_ids = Enum.reverse(reversed_ids)

        if length(normalized_ids) == length(Enum.uniq(normalized_ids)) do
          normalized_ids
        else
          Repo.rollback({:invalid_sheet_reorder, sheet_ids})
        end
    end
  end

  defp lock_exact_sibling_set!(project_id, parent_id, sheet_ids) do
    locked_ids =
      Sheet
      |> where(
        [sheet],
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at)
      )
      |> SharedTree.add_parent_filter(parent_id)
      |> order_by([sheet], asc: sheet.id)
      |> lock("FOR UPDATE")
      |> select([sheet], sheet.id)
      |> Repo.all()

    if locked_ids == Enum.sort(sheet_ids) do
      :ok
    else
      Repo.rollback({:invalid_sheet_reorder, sheet_ids})
    end
  end

  defp validate_parent_cycle!(_sheet_id, nil), do: :ok

  defp validate_parent_cycle!(sheet_id, sheet_id), do: Repo.rollback(:would_create_cycle)

  defp validate_parent_cycle!(sheet_id, parent_id) do
    if SharedTree.descendant?(Sheet, parent_id, sheet_id),
      do: Repo.rollback(:would_create_cycle),
      else: :ok
  end
end

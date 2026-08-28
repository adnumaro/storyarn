defmodule Storyarn.Sheets.Editor.Commands.Tree do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor.Adapters.Postgres.Positions
  alias Storyarn.Sheets.Editor.Projections.ProjectRecord, as: Project
  alias Storyarn.Sheets.Editor.Queries.Tree, as: TreeQueries
  alias Storyarn.Sheets.References, as: ProjectReferenceIntegrity
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

      case reorder_siblings(project_id, normalized_parent_id, normalized_sheet_ids) do
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

      case move_locked_sheet(locked_sheet, normalized_parent_id, new_position) do
        {:ok, moved_sheet} -> moved_sheet
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp reorder_siblings(project_id, parent_id, ids) do
    pairs =
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()

    Repo.transaction(fn ->
      Positions.batch_set("sheets", pairs,
        scope: {"project_id", project_id},
        parent_id: parent_id,
        soft_delete: true
      )

      list_sheets_by_parent(project_id, parent_id)
    end)
  end

  defp move_locked_sheet(sheet, new_parent_id, new_position) do
    new_position = max(new_position, 0)

    Repo.transaction(fn ->
      case sheet
           |> Sheet.move_changeset(%{parent_id: new_parent_id, position: new_position})
           |> Repo.update() do
        {:ok, updated} ->
          apply_move(sheet, updated, new_parent_id, new_position)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp apply_move(sheet, updated, new_parent_id, new_position) do
    siblings = list_sheets_by_parent(sheet.project_id, new_parent_id)
    siblings_without_moved = Enum.reject(siblings, &(&1.id == sheet.id))

    pairs =
      siblings_without_moved
      |> List.insert_at(new_position, updated)
      |> Enum.with_index()
      |> Enum.map(fn {s, index} -> {s.id, index} end)

    Positions.batch_set("sheets", pairs,
      scope: {"project_id", sheet.project_id},
      parent_id: new_parent_id,
      soft_delete: true
    )

    if sheet.parent_id != new_parent_id do
      reorder_source_container(sheet.project_id, sheet.parent_id)
    end

    Repo.get!(Sheet, sheet.id)
  end

  defp reorder_source_container(project_id, parent_id) do
    pairs =
      project_id
      |> list_sheets_by_parent(parent_id)
      |> Enum.with_index()
      |> Enum.map(fn {sheet, index} -> {sheet.id, index} end)

    Positions.batch_set("sheets", pairs,
      scope: {"project_id", project_id},
      parent_id: parent_id,
      soft_delete: true
    )
  end

  defp list_sheets_by_parent(project_id, parent_id) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: sheet.position, asc: sheet.name]
    )
    |> TreeQueries.add_parent_filter(parent_id)
    |> Repo.all()
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
      |> TreeQueries.add_parent_filter(parent_id)
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
    if TreeQueries.descendant?(parent_id, sheet_id),
      do: Repo.rollback(:would_create_cycle),
      else: :ok
  end
end

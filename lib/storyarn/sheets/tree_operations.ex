defmodule Storyarn.Sheets.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Sheets.Sheet
  alias Storyarn.Repo

  @doc """
  Reorders sheets within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of sheet IDs
  in the desired order. Updates all positions in a single transaction.

  Returns `{:ok, sheets}` with the reordered sheets or `{:error, reason}`.
  """
  def reorder_sheets(project_id, parent_id, sheet_ids) when is_list(sheet_ids) do
    Repo.transaction(fn ->
      sheet_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(&update_sheet_position(&1, project_id, parent_id))

      list_sheets_by_parent(project_id, parent_id)
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
      old_parent_id = sheet.parent_id
      project_id = sheet.project_id

      # Update the sheet's parent and position
      {:ok, updated_sheet} =
        sheet
        |> Sheet.move_changeset(%{parent_id: new_parent_id, position: new_position})
        |> Repo.update()

      # Get all siblings in the destination container (including the moved sheet)
      siblings = list_sheets_by_parent(project_id, new_parent_id)

      # Build the new order: insert the moved sheet at the desired position
      siblings_without_moved = Enum.reject(siblings, &(&1.id == sheet.id))

      new_order =
        siblings_without_moved
        |> List.insert_at(new_position, updated_sheet)
        |> Enum.map(& &1.id)

      # Update positions in destination container
      new_order
      |> Enum.with_index()
      |> Enum.each(fn {sheet_id, index} ->
        update_position_only(sheet_id, index)
      end)

      # If parent changed, also reorder the source container
      if old_parent_id != new_parent_id do
        reorder_source_container(project_id, old_parent_id)
      end

      # Return the sheet with updated position
      Repo.get!(Sheet, sheet.id)
    end)
  end

  defp update_sheet_position({sheet_id, index}, project_id, parent_id) do
    query =
      from(s in Sheet,
        where: s.id == ^sheet_id and s.project_id == ^project_id and is_nil(s.deleted_at)
      )

    query = add_parent_filter(query, parent_id)
    Repo.update_all(query, set: [position: index])
  end

  defp update_position_only(sheet_id, position) do
    from(s in Sheet, where: s.id == ^sheet_id and is_nil(s.deleted_at))
    |> Repo.update_all(set: [position: position])
  end

  defp reorder_source_container(project_id, parent_id) do
    list_sheets_by_parent(project_id, parent_id)
    |> Enum.with_index()
    |> Enum.each(fn {sheet, index} ->
      update_position_only(sheet.id, index)
    end)
  end

  defp add_parent_filter(query, nil), do: where(query, [s], is_nil(s.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [s], s.parent_id == ^parent_id)

  defp list_sheets_by_parent(project_id, parent_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end
end

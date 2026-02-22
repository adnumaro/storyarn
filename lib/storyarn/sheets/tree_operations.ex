defmodule Storyarn.Sheets.TreeOperations do
  @moduledoc false

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
    SharedTree.reorder(Sheet, project_id, parent_id, sheet_ids, &list_sheets_by_parent/2)
  end

  @doc """
  Moves a sheet to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It updates the sheet's parent_id, then rebuilds positions for all affected containers.

  Returns `{:ok, sheet}` with the moved sheet or `{:error, reason}`.
  """
  def move_sheet_to_position(%Sheet{} = sheet, new_parent_id, new_position) do
    if new_parent_id && descendant?(new_parent_id, sheet.id) do
      {:error, :cyclic_parent}
    else
      SharedTree.move_to_position(
        Sheet,
        sheet,
        new_parent_id,
        new_position,
        &list_sheets_by_parent/2
      )
    end
  end

  defp list_sheets_by_parent(project_id, parent_id) do
    SharedTree.list_by_parent(Sheet, project_id, parent_id)
  end

  # Walks upward from id through parent_id links.
  # Returns true if potential_ancestor_id is found in the chain.
  defp descendant?(id, potential_ancestor_id, depth \\ 0)
  defp descendant?(_id, _potential_ancestor_id, depth) when depth > 100, do: false

  defp descendant?(id, potential_ancestor_id, depth) do
    case Repo.get(Sheet, id) do
      nil -> false
      %Sheet{id: ^potential_ancestor_id} -> true
      %Sheet{parent_id: nil} -> false
      %Sheet{parent_id: parent_id} -> descendant?(parent_id, potential_ancestor_id, depth + 1)
    end
  end
end

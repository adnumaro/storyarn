defmodule Storyarn.Sheets.Editor.Commands.SheetMovement do
  @moduledoc """
  Coordinates an atomic Sheet move with inheritance and localization repair.

  The lock order and transaction boundaries intentionally match the legacy
  facade workflow; only its ownership moved into the editor capability.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor.Commands.Inheritance
  alias Storyarn.Sheets.Editor.Commands.Tree
  alias Storyarn.Sheets.Editor.Data.ProjectRecord
  alias Storyarn.Sheets.Localization
  alias Storyarn.Sheets.Sheet

  @spec move_to_position(Sheet.t(), integer() | nil, integer()) ::
          {:ok, Sheet.t()} | {:error, term()}
  def move_to_position(%Sheet{} = sheet, new_parent_id, new_position) do
    fn ->
      case Repo.one(
             from(project in ProjectRecord,
               where: project.id == ^sheet.project_id,
               lock: "FOR UPDATE"
             )
           ) do
        %ProjectRecord{deleted_at: nil} -> :ok
        %ProjectRecord{} -> Repo.rollback(:project_not_active)
        nil -> Repo.rollback(:project_not_found)
      end

      current_sheet =
        Repo.one(
          from(current in Sheet,
            where:
              current.id == ^sheet.id and current.project_id == ^sheet.project_id and
                is_nil(current.deleted_at),
            lock: "FOR UPDATE"
          )
        ) || Repo.rollback(:sheet_not_active)

      move_in_transaction(current_sheet, new_parent_id, new_position)
    end
    |> Repo.transaction()
    |> Collaboration.broadcast_dashboard_result(sheet.project_id, :sheets)
  end

  defp move_in_transaction(sheet, new_parent_id, new_position) do
    with {:ok, moved_sheet} <- Tree.move_sheet_to_position(sheet, new_parent_id, new_position),
         {:ok, %{sheet_ids: affected_sheet_ids}} <-
           Inheritance.recalculate_on_move_with_sheet_ids(moved_sheet),
         :ok <- Localization.extract_sheet_blocks_for_sheets(affected_sheet_ids) do
      moved_sheet
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end

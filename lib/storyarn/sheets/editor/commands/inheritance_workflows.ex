defmodule Storyarn.Sheets.Editor.Commands.InheritanceWorkflows do
  @moduledoc """
  Transactional application workflows around Sheet property inheritance.

  Core inheritance mechanics remain in `Inheritance`; this module coordinates
  localization projection and dashboard invalidation at the capability edge.
  """

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Editor.Commands.Inheritance
  alias Storyarn.Sheets.Localization
  alias Storyarn.Sheets.Sheet

  def propagate_to_descendants(%Block{} = parent_block, selected_sheet_ids) do
    fn ->
      {:ok, count} = Inheritance.propagate_to_descendants(parent_block, selected_sheet_ids)

      case Localization.extract_block_tree(parent_block.id) do
        :ok -> count
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_block_dashboard_result(parent_block)
  end

  def detach_block(%Block{} = block) do
    block
    |> Inheritance.detach_block()
    |> broadcast_block_dashboard_result(block)
  end

  def reattach_block(%Block{} = block) do
    fn -> reattach_block_in_transaction(block) end
    |> Repo.transaction()
    |> broadcast_block_dashboard_result(block)
  end

  def hide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    sheet
    |> Inheritance.hide_for_children(ancestor_block_id)
    |> broadcast_sheet_dashboard_result(sheet)
  end

  def unhide_for_children(%Sheet{} = sheet, ancestor_block_id) do
    sheet
    |> Inheritance.unhide_for_children(ancestor_block_id)
    |> broadcast_sheet_dashboard_result(sheet)
  end

  defp reattach_block_in_transaction(block) do
    with {:ok, updated_block} <- Inheritance.reattach_block(block),
         :ok <- Localization.extract_block(updated_block) do
      updated_block
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp broadcast_block_dashboard_result({:ok, _value} = result, %Block{} = block) do
    case Repo.get(Sheet, block.sheet_id) do
      %Sheet{project_id: project_id} ->
        Collaboration.broadcast_dashboard_change(project_id, :sheets)

      nil ->
        :ok
    end

    result
  end

  defp broadcast_block_dashboard_result(result, _block), do: result

  defp broadcast_sheet_dashboard_result({:ok, _value} = result, %Sheet{project_id: project_id}) do
    Collaboration.broadcast_dashboard_change(project_id, :sheets)
    result
  end

  defp broadcast_sheet_dashboard_result(result, _sheet), do: result
end

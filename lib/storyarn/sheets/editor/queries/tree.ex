defmodule Storyarn.Sheets.Editor.Queries.Tree do
  @moduledoc """
  Read-only hierarchy helpers used by Sheet editor queries and commands.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet

  def next_position(project_id, parent_id) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      select: max(sheet.position)
    )
    |> add_parent_filter(parent_id)
    |> Repo.one()
    |> case do
      nil -> 0
      max_position -> max_position + 1
    end
  end

  def descendant?(id, potential_ancestor_id, depth \\ 0)
  def descendant?(_id, _potential_ancestor_id, depth) when depth > 100, do: false

  def descendant?(id, potential_ancestor_id, depth) do
    case Repo.get(Sheet, id) do
      nil -> false
      %{id: ^potential_ancestor_id} -> true
      %{parent_id: nil} -> false
      %{parent_id: parent_id} -> descendant?(parent_id, potential_ancestor_id, depth + 1)
    end
  end

  def add_parent_filter(query, nil), do: where(query, [sheet], is_nil(sheet.parent_id))
  def add_parent_filter(query, parent_id), do: where(query, [sheet], sheet.parent_id == ^parent_id)

  def build_from_flat_list(items, root_parent_id \\ nil) do
    grouped = Enum.group_by(items, & &1.parent_id)
    build_subtree(grouped, root_parent_id)
  end

  defp build_subtree(grouped, parent_id) do
    Enum.map(Map.get(grouped, parent_id) || [], fn item ->
      Map.put(item, :children, build_subtree(grouped, item.id))
    end)
  end
end

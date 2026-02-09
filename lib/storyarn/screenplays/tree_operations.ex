defmodule Storyarn.Screenplays.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Screenplays.Screenplay

  @doc """
  Reorders screenplays within a parent container.
  Updates all positions in a single transaction.
  """
  def reorder_screenplays(project_id, parent_id, screenplay_ids) when is_list(screenplay_ids) do
    Repo.transaction(fn ->
      screenplay_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(&update_screenplay_position(&1, project_id, parent_id))

      list_screenplays_by_parent(project_id, parent_id)
    end)
  end

  @doc """
  Moves a screenplay to a new parent at a specific position.
  """
  def move_screenplay_to_position(%Screenplay{} = screenplay, new_parent_id, new_position) do
    Repo.transaction(fn ->
      old_parent_id = screenplay.parent_id
      project_id = screenplay.project_id

      updated =
        case screenplay
             |> Screenplay.move_changeset(%{parent_id: new_parent_id, position: new_position})
             |> Repo.update() do
          {:ok, s} -> s
          {:error, changeset} -> Repo.rollback(changeset)
        end

      # Rebuild positions in destination container
      siblings = list_screenplays_by_parent(project_id, new_parent_id)
      siblings_without_moved = Enum.reject(siblings, &(&1.id == screenplay.id))

      siblings_without_moved
      |> List.insert_at(new_position, updated)
      |> Enum.map(& &1.id)
      |> Enum.with_index()
      |> Enum.each(fn {id, index} -> update_position_only(id, index) end)

      # If parent changed, reorder source container
      if old_parent_id != new_parent_id do
        reorder_source_container(project_id, old_parent_id)
      end

      Repo.get!(Screenplay, screenplay.id)
    end)
  end

  defp list_screenplays_by_parent(project_id, parent_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_of_id),
      order_by: [asc: s.position, asc: s.name]
    )
    |> add_parent_filter(parent_id)
    |> Repo.all()
  end

  defp update_screenplay_position({screenplay_id, index}, project_id, parent_id) do
    from(s in Screenplay,
      where: s.id == ^screenplay_id and s.project_id == ^project_id and is_nil(s.deleted_at)
    )
    |> add_parent_filter(parent_id)
    |> Repo.update_all(set: [position: index])
  end

  defp update_position_only(screenplay_id, position) do
    from(s in Screenplay, where: s.id == ^screenplay_id and is_nil(s.deleted_at))
    |> Repo.update_all(set: [position: position])
  end

  defp reorder_source_container(project_id, parent_id) do
    list_screenplays_by_parent(project_id, parent_id)
    |> Enum.with_index()
    |> Enum.each(fn {s, index} -> update_position_only(s.id, index) end)
  end

  defp add_parent_filter(query, nil), do: where(query, [s], is_nil(s.parent_id))
  defp add_parent_filter(query, parent_id), do: where(query, [s], s.parent_id == ^parent_id)
end

defmodule Storyarn.Screenplays.TreeOperations do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Shared.TreeOperations, as: SharedTree

  @doc """
  Reorders screenplays within a parent container.
  Updates all positions in a single transaction.
  """
  def reorder_screenplays(project_id, parent_id, screenplay_ids) when is_list(screenplay_ids) do
    SharedTree.reorder(
      Screenplay,
      project_id,
      parent_id,
      screenplay_ids,
      &list_screenplays_by_parent/2
    )
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
      |> Enum.each(fn {id, index} ->
        SharedTree.update_position_only(Screenplay, id, index)
      end)

      # If parent changed, reorder source container
      if old_parent_id != new_parent_id do
        SharedTree.reorder_source_container(
          Screenplay,
          project_id,
          old_parent_id,
          &list_screenplays_by_parent/2
        )
      end

      Repo.get!(Screenplay, screenplay.id)
    end)
  end

  defp list_screenplays_by_parent(project_id, parent_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_of_id),
      order_by: [asc: s.position, asc: s.name]
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.all()
  end
end

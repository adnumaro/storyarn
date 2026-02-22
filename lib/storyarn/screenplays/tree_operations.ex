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
    if new_parent_id && descendant?(new_parent_id, screenplay.id) do
      {:error, :cyclic_parent}
    else
      SharedTree.move_to_position(
        Screenplay,
        screenplay,
        new_parent_id,
        new_position,
        &list_screenplays_by_parent/2
      )
    end
  end

  # Walks upward from id through parent_id links.
  # Returns true if potential_ancestor_id is found in the chain.
  defp descendant?(id, potential_ancestor_id, depth \\ 0)
  defp descendant?(_id, _potential_ancestor_id, depth) when depth > 100, do: false

  defp descendant?(id, potential_ancestor_id, depth) do
    case Repo.get(Screenplay, id) do
      nil ->
        false

      %Screenplay{id: ^potential_ancestor_id} ->
        true

      %Screenplay{parent_id: nil} ->
        false

      %Screenplay{parent_id: parent_id} ->
        descendant?(parent_id, potential_ancestor_id, depth + 1)
    end
  end

  # Keeps local filter because screenplays need the `is_nil(s.draft_of_id)` filter
  # that can't be expressed in the generic SharedTree.list_by_parent/3.
  defp list_screenplays_by_parent(project_id, parent_id) do
    from(s in Screenplay,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_of_id),
      order_by: [asc: s.position, asc: s.name]
    )
    |> SharedTree.add_parent_filter(parent_id)
    |> Repo.all()
  end
end

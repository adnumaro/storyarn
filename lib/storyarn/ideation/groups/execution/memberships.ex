defmodule Storyarn.Ideation.Groups.Execution.Memberships do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Membership
  alias Storyarn.Ideation.Ideas
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def current(group_id),
    do: Repo.all(from m in Membership, where: m.group_id == ^group_id and is_nil(m.removed_at), order_by: m.idea_id)

  def validate(session_id, group_id, ids) do
    sources = Ideas.group_sources(session_id, ids)

    occupied? =
      Repo.exists?(
        from m in Membership,
          where: m.idea_id in ^ids and m.group_id != ^group_id and is_nil(m.removed_at)
      )

    cond do
      Enum.map(sources, & &1.idea_id) != ids -> {:error, :invalid_group_members}
      occupied? -> {:error, :already_grouped}
      true -> {:ok, sources}
    end
  end

  def replace(group, actor_id, sources, pinned \\ %{}) do
    previous = current(group.id)
    ids = Enum.map(sources, & &1.idea_id)
    removed = for member <- previous, member.idea_id not in ids, do: member.id

    Repo.update_all(from(m in Membership, where: m.id in ^removed),
      set: [removed_at: %{TimeHelpers.now() | microsecond: {0, 6}}]
    )

    previous_ids = Enum.map(previous, & &1.idea_id)
    retained = retained_sources(group.id, ids -- previous_ids)

    for source <- sources, source.idea_id not in previous_ids do
      Repo.insert!(%Membership{
        session_id: group.session_id,
        group_id: group.id,
        idea_id: source.idea_id,
        source_revision:
          Map.get(pinned, to_string(source.idea_id), Map.get(retained, source.idea_id, source.source_revision)),
        actor_id: actor_id
      })
    end

    current(group.id)
  end

  # Reattaching the same identity (including browser undo) retains the source
  # revision already used by this group's synthesis, even if its note was edited.
  defp retained_sources(group_id, ids) do
    from(m in Membership,
      where: m.group_id == ^group_id and m.idea_id in ^ids and not is_nil(m.removed_at),
      distinct: m.idea_id,
      order_by: [asc: m.idea_id, desc: m.id],
      select: {m.idea_id, m.source_revision}
    )
    |> Repo.all()
    |> Map.new()
  end

  def remove(group_id) do
    Repo.update_all(from(m in Membership, where: m.group_id == ^group_id and is_nil(m.removed_at)),
      set: [removed_at: %{TimeHelpers.now() | microsecond: {0, 6}}]
    )
  end

  def snapshot(members), do: Map.new(members, &{to_string(&1.idea_id), &1.source_revision})
end

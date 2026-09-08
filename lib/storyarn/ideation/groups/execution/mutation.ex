defmodule Storyarn.Ideation.Groups.Execution.Mutation do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Execution.Memberships
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Revision
  alias Storyarn.Ideation.Ideas
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def create(access, attrs, key, fingerprint) do
    count = Repo.aggregate(from(g in Group, where: g.session_id == ^access.session_id and is_nil(g.deleted_at)), :count)

    with true <- count < 500,
         {:ok, sources} <- Memberships.validate(access.session_id, 0, attrs.idea_ids) do
      group =
        Repo.insert!(%Group{
          session_id: access.session_id,
          author_id: access.user_id,
          title: attrs.title,
          synthesis: attrs.synthesis,
          canvas: attrs.canvas
        })

      members = Memberships.replace(group, access.user_id, sources)
      record(group, access.user_id, "create", key, fingerprint, members)
    else
      false -> {:error, :group_limit_reached}
      error -> error
    end
  end

  def update(access, id, expected, attrs, key, fingerprint) do
    with {:ok, group} <- current(access, id, expected),
         {:ok, canvas} <- update_canvas(group, attrs),
         {:ok, members} <- update_members(group, access.user_id, attrs) do
      changes = attrs |> Map.take([:title, :synthesis]) |> Map.merge(%{canvas: canvas, version: group.version + 1})
      updated = group |> change(changes) |> Repo.update!()
      record(updated, access.user_id, "update", key, fingerprint, members)
    end
  end

  def move(access, id, expected, attrs, key, fingerprint) do
    with {:ok, group} <- current(access, id, expected) do
      members = Memberships.current(group.id)
      dx = attrs.x - group.canvas["x"]
      dy = attrs.y - group.canvas["y"]

      with :ok <- Ideas.move_group_sources(access, Enum.map(members, & &1.idea_id), attrs.member_versions, dx, dy) do
        canvas = Map.merge(group.canvas, %{"x" => attrs.x, "y" => attrs.y})
        updated = group |> change(canvas: canvas, version: group.version + 1) |> Repo.update!()
        record(updated, access.user_id, "move", key, fingerprint, members)
      end
    end
  end

  def delete(access, id, expected, key, fingerprint) do
    with {:ok, group} <- current(access, id, expected) do
      members = Memberships.current(group.id)

      updated =
        group
        |> change(deleted_at: %{TimeHelpers.now() | microsecond: {0, 6}}, version: group.version + 1)
        |> Repo.update!()

      Memberships.remove(group.id)
      record(updated, access.user_id, "delete", key, fingerprint, members)
    end
  end

  def restore(access, id, expected, attrs, key, fingerprint) do
    with {:ok, group} <- current(access, id, expected, true),
         %Revision{operation: "delete", actor_id: actor_id} = deletion <-
           Repo.get_by(Revision, group_id: id, number: expected),
         true <- actor_id == access.user_id and DateTime.compare(group.deleted_at, attrs.deleted_at) == :eq,
         sources = Ideas.group_sources(access.session_id, deletion.idea_ids),
         true <- Enum.map(sources, & &1.idea_id) == attrs.idea_ids,
         {:ok, _} <- Memberships.validate(access.session_id, id, attrs.idea_ids) do
      updated = group |> change(deleted_at: nil, version: group.version + 1) |> Repo.update!()
      members = Memberships.replace(updated, access.user_id, sources, pinned: deletion.sources)
      record(updated, access.user_id, "restore", key, fingerprint, members)
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_group}
    end
  end

  defp current(access, id, expected, deleted? \\ false) do
    # The session contribution lock serializes every group mutation and recovery.
    query = from g in Group, where: g.id == ^id and g.session_id == ^access.session_id
    query = if deleted?, do: where(query, [g], not is_nil(g.deleted_at)), else: where(query, [g], is_nil(g.deleted_at))

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %{version: ^expected} = group -> {:ok, group}
      _ -> {:error, :stale_group}
    end
  end

  # Detaching and undoing detachment reposition only the independent synthesis.
  # A populated group's normal movement must enter the atomic Ideas placement port.
  defp update_canvas(group, %{canvas: canvas} = attrs) do
    current_ids = group.id |> Memberships.current() |> Enum.map(& &1.idea_id)
    current_empty? = Ideas.group_sources(group.session_id, current_ids) == []

    if current_empty? or Map.get(attrs, :idea_ids) == [],
      do: {:ok, Map.merge(group.canvas, canvas)},
      else: {:error, :invalid_canvas}
  end

  defp update_canvas(group, _), do: {:ok, group.canvas}

  defp update_members(group, actor_id, %{idea_ids: ids}) do
    with {:ok, sources} <- Memberships.validate(group.session_id, group.id, ids),
         do: {:ok, Memberships.replace(group, actor_id, sources, retain_hidden: ids != [])}
  end

  defp update_members(group, _, _), do: {:ok, Memberships.current(group.id)}

  defp record(group, actor_id, operation, key, fingerprint, members) do
    Repo.insert!(%Revision{
      session_id: group.session_id,
      group_id: group.id,
      actor_id: actor_id,
      number: group.version,
      operation: operation,
      request_key: key,
      fingerprint: fingerprint,
      title: group.title,
      synthesis: group.synthesis,
      canvas: group.canvas,
      idea_ids: Enum.map(members, & &1.idea_id),
      sources: Memberships.snapshot(members),
      deleted_at: group.deleted_at
    })

    {:ok, group}
  end
end

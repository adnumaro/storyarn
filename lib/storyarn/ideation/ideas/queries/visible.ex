defmodule Storyarn.Ideation.Ideas.Queries.Visible do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  # Choose the authorized revision in SQL, before decrypting any content.
  def query(session_id, actor_id) do
    from i in Idea,
      join: r in Revision,
      on:
        r.idea_id == i.id and
          r.number ==
            fragment("CASE WHEN ? = ? THEN ? ELSE ? END", i.author_id, ^actor_id, i.revision, i.published_revision),
      left_join: source in Publication,
      on: source.idea_id == i.source_idea_id and source.revision == i.source_revision,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == i.session_id,
      where:
        i.session_id == ^session_id and is_nil(i.deleted_at) and
          (i.author_id == ^actor_id or not s.private_mode),
      select: {i, r, not is_nil(source.id)}
  end

  def get(session_id, idea_id, actor_id) when valid_id(idea_id) do
    case session_id |> query(actor_id) |> where([i], i.id == ^idea_id) |> Repo.one() do
      {idea, revision, source_published?} ->
        {:ok, View.idea(idea, revision, actor_id, source_published?, visible_links(idea, actor_id))}

      nil ->
        {:error, :not_found}
    end
  end

  def get(_session_id, _idea_id, _actor_id), do: {:error, :not_found}

  def visible_links(idea, actor_id) do
    ids = Map.get(idea.canvas, "links", [])

    visible_link_ids(idea.session_id, actor_id, ids)
  end

  def visible_link_ids(_session_id, _actor_id, []), do: []

  def visible_link_ids(session_id, actor_id, ids) do
    Repo.all(
      from i in Idea,
        join: s in subquery(Sessions.canvas_settings_query()),
        on: s.id == i.session_id,
        where:
          (i.author_id == ^actor_id or not s.private_mode) and
            i.id in ^ids and i.session_id == ^session_id and is_nil(i.deleted_at) and
            (i.author_id == ^actor_id or not is_nil(i.published_revision)),
        select: i.id
    )
  end

  def owned(session_id, idea_id, actor_id) when valid_id(idea_id) do
    case Repo.one(from i in Idea, where: i.session_id == ^session_id and i.id == ^idea_id and is_nil(i.deleted_at)) do
      %Idea{} = idea -> if Policy.author?(idea, actor_id), do: {:ok, idea}, else: {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def owned(_session_id, _idea_id, _actor_id), do: {:error, :not_found}
end

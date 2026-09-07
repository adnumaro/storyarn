defmodule Storyarn.Ideation.Ideas.Queries.Visible do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.Ideas.Rules.Input, only: [valid_id: 1, valid_revision: 1]

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Policy
  alias Storyarn.Ideation.Ideas.View
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
      where: i.session_id == ^session_id,
      select: {i, r, not is_nil(source.id)}
  end

  def get(session_id, idea_id, actor_id) when valid_id(idea_id) do
    case session_id |> query(actor_id) |> where([i], i.id == ^idea_id) |> Repo.one() do
      {idea, revision, source_published?} -> {:ok, View.idea(idea, revision, actor_id, source_published?)}
      nil -> {:error, :not_found}
    end
  end

  def get(_session_id, _idea_id, _actor_id), do: {:error, :not_found}

  def readable_revision(session_id, idea_id, number, actor_id) when valid_id(idea_id) and valid_revision(number) do
    query =
      from i in Idea,
        join: r in Revision,
        on: r.idea_id == i.id and r.number == ^number,
        left_join: p in Publication,
        on: p.idea_id == i.id and p.revision == r.number,
        where:
          i.session_id == ^session_id and i.id == ^idea_id and
            (i.author_id == ^actor_id or not is_nil(p.id)),
        select: {i, r}

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {idea, revision} -> {:ok, idea, revision}
    end
  end

  def readable_revision(_session_id, _idea_id, _number, _actor_id), do: {:error, :not_found}

  def owned(session_id, idea_id, actor_id) when valid_id(idea_id) do
    case Repo.get_by(Idea, session_id: session_id, id: idea_id) do
      %Idea{} = idea -> if Policy.author?(idea, actor_id), do: {:ok, idea}, else: {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def owned(_session_id, _idea_id, _actor_id), do: {:error, :not_found}
end

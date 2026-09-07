defmodule Storyarn.Ideation.Ideas.Queries.History do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Queries.Visible
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Ideas.Rules.Input
  alias Storyarn.Ideation.Ideas.View
  alias Storyarn.Repo

  def run(scope, project_id, session_id, idea_id, opts) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id),
         {:ok, idea} <- Visible.get(session_id, idea_id, actor_id),
         {:ok, limit, before_id} <- Input.page(opts) do
      query = from r in Revision, where: r.idea_id == ^idea.id, order_by: [desc: r.id], limit: ^limit
      query = if before_id, do: where(query, [r], r.id < ^before_id), else: query

      query =
        if idea.author_id == actor_id,
          do: query,
          else: join(query, :inner, [r], p in Publication, on: p.idea_id == r.idea_id and p.revision == r.number)

      {:ok, query |> Repo.all() |> Enum.map(&Map.put(View.revision(&1), :id, &1.id))}
    end
  end
end

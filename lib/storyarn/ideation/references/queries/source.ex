defmodule Storyarn.Ideation.References.Source do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.References.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Sessions

  def get(scope, project_id, session_id, idea_id)
      when valid_id(project_id) and valid_id(session_id) and (is_nil(idea_id) or valid_id(idea_id)) do
    Ideas.comment_source(scope, project_id, session_id, idea_id, [])
  end

  def get(_, _, _, _), do: {:error, :not_found}

  # Used by backlinks before pagination. These are identity-only projections;
  # private ideas never become discoverable through an inverse reference.
  def readable(query, project_id) do
    shared_ideas = from(i in subquery(Ideas.comment_sources_query()), where: i.project_id == ^project_id, select: i.id)

    from(r in query,
      join: s in subquery(Sessions.comment_sources_query()),
      on: s.id == r.session_id,
      where: s.project_id == ^project_id,
      where: is_nil(r.idea_id) or r.idea_id in subquery(shared_ideas),
      select: %{reference: r, session_name: s.name}
    )
  end
end

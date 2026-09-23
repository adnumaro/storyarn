defmodule Storyarn.Ideation.Decisions.Queries.CommentSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Sessions

  def query do
    from(d in Decision,
      join: s in subquery(Sessions.comment_sources_query()),
      on: s.id == d.session_id,
      select: %{
        id: d.id,
        project_id: s.project_id,
        session_id: s.id,
        source_type: "ideation_decision",
        recovery_identity: d.recovery_identity,
        name: fragment("concat('Decision #', ?)", d.id)
      }
    )
  end
end

defmodule Storyarn.Ideation.Ideas.Queries.CommentSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Sessions

  def query do
    from(i in Idea,
      join: s in subquery(Sessions.comment_sources_query()),
      on: s.id == i.session_id,
      join: settings in subquery(Sessions.canvas_settings_query()),
      on: settings.id == s.id,
      where: is_nil(i.deleted_at) and not is_nil(i.published_revision) and not settings.private_mode,
      select: %{
        id: i.id,
        project_id: s.project_id,
        session_id: s.id,
        source_type: "ideation_idea",
        recovery_identity: i.recovery_identity
      }
    )
  end
end

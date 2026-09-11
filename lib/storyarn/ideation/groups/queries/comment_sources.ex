defmodule Storyarn.Ideation.Groups.Queries.CommentSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Sessions

  def query do
    from(g in Group,
      join: s in subquery(Sessions.comment_sources_query()),
      on: s.id == g.session_id,
      join: settings in subquery(Sessions.canvas_settings_query()),
      on: settings.id == s.id,
      where: is_nil(g.deleted_at) and not settings.private_mode,
      select: %{
        id: g.id,
        project_id: s.project_id,
        session_id: s.id,
        source_type: "ideation_group",
        recovery_identity: g.recovery_identity
      }
    )
  end
end

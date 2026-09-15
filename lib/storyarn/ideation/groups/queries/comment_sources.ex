defmodule Storyarn.Ideation.Groups.Queries.CommentSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Sessions

  def query do
    from(g in Group,
      join: s in subquery(Sessions.comment_sources_query()),
      on: s.id == g.session_id,
      left_join: mask in subquery(Sessions.round_mask_query()),
      on: mask.id == g.round_id,
      where: is_nil(g.deleted_at) and not fragment("COALESCE(?, false)", mask.private),
      select: %{
        id: g.id,
        project_id: s.project_id,
        session_id: s.id,
        source_type: "ideation_group",
        recovery_identity: g.recovery_identity,
        name: fragment("concat('Group #', ?)", g.id)
      }
    )
  end
end

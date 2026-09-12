defmodule Storyarn.Ideation.Sessions.Queries.CommentSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Session

  # Shared identity and label only. The consumer must also authorize project access.
  def query do
    from(s in Session,
      where: is_nil(s.deleted_at),
      select: %{
        id: s.id,
        project_id: s.project_id,
        session_id: s.id,
        source_type: "ideation_session",
        recovery_identity: s.recovery_identity,
        name: s.title
      }
    )
  end
end

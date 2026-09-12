defmodule Storyarn.Ideation.Sessions.Queries.ContextualChoices do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Session

  # Contextual navigation needs lifecycle status. Keep it separate from the
  # fixed six-column comment-source union shared by sessions, ideas and groups.
  def query do
    from(s in Session,
      where: is_nil(s.deleted_at),
      select: %{id: s.id, project_id: s.project_id, name: s.title, status: s.status}
    )
  end
end

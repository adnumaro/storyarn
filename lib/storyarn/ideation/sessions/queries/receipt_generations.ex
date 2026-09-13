defmodule Storyarn.Ideation.Sessions.Queries.ReceiptGenerations do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Session

  # Identity-only projection for an already authorized receipt lookup. Replaced
  # generations remain command fences and are not ordinary readable sessions.
  def query do
    from s in Session,
      select: %{
        id: s.id,
        project_id: s.project_id,
        recovery_identity: s.recovery_identity,
        deleted_at: s.deleted_at
      }
  end
end

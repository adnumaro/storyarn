defmodule Storyarn.Ideation.Sessions.Queries.ContextualReceipts do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Revision
  alias Storyarn.Ideation.Sessions.Session

  # Identity-only projections for the authorized References transaction. Replaced
  # sources remain receipt fences; they are never ordinary session choices.
  def sources do
    from(s in Session, select: %{id: s.id, project_id: s.project_id, deleted_at: s.deleted_at})
  end

  def links do
    from(r in Revision,
      where: r.action == :context_linked,
      select: %{
        session_id: r.session_id,
        actor_id: r.actor_id,
        request_key: r.snapshot["contextual_request"]["key"],
        fingerprint: r.snapshot["contextual_request"]["fingerprint"],
        reference_identity: r.snapshot["contextual_request"]["reference_identity"]
      }
    )
  end
end

defmodule Storyarn.Ideation.Sessions.Queries.CanvasSettings do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Session
  # Consumer-local projection for Ideas' authorized SQL joins. No session schema escapes.
  def query do
    from s in Session,
      where: is_nil(s.deleted_at),
      select: %{id: s.id, private_mode: fragment("COALESCE(?->>'private_mode', 'false') = 'true'", s.configuration)}
  end
end

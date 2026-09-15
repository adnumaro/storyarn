defmodule Storyarn.Ideation.Sessions.Queries.RoundMask do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Round

  # Consumer-local projection for authorized SQL joins: which rounds currently
  # hide other people's contributions. No round schema escapes.
  def query do
    from r in Round, select: %{id: r.id, session_id: r.session_id, private: r.private}
  end
end

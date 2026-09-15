defmodule Storyarn.Ideation.Ideas.Queries.GroupSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  # Closed capability projection: no text, unpublished revisions or private sources.
  def list(session_id, ids) do
    from(i in Idea,
      left_join: mask in subquery(Sessions.round_mask_query()),
      on: mask.id == i.round_id,
      where:
        i.session_id == ^session_id and i.id in ^ids and is_nil(i.deleted_at) and
          not is_nil(i.published_revision) and not fragment("COALESCE(?, false)", mask.private),
      order_by: i.id,
      select: %{idea_id: i.id, source_revision: i.published_revision, round_id: i.round_id, canvas: i.canvas}
    )
    |> Repo.all()
    |> Enum.map(fn source -> %{source | canvas: Map.take(source.canvas, ~w(x y width color shape version))} end)
  end
end

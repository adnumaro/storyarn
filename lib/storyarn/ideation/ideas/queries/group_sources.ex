defmodule Storyarn.Ideation.Ideas.Queries.GroupSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  # Closed capability projection: no text, unpublished revisions or private sources.
  def list(session_id, ids) do
    from(i in Idea,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == i.session_id,
      where:
        i.session_id == ^session_id and i.id in ^ids and is_nil(i.deleted_at) and
          not is_nil(i.published_revision) and not s.private_mode,
      order_by: i.id,
      select: %{idea_id: i.id, source_revision: i.published_revision, canvas: i.canvas}
    )
    |> Repo.all()
    |> Enum.map(fn source -> %{source | canvas: Map.take(source.canvas, ~w(x y width color version))} end)
  end
end

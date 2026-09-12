defmodule Storyarn.Ideation.Groups.Queries.DecisionSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Revision
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def list(session_id, ids), do: Repo.all(from g in query(session_id), where: g.id in ^ids)

  def search(session_id, page) do
    query = query(session_id)
    query = if page.before_id, do: where(query, [g], g.id < ^page.before_id), else: query
    Repo.all(from g in query, order_by: [desc: g.id], limit: 201)
  end

  defp query(session_id) do
    from g in Group,
      join: r in Revision,
      on: r.group_id == g.id and r.number == g.version,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == g.session_id,
      where: g.session_id == ^session_id and is_nil(g.deleted_at) and not s.private_mode,
      select: %{
        type: "group",
        id: g.id,
        identity: g.recovery_identity,
        version: r.number,
        author_id: g.author_id,
        title: r.title,
        body: r.synthesis
      }
  end
end

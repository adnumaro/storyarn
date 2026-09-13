defmodule Storyarn.Ideation.Ideas.Queries.DecisionSources do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def list(session_id, ids), do: Repo.all(from i in query(session_id), where: i.id in ^ids)

  def search(session_id, page) do
    query = query(session_id)
    query = if page.before_id, do: where(query, [i], i.id < ^page.before_id), else: query
    Repo.all(from i in query, order_by: [desc: i.id], limit: 201)
  end

  # Select the published revision in SQL; even an author's own unpublished head
  # must never be used as the source of a shared proposal.
  defp query(session_id) do
    from i in Idea,
      join: r in Revision,
      on: r.idea_id == i.id and r.number == i.published_revision,
      join: s in subquery(Sessions.canvas_settings_query()),
      on: s.id == i.session_id,
      where: i.session_id == ^session_id and is_nil(i.deleted_at) and not s.private_mode,
      select: %{
        type: "idea",
        id: i.id,
        identity: i.recovery_identity,
        version: r.number,
        author_id: i.author_id,
        title: r.title,
        body: r.body
      }
  end
end

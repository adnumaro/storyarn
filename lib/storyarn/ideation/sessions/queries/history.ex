defmodule Storyarn.Ideation.Sessions.Queries.History do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Queries.Page
  alias Storyarn.Ideation.Sessions.Revision
  alias Storyarn.Repo

  def run(scope, project_id, session_id, opts) do
    with {:ok, session} <- Get.run(scope, project_id, session_id),
         {:ok, limit, before_id} <- Page.options(opts) do
      query = from r in Revision, where: r.session_id == ^session.id, order_by: [desc: r.id], limit: ^limit
      query = if before_id, do: where(query, [r], r.id < ^before_id), else: query
      {:ok, Repo.all(query)}
    end
  end
end

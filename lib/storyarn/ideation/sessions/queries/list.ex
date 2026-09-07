defmodule Storyarn.Ideation.Sessions.Queries.List do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Queries.Page
  alias Storyarn.Ideation.Sessions.Queries.ProjectAccess
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def run(scope, project_id, opts) do
    with :ok <- ProjectAccess.authorize(scope, project_id),
         status when status in [:open, :archived, :all] <- Keyword.get(opts, :status, :open),
         {:ok, limit, before_id} <- Page.options(opts) do
      query = from s in Session, where: s.project_id == ^project_id, order_by: [desc: s.id], limit: ^limit
      query = if status == :all, do: query, else: where(query, [s], s.status == ^status)
      query = if before_id, do: where(query, [s], s.id < ^before_id), else: query
      {:ok, Repo.all(query)}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_options}
    end
  end
end

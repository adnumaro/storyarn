defmodule Storyarn.Ideation.Decisions.Queries.Project do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Catalog
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  @session_limit 200

  @doc "The readable session that holds a decision, for links that name only the decision."
  def session(scope, project_id, decision_id) when is_integer(decision_id) and decision_id > 0 do
    with session_id when is_integer(session_id) <-
           Repo.one(from d in Decision, where: d.id == ^decision_id, select: d.session_id),
         {:ok, session} <- Sessions.get_session(scope, project_id, session_id) do
      {:ok, session.id}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def session(_scope, _project_id, _decision_id), do: {:error, :not_found}

  @doc """
  Every decision of the project's readable sessions, grouped by session, newest
  session first. Each session is read through its own catalog, so access and
  source visibility match the panel.
  """
  def list(scope, project_id) do
    with {:ok, sessions} <- Sessions.list_sessions(scope, project_id, status: :all, limit: @session_limit) do
      ids = Enum.map(sessions, & &1.id)

      deciding =
        MapSet.new(Repo.all(from d in Decision, where: d.session_id in ^ids, distinct: true, select: d.session_id))

      {:ok,
       for session <- sessions,
           MapSet.member?(deciding, session.id),
           {:ok, decisions} <- [Catalog.list(scope, project_id, session.id)] do
         %{session: %{id: session.id, title: session.title, status: session.status}, decisions: decisions}
       end}
    end
  end
end

defmodule Storyarn.Ideation.Sessions.Queries.Get do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def run(scope, project_id, session_id) when is_integer(session_id) and session_id > 0 do
    with {:ok, _access} <- ProjectAccess.read(scope, project_id),
         %Session{} = session <-
           Repo.one(from s in Session, where: s.project_id == ^project_id and s.id == ^session_id) do
      {:ok, session}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(_scope, _project_id, _session_id), do: {:error, :not_found}
end

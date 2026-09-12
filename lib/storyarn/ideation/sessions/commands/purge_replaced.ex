defmodule Storyarn.Ideation.Sessions.Commands.PurgeReplaced do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Events.Invalidation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  # Destructive, explicit owner action. Never called by restore or retention jobs.
  # Descendants are removed by the session-owned foreign-key cascades. Existing
  # archives have an independent lifecycle and retain their captured bytes.
  def run(scope, project_id, session_id, revision)
      when is_integer(session_id) and session_id > 0 and is_integer(revision) and revision > 0 do
    fn ->
      with {:ok, access} <- ProjectAccess.write(scope, project_id),
           true <- access.owner?,
           %Session{} = session <-
             Repo.one(from s in Session, where: s.project_id == ^project_id and s.id == ^session_id, lock: "FOR UPDATE"),
           false <- is_nil(session.deleted_at),
           true <- session.revision == revision or {:error, :stale_revision},
           {:ok, _session} <- Repo.delete(session) do
        {:ok, :purged}
      else
        nil -> {:error, :not_found}
        false -> {:error, :unauthorized}
        true -> {:error, :session_not_replaced}
        {:error, reason} -> {:error, reason}
      end
    end
    |> Repo.transact()
    |> Invalidation.notify(project_id, :sources)
  end

  def run(_, _, _, _), do: {:error, :invalid_revision}
end

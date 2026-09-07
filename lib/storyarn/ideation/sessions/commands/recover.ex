defmodule Storyarn.Ideation.Sessions.Commands.Recover do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision)
      when is_integer(session_id) and session_id > 0 and is_integer(revision) and revision > 0 do
    Repo.transact(fn ->
      with {:ok, access} <- ProjectAccess.write(scope, project_id),
           %Session{} = session <-
             Repo.one(
               from s in Session,
                 where: s.project_id == ^project_id and s.id == ^session_id and not is_nil(s.deleted_at),
                 lock: "FOR UPDATE"
             ),
           true <- access.owner? or session.facilitator_id == access.user_id,
           true <- session.revision == revision or {:error, :stale_revision},
           {:ok, recovered} <-
             session
             |> change(deleted_at: nil, status: :archived, archived_at: TimeHelpers.now(), revision: revision + 1)
             |> Repo.update() do
        Mutation.record(recovered, access.user_id, :recovered)
      else
        nil -> {:error, :not_found}
        false -> {:error, :unauthorized}
        {:error, _} = error -> error
      end
    end)
  end

  def run(_, _, _, _), do: {:error, :invalid_revision}
end

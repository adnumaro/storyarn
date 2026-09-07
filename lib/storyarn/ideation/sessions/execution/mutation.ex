defmodule Storyarn.Ideation.Sessions.Execution.Mutation do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Events.Invalidation
  alias Storyarn.Ideation.Sessions.Revision
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def create(scope, project_id, callback) do
    fn ->
      with {:ok, access} <- ProjectAccess.write(scope, project_id) do
        callback.(access)
      end
    end
    |> Repo.transact()
    |> Invalidation.notify(project_id)
  end

  def run(scope, project_id, session_id, revision, callback) when is_integer(revision) and revision > 0 do
    fn ->
      with {:ok, access} <- ProjectAccess.write(scope, project_id),
           %Session{} = session <- lock_session(project_id, session_id),
           :ok <- authorize_manager(session, access),
           :ok <- check_revision(session, revision) do
        callback.(session, access)
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
    |> Repo.transact()
    |> Invalidation.notify(project_id)
  end

  def run(_scope, _project_id, _session_id, _revision, _callback), do: {:error, :invalid_revision}

  # Only called inside the command transaction: the session and audit record
  # either both commit or neither does. No asynchronous history write.
  def record(session, actor_id, action) do
    snapshot = %{
      "title" => session.title,
      "objective" => session.objective,
      "context" => session.context,
      "status" => Atom.to_string(session.status),
      "facilitator_id" => session.facilitator_id,
      "decision_owner_id" => session.decision_owner_id,
      "configuration_version" => session.configuration_version,
      "configuration" => Ecto.embedded_dump(session.configuration, :json)
    }

    Repo.insert!(%Revision{
      session_id: session.id,
      actor_id: actor_id,
      number: session.revision,
      action: action,
      snapshot: snapshot
    })

    {:ok, session}
  end

  defp lock_session(project_id, session_id) when is_integer(session_id) and session_id > 0 do
    Repo.one(
      from s in Session,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and s.id == ^session_id,
        lock: "FOR UPDATE"
    )
  end

  defp lock_session(_project_id, _session_id), do: nil

  defp authorize_manager(session, access) do
    if access.owner? or session.facilitator_id == access.user_id, do: :ok, else: {:error, :unauthorized}
  end

  defp check_revision(%{revision: revision}, revision), do: :ok
  defp check_revision(_session, _revision), do: {:error, :stale_revision}
end

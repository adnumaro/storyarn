defmodule Storyarn.Ideation.Sessions.Execution.ContributionAccess do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Repo

  def lock(scope, project_id, session_id)
      when is_integer(session_id) and session_id > 0 and session_id <= 9_223_372_036_854_775_807 do
    if Repo.in_transaction?() do
      with {:ok, access} <- ProjectAccess.write(scope, project_id),
           %Session{} = session <-
             Repo.one(
               from s in Session,
                 where: s.project_id == ^project_id and is_nil(s.deleted_at) and s.id == ^session_id,
                 lock: "FOR UPDATE"
             ),
           :open <- session.status do
        {:ok,
         Map.merge(access, %{
           session_id: session.id,
           session_revision: session.revision,
           facilitator_id: session.facilitator_id,
           configuration: Ecto.embedded_dump(session.configuration, :json),
           configuration_version: session.configuration_version
         })}
      else
        nil -> {:error, :not_found}
        :archived -> {:error, :session_archived}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :contribution_transaction_required}
    end
  end

  def lock(_scope, _project_id, _session_id), do: {:error, :not_found}
end

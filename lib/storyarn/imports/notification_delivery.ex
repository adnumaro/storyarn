defmodule Storyarn.Imports.NotificationDelivery do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Notifications
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @type locked_context :: %{
          project_id: pos_integer(),
          requester_id: pos_integer() | nil,
          project: Project.t() | nil,
          requester: User.t() | nil
        }

  @doc false
  @spec lock_context(ProjectImportAttempt.t()) :: locked_context()
  def lock_context(%ProjectImportAttempt{} = attempt) do
    ensure_inside_transaction!()

    project =
      Project
      |> where([project], project.id == ^attempt.project_id)
      |> lock("FOR SHARE")
      |> Repo.one()

    build_context(attempt, project)
  end

  @doc false
  @spec lock_context(ProjectImportAttempt.t(), Project.t()) :: locked_context()
  def lock_context(%ProjectImportAttempt{project_id: project_id} = attempt, %Project{id: project_id} = locked_project) do
    ensure_inside_transaction!()
    build_context(attempt, locked_project)
  end

  @doc false
  @spec deliver(ProjectImportAttempt.t(), locked_context(), String.t()) ::
          {:ok, Notifications.delivery_outcome()} | {:error, Ecto.Changeset.t()}
  def deliver(%ProjectImportAttempt{} = attempt, %{project_id: project_id, requester_id: requester_id} = context, status)
      when status in ["success", "failure"] do
    project = if attempt.project_id == project_id, do: context.project
    requester = if attempt.user_id == requester_id, do: context.requester

    Notifications.deliver_async_result(
      Scope.for_user(requester),
      project,
      %{
        entity_type: "project_import",
        entity_id: attempt.id,
        status: status,
        dedupe_key: "project_import:#{attempt.id}:#{status}"
      }
    )
  end

  defp build_context(attempt, project) do
    %{
      project_id: attempt.project_id,
      requester_id: attempt.user_id,
      project: project,
      requester: lock_requester(attempt.user_id)
    }
  end

  defp lock_requester(nil), do: nil

  defp lock_requester(user_id) do
    User
    |> where([user], user.id == ^user_id)
    |> lock("FOR KEY SHARE")
    |> Repo.one()
  end

  defp ensure_inside_transaction! do
    if !Repo.in_transaction?() do
      raise ArgumentError, "notification parent locks require an open transaction"
    end
  end
end

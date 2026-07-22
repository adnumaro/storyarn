defmodule Storyarn.Workers.RestoreProjectWorker do
  @moduledoc """
  Oban worker that performs a project snapshot restore in the background.

  The job may run only after atomically claiming the restoration lock identified
  by its actor, snapshot, and token. The claim fences duplicate deliveries that
  carry the same token. Authorization is reloaded immediately before the
  restore, and the lock is released only by its matching token.
  """

  # Keep project restores off the legacy :snapshots queue. During a rolling
  # deploy, old releases do not poll this queue and therefore cannot execute a
  # token-bound job with the unfenced legacy worker implementation.
  use Oban.Worker, queue: :project_restores, max_attempts: 1

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "project_id" => project_id,
          "snapshot_id" => snapshot_id,
          "user_id" => user_id,
          "lock_token" => lock_token
        }
      })
      when is_integer(job_id) and job_id > 0 do
    case Projects.claim_restoration_lock(
           project_id,
           user_id,
           snapshot_id,
           lock_token,
           job_id
         ) do
      {:ok, _project} ->
        perform_owned_restore(project_id, snapshot_id, user_id, lock_token, job_id)

      {:error, reason} ->
        Logger.warning(
          "Rejected project restore job without an unclaimed matching lock " <>
            "project=#{project_id} snapshot=#{snapshot_id} reason=#{inspect(reason)}"
        )

        {:error, {:invalid_restoration_lock, reason}}
    end
  end

  def perform(%Oban.Job{}) do
    {:error, :invalid_restore_job_args}
  end

  @doc false
  def perform_owned_restore(project_id, snapshot_id, user_id, lock_token, job_id, opts \\ []) do
    restore_fun =
      Keyword.get(
        opts,
        :restore_fun,
        &Versioning.restore_project_snapshot/3
      )

    release_fun =
      Keyword.get(
        opts,
        :release_fun,
        &Projects.release_restoration_lock/3
      )

    result =
      try do
        with :ok <- Versioning.ensure_restore_enabled(:project_snapshot_restore),
             :ok <- reauthorize_actor(project_id, user_id),
             {:ok, snapshot} <- fetch_snapshot(project_id, snapshot_id),
             {:ok, restored} <-
               restore_fun.(
                 project_id,
                 snapshot,
                 user_id: user_id
               ) do
          {:ok, restored, snapshot}
        end
      rescue
        exception ->
          Logger.error(
            "Project restore raised for project #{project_id}: " <>
              Exception.message(exception)
          )

          {:error, :restore_exception}
      catch
        kind, reason ->
          Logger.error(
            "Project restore terminated abnormally for project #{project_id}: " <>
              "kind=#{kind} reason=#{inspect(reason)}"
          )

          {:error, :restore_exception}
      end

    case release_owned_lock(project_id, lock_token, job_id, release_fun) do
      :ok ->
        publish_result(project_id, result)

      {:error, reason} ->
        Logger.error(
          "Suppressed terminal project restoration event because lock release " <>
            "was not confirmed project=#{project_id} reason=#{inspect(reason)}"
        )

        {:error, {:restoration_lock_release_failed, reason}}
    end
  end

  defp reauthorize_actor(project_id, user_id) do
    with %User{} = user <- Repo.get(User, user_id),
         {:ok, _project, _membership} <-
           Projects.authorize(Scope.for_user(user), project_id, :manage_project) do
      :ok
    else
      _ -> {:error, :restore_actor_unauthorized}
    end
  end

  defp fetch_snapshot(project_id, snapshot_id) do
    case Versioning.get_project_snapshot(project_id, snapshot_id) do
      nil -> {:error, :snapshot_not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  defp release_owned_lock(project_id, lock_token, job_id, release_fun) do
    case release_fun.(project_id, lock_token, job_id) do
      {:ok, _project} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not release owned project restoration lock " <>
            "project=#{project_id} reason=#{inspect(reason)}"
        )

        {:error, reason}

      _unexpected ->
        Logger.warning(
          "Could not release owned project restoration lock " <>
            "project=#{project_id} reason=unexpected_result"
        )

        {:error, :unexpected_release_result}
    end
  rescue
    exception ->
      Logger.warning(
        "Owned project restoration lock release raised " <>
          "project=#{project_id} exception=#{inspect(exception.__struct__)}"
      )

      {:error, :release_exception}
  catch
    kind, _reason ->
      Logger.warning(
        "Owned project restoration lock release terminated abnormally " <>
          "project=#{project_id} kind=#{kind}"
      )

      {:error, :release_failure}
  end

  defp publish_result(project_id, {:ok, restored, snapshot}) do
    Collaboration.broadcast_restoration_completed(project_id, %{
      restored: restored.restored,
      skipped: restored.skipped,
      snapshot_title: snapshot.title
    })

    Collaboration.broadcast_dashboard_change(project_id, :all)
    :ok
  end

  defp publish_result(project_id, {:error, :restore_temporarily_disabled} = error) do
    Collaboration.broadcast_restoration_failed(project_id, %{
      reason: :restore_temporarily_disabled
    })

    error
  end

  defp publish_result(project_id, {:error, :snapshot_not_found} = error) do
    Collaboration.broadcast_restoration_failed(project_id, %{
      reason: "Snapshot not found"
    })

    error
  end

  defp publish_result(project_id, {:error, reason} = error) do
    Logger.error("Project restore failed for project #{project_id}: #{inspect(reason)}")

    Collaboration.broadcast_restoration_failed(project_id, %{reason: :restore_failed})
    error
  end
end

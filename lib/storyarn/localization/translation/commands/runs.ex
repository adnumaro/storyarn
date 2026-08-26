defmodule Storyarn.Localization.Translation.Commands.Runs do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Localization.Texts
  alias Storyarn.Localization.Translation.Adapters.Notifications.Delivery, as: NotificationDelivery
  alias Storyarn.Localization.Translation.Adapters.PubSub.Broadcaster
  alias Storyarn.Localization.Translation.Data.ProjectRecord
  alias Storyarn.Localization.Translation.Data.UserRecord
  alias Storyarn.Localization.Translation.Queries.Runs, as: RunQueries
  alias Storyarn.Localization.TranslationJobQueue
  alias Storyarn.Localization.TranslationRun
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @active_statuses ~w(queued running)

  def enqueue(project_id, target_locale, requested_by_id, opts \\ []) do
    text_status = opts[:status] || "pending"
    source_type = opts[:source_type]
    filters = maybe_add([locale_code: target_locale, status: text_status], :source_type, source_type)
    total_count = Texts.count_texts(project_id, filters)

    attrs = %{
      target_locale: target_locale,
      source_type: source_type,
      text_status: text_status,
      total_count: total_count,
      requested_by_id: requested_by_id
    }

    Multi.new()
    |> Multi.insert(:run, TranslationRun.create_changeset(%TranslationRun{project_id: project_id}, attrs))
    |> Multi.run(:job, fn _repo, %{run: run} ->
      TranslationJobQueue.enqueue(run.id)
    end)
    |> Multi.run(:run_with_job, fn _repo, %{run: run, job: job} ->
      update_run(run, %{oban_job_id: job.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{run_with_job: run}} -> {:ok, run}
      {:error, :run, changeset, _changes} -> normalize_enqueue_error(changeset)
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def update_run(%TranslationRun{} = run, attrs) do
    run
    |> TranslationRun.update_changeset(attrs)
    |> Repo.update()
  end

  def transition_active(run_id, attrs) when is_map(attrs) do
    updates = attrs |> Map.put(:updated_at, TimeHelpers.now()) |> Map.to_list()

    from(run in TranslationRun, where: run.id == ^run_id and run.status in @active_statuses)
    |> Repo.update_all(set: updates)
    |> case do
      {1, _rows} -> {:ok, RunQueries.get(run_id)}
      {0, _rows} -> {:error, :inactive}
    end
  end

  def transition_terminal(run_id, %{status: status} = attrs) when status in ["completed", "failed"] do
    with {:ok, identity} <- terminal_run_identity(run_id) do
      Repo.transact(fn -> transition_terminal_locked(run_id, attrs, identity) end)
    end
  end

  def transition_terminal(_run_id, _attrs), do: {:error, :invalid_terminal_status}

  def cancel(%TranslationRun{status: status} = run) when status in ["queued", "running"] do
    now = TimeHelpers.now()

    with {:ok, cancelled} <-
           transition_active(run.id, %{status: "cancelled", cancelled_at: now, completed_at: now}),
         :ok <- TranslationJobQueue.cancel(run.oban_job_id) do
      Broadcaster.broadcast(cancelled)
      {:ok, cancelled}
    else
      {:error, :inactive} -> {:ok, RunQueries.get(run.id) || run}
      {:error, _reason} = error -> error
    end
  end

  def cancel(%TranslationRun{} = run), do: {:ok, run}

  defp normalize_enqueue_error(changeset) do
    active_run_error? =
      Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
        metadata[:constraint_name] == "localization_translation_runs_one_active"
      end)

    if active_run_error?, do: {:error, :already_running}, else: {:error, changeset}
  end

  defp terminal_run_identity(run_id) do
    case Repo.one(
           from(run in TranslationRun,
             where: run.id == ^run_id and run.status in @active_statuses,
             select: %{
               run_id: run.id,
               project_id: run.project_id,
               requested_by_id: run.requested_by_id
             }
           )
         ) do
      identity when is_map(identity) -> {:ok, identity}
      nil -> {:error, :inactive}
    end
  end

  defp lock_terminal_notification_parents(%{project_id: project_id, requested_by_id: requested_by_id}) do
    with %ProjectRecord{} = project <- lock_notification_project(project_id),
         {:ok, requester} <- lock_notification_user(requested_by_id) do
      {:ok, {project, requester}}
    else
      nil -> {:error, :inactive}
      {:error, _reason} = error -> error
    end
  end

  defp lock_notification_project(project_id) do
    Repo.one(from(project in ProjectRecord, where: project.id == ^project_id, lock: "FOR SHARE"))
  end

  defp lock_notification_user(nil), do: {:ok, nil}

  defp lock_notification_user(user_id) when is_integer(user_id) do
    case Repo.one(from(user in UserRecord, where: user.id == ^user_id, lock: "FOR KEY SHARE")) do
      %UserRecord{} = user -> {:ok, user}
      nil -> {:ok, nil}
    end
  end

  defp lock_active_run(run_id) do
    TranslationRun
    |> where([run], run.id == ^run_id and run.status in @active_statuses)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp transition_terminal_locked(run_id, attrs, identity) do
    with {:ok, {project, requester}} <- lock_terminal_notification_parents(identity),
         %TranslationRun{} = run <- lock_active_run(run_id),
         :ok <- validate_terminal_run_identity(run, identity, requester) do
      persist_terminal(run, attrs, project, requester)
    else
      nil -> {:error, :inactive}
      {:error, _reason} = error -> error
    end
  end

  defp validate_terminal_run_identity(
         %TranslationRun{id: run_id, project_id: project_id, requested_by_id: requested_by_id},
         %{run_id: run_id, project_id: project_id, requested_by_id: requested_by_id},
         %UserRecord{id: requested_by_id}
       ), do: :ok

  defp validate_terminal_run_identity(
         %TranslationRun{id: run_id, project_id: project_id, requested_by_id: current_requester_id},
         %{run_id: run_id, project_id: project_id, requested_by_id: expected_requester_id},
         nil
       )
       when is_nil(current_requester_id) or current_requester_id == expected_requester_id, do: :ok

  defp validate_terminal_run_identity(%TranslationRun{}, _identity, _requester), do: {:error, :inactive}

  defp persist_terminal(run, attrs, project, requester) do
    with {:ok, updated} <- update_run(run, attrs),
         {:ok, notification_outcome} <- deliver_terminal_notification(updated, project, requester) do
      {:ok, {updated, notification_outcome}}
    end
  end

  defp deliver_terminal_notification(%TranslationRun{status: status} = run, project, requester)
       when status in ["completed", "failed"] do
    notification_status = notification_status(run)

    NotificationDelivery.deliver_async_result(
      requester_id(requester),
      project.id,
      %{
        entity_type: "localization_batch",
        entity_id: run.id,
        entity_name: run.target_locale,
        status: notification_status,
        dedupe_key: "localization_batch:#{run.id}:#{notification_status}"
      }
    )
  end

  defp notification_status(%TranslationRun{status: "completed"}), do: "success"
  defp notification_status(%TranslationRun{status: "failed"}), do: "failure"

  defp requester_id(%UserRecord{id: id}), do: id
  defp requester_id(nil), do: nil

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end

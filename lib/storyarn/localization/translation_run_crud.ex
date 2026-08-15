defmodule Storyarn.Localization.TranslationRunCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Localization.TranslationRun
  alias Storyarn.Notifications
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workers.LocalizationBatchTranslationWorker

  @active_statuses ~w(queued running)

  def enqueue(project_id, target_locale, requested_by_id, opts \\ []) do
    text_status = opts[:status] || "pending"
    source_type = opts[:source_type]

    filters = maybe_add([locale_code: target_locale, status: text_status], :source_type, source_type)

    total_count = TextCrud.count_texts(project_id, filters)

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
      %{run_id: run.id}
      |> LocalizationBatchTranslationWorker.new()
      |> Oban.insert()
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

  def get(run_id), do: Repo.get(TranslationRun, run_id)

  def get_for_project(project_id, run_id) do
    Repo.one(from(r in TranslationRun, where: r.id == ^run_id and r.project_id == ^project_id))
  end

  def get_active(_project_id, nil), do: nil

  def get_active(project_id, target_locale) do
    Repo.one(
      from(r in TranslationRun,
        where:
          r.project_id == ^project_id and r.target_locale == ^target_locale and
            r.status in ["queued", "running"],
        order_by: [desc: r.id],
        limit: 1
      )
    )
  end

  def update_run(%TranslationRun{} = run, attrs) do
    run
    |> TranslationRun.update_changeset(attrs)
    |> Repo.update()
  end

  def transition_active(run_id, attrs) when is_map(attrs) do
    updates = attrs |> Map.put(:updated_at, TimeHelpers.now()) |> Map.to_list()

    from(r in TranslationRun, where: r.id == ^run_id and r.status in @active_statuses)
    |> Repo.update_all(set: updates)
    |> case do
      {1, _rows} -> {:ok, get(run_id)}
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
         :ok <- cancel_oban_job(run.oban_job_id) do
      broadcast(cancelled)
      {:ok, cancelled}
    else
      {:error, :inactive} -> {:ok, get(run.id) || run}
      {:error, _reason} = error -> error
    end
  end

  def cancel(%TranslationRun{} = run), do: {:ok, run}

  def cancelled?(run_id) do
    Repo.exists?(from(r in TranslationRun, where: r.id == ^run_id and r.status == "cancelled"))
  end

  def broadcast(%TranslationRun{} = run) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      topic(run.project_id),
      {:translation_run_updated, run}
    )
  end

  def topic(project_id), do: "project:#{project_id}:localization"

  defp cancel_oban_job(nil), do: :ok
  defp cancel_oban_job(job_id), do: Oban.cancel_job(job_id)

  defp normalize_enqueue_error(changeset) do
    active_run_error? =
      Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
        metadata[:constraint_name] == "localization_translation_runs_one_active"
      end)

    if active_run_error? do
      {:error, :already_running}
    else
      {:error, changeset}
    end
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
    with %Project{} = project <- lock_notification_project(project_id),
         {:ok, requester} <- lock_notification_user(requested_by_id) do
      {:ok, {project, requester}}
    else
      nil -> {:error, :inactive}
      {:error, _reason} = error -> error
    end
  end

  defp lock_notification_project(project_id) do
    Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR SHARE"))
  end

  defp lock_notification_user(nil), do: {:ok, nil}

  defp lock_notification_user(user_id) when is_integer(user_id) do
    case Repo.one(from(user in User, where: user.id == ^user_id, lock: "FOR KEY SHARE")) do
      %User{} = user -> {:ok, user}
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
         %User{id: requested_by_id}
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

    Notifications.deliver_async_result(
      Scope.for_user(requester),
      project,
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

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end

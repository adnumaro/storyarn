defmodule Storyarn.Localization.TranslationRunCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Localization.TranslationRun
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

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end

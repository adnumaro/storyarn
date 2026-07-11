defmodule Storyarn.Workers.LocalizationBatchTranslationWorker do
  @moduledoc "Translates a persisted localization batch outside the LiveView process."

  use Oban.Worker, queue: :localization, max_attempts: 3

  alias Storyarn.Localization.BatchTranslator
  alias Storyarn.Localization.LanguageCrud
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Localization.TranslationRunCrud
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}} = job) do
    case TranslationRunCrud.get(run_id) do
      nil ->
        {:discard, :translation_run_not_found}

      %{status: "cancelled"} ->
        :ok

      run ->
        execute(run, job)
    end
  end

  defp execute(run, job) do
    with true <- active_target?(run),
         {:ok, running} <-
           TranslationRunCrud.transition_active(run.id, %{
             status: "running",
             started_at: run.started_at || TimeHelpers.now(),
             error: nil
           }) do
      execute_running(running, job)
    else
      false -> cancel_inactive_target(run)
      {:error, :inactive} -> :ok
    end
  end

  defp execute_running(running, job) do
    base_counts = run_counts(running)

    TranslationRunCrud.broadcast(running)

    opts =
      [
        status: running.text_status,
        source_type: running.source_type,
        translator: translation_provider(),
        cancelled?: fn -> TranslationRunCrud.cancelled?(running.id) end,
        progress_callback: &persist_progress(running, base_counts, &1)
      ]

    case BatchTranslator.translate_batch(running.project_id, running.target_locale, opts) do
      {:ok, result} -> complete(running, base_counts, result)
      {:error, :cancelled} -> mark_cancelled(running)
      {:error, reason} -> fail(running, reason, job.attempt >= job.max_attempts)
    end
  end

  defp persist_progress(run, base_counts, result) do
    case TranslationRunCrud.transition_active(run.id, merged_counts(base_counts, result)) do
      {:ok, updated} ->
        TranslationRunCrud.broadcast(updated)

      {:error, :inactive} ->
        :ok
    end
  end

  defp complete(run, base_counts, result) do
    case TranslationRunCrud.transition_active(
           run.id,
           Map.merge(merged_counts(base_counts, result), %{
             status: "completed",
             completed_at: TimeHelpers.now()
           })
         ) do
      {:ok, completed} ->
        TranslationRunCrud.broadcast(completed)
        :ok

      {:error, :inactive} ->
        :ok
    end
  end

  defp mark_cancelled(run) do
    case TranslationRunCrud.get(run.id) do
      %{status: "cancelled"} -> :ok
      current -> current |> TranslationRunCrud.cancel() |> then(fn {:ok, _run} -> :ok end)
    end
  end

  defp fail(run, reason, final_attempt?) do
    attrs =
      if final_attempt? do
        %{status: "failed", error: inspect(reason), completed_at: TimeHelpers.now()}
      else
        %{error: inspect(reason)}
      end

    case TranslationRunCrud.transition_active(run.id, attrs) do
      {:ok, updated} -> TranslationRunCrud.broadcast(updated)
      {:error, :inactive} -> :ok
    end

    Logger.warning(
      "Localization batch #{run.id} #{if(final_attempt?, do: "failed", else: "will retry")}: #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp active_target?(run) do
    case LanguageCrud.get_language_by_locale(run.project_id, run.target_locale) do
      %{is_source: false} -> true
      _language -> false
    end
  end

  defp cancel_inactive_target(run) do
    run
    |> TranslationRunCrud.cancel()
    |> case do
      {:ok, _cancelled} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_counts(run) do
    %{
      processed_count: run.processed_count,
      translated_count: run.translated_count,
      failed_count: run.failed_count
    }
  end

  defp merged_counts(base, result) do
    %{
      processed_count: base.processed_count + result.translated + result.failed,
      translated_count: base.translated_count + result.translated,
      failed_count: base.failed_count + result.failed
    }
  end

  defp translation_provider do
    Application.get_env(:storyarn, :localization_translation_provider, DeepL)
  end
end

defmodule Storyarn.Workers.LocalizationBatchTranslationWorker do
  @moduledoc "Translates a persisted localization batch outside the LiveView process."

  use Oban.Worker, queue: :localization, max_attempts: 3

  alias Storyarn.Localization.BatchTranslator
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Localization.TranslationRunCrud
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    case TranslationRunCrud.get(run_id) do
      nil ->
        {:discard, :translation_run_not_found}

      %{status: "cancelled"} ->
        :ok

      run ->
        execute(run)
    end
  end

  defp execute(run) do
    {:ok, running} =
      TranslationRunCrud.update_run(run, %{
        status: "running",
        started_at: run.started_at || TimeHelpers.now(),
        error: nil
      })

    TranslationRunCrud.broadcast(running)

    opts =
      [
        status: running.text_status,
        source_type: running.source_type,
        translator: translation_provider(),
        cancelled?: fn -> TranslationRunCrud.cancelled?(running.id) end,
        progress_callback: &persist_progress(running, &1)
      ]

    case BatchTranslator.translate_batch(running.project_id, running.target_locale, opts) do
      {:ok, result} -> complete(running, result)
      {:error, :cancelled} -> mark_cancelled(running)
      {:error, reason} -> fail(running, reason)
    end
  end

  defp persist_progress(run, result) do
    case TranslationRunCrud.get(run.id) do
      %{status: "cancelled"} ->
        :ok

      current ->
        {:ok, updated} =
          TranslationRunCrud.update_run(current, %{
            processed_count: result.translated + result.failed,
            translated_count: result.translated,
            failed_count: result.failed
          })

        TranslationRunCrud.broadcast(updated)
    end
  end

  defp complete(run, result) do
    current = TranslationRunCrud.get(run.id)

    if current.status == "cancelled" do
      :ok
    else
      {:ok, completed} =
        TranslationRunCrud.update_run(current, %{
          status: "completed",
          processed_count: result.translated + result.failed,
          translated_count: result.translated,
          failed_count: result.failed,
          completed_at: TimeHelpers.now()
        })

      TranslationRunCrud.broadcast(completed)
      :ok
    end
  end

  defp mark_cancelled(run) do
    case TranslationRunCrud.get(run.id) do
      %{status: "cancelled"} -> :ok
      current -> current |> TranslationRunCrud.cancel() |> then(fn {:ok, _run} -> :ok end)
    end
  end

  defp fail(run, reason) do
    current = TranslationRunCrud.get(run.id)

    {:ok, failed} =
      TranslationRunCrud.update_run(current, %{
        status: "failed",
        error: inspect(reason),
        completed_at: TimeHelpers.now()
      })

    TranslationRunCrud.broadcast(failed)
    Logger.warning("Localization batch #{run.id} failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp translation_provider do
    Application.get_env(:storyarn, :localization_translation_provider, DeepL)
  end
end

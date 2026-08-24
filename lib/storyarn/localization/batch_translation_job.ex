defmodule Storyarn.Localization.BatchTranslationJob do
  @moduledoc false

  alias Storyarn.Localization.BatchTranslator
  alias Storyarn.Localization.LanguageCrud
  alias Storyarn.Localization.NotificationDelivery
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Localization.TranslationRunCrud
  alias Storyarn.Platform.Shared.TimeHelpers

  require Logger

  defguardp is_positive_integer(value) when is_integer(value) and value > 0

  @spec perform(integer(), pos_integer(), pos_integer()) :: :ok | {:error, term()} | {:discard, atom()}
  def perform(run_id, attempt, max_attempts)
      when is_integer(run_id) and is_positive_integer(attempt) and is_positive_integer(max_attempts) do
    case TranslationRunCrud.get(run_id) do
      nil ->
        {:discard, :translation_run_not_found}

      %{status: "cancelled"} ->
        :ok

      run ->
        execute(run, attempt >= max_attempts)
    end
  end

  defp execute(run, final_attempt?) do
    with true <- active_target?(run),
         {:ok, running} <-
           TranslationRunCrud.transition_active(run.id, %{
             status: "running",
             started_at: run.started_at || TimeHelpers.now(),
             error: nil
           }) do
      execute_running(running, final_attempt?)
    else
      false -> cancel_inactive_target(run)
      {:error, :inactive} -> :ok
    end
  end

  defp execute_running(running, final_attempt?) do
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

    case translate_batch(running, opts) do
      {:returned, {:ok, result}} ->
        complete(running, base_counts, result)

      {:returned, {:error, :cancelled}} ->
        mark_cancelled(running)

      {:returned, {:error, reason}} ->
        fail(running, reason, final_attempt?)

      {:raised, exception, stacktrace} ->
        fail_and_reraise(running, exception, stacktrace, final_attempt?)

      {:caught, kind, reason, stacktrace} ->
        fail_and_raise(running, kind, reason, stacktrace, final_attempt?)
    end
  end

  defp translate_batch(running, opts) do
    {:returned, BatchTranslator.translate_batch(running.project_id, running.target_locale, opts)}
  rescue
    exception -> {:raised, exception, __STACKTRACE__}
  catch
    kind, reason -> {:caught, kind, reason, __STACKTRACE__}
  end

  defp persist_progress(run, base_counts, result) do
    case TranslationRunCrud.transition_active(run.id, merged_counts(base_counts, result)) do
      {:ok, updated} -> TranslationRunCrud.broadcast(updated)
      {:error, :inactive} -> :ok
    end
  end

  defp complete(run, base_counts, result) do
    case TranslationRunCrud.transition_terminal(
           run.id,
           Map.merge(merged_counts(base_counts, result), %{
             status: "completed",
             completed_at: TimeHelpers.now()
           })
         ) do
      {:ok, {completed, notification_outcome}} ->
        TranslationRunCrud.broadcast(completed)
        NotificationDelivery.publish_committed(notification_outcome)
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

    result =
      if final_attempt? do
        TranslationRunCrud.transition_terminal(run.id, attrs)
      else
        TranslationRunCrud.transition_active(run.id, attrs)
      end

    case result do
      {:ok, {updated, notification_outcome}} ->
        TranslationRunCrud.broadcast(updated)
        NotificationDelivery.publish_committed(notification_outcome)

      {:ok, updated} ->
        TranslationRunCrud.broadcast(updated)

      {:error, :inactive} ->
        :ok
    end

    Logger.warning(
      "Localization batch #{run.id} #{if(final_attempt?, do: "failed", else: "will retry")}: #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp fail_and_reraise(run, exception, stacktrace, final_attempt?) do
    log_unexpected_exception(run, exception, stacktrace)
    fail(run, {:exception, exception.__struct__}, final_attempt?)
    reraise exception, stacktrace
  end

  defp fail_and_raise(run, kind, reason, stacktrace, final_attempt?) do
    log_unexpected_catch(run, kind, reason, stacktrace)
    fail(run, {:caught, kind}, final_attempt?)
    :erlang.raise(kind, reason, stacktrace)
  end

  defp log_unexpected_exception(run, exception, stacktrace) do
    Logger.error(
      "Unexpected localization batch translation exception run_id=#{run.id}\n#{Exception.format(:error, exception, stacktrace)}"
    )
  end

  defp log_unexpected_catch(run, kind, reason, stacktrace) do
    Logger.error(
      "Unexpected localization batch translation catch run_id=#{run.id}\n#{Exception.format(kind, reason, stacktrace)}"
    )
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

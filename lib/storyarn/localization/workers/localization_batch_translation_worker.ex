defmodule Storyarn.Localization.Workers.LocalizationBatchTranslationWorker do
  @moduledoc "Oban adapter for Localization-owned batch translation jobs."

  use Oban.Worker, queue: :localization, max_attempts: 3

  alias Storyarn.Localization

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}, attempt: attempt, max_attempts: max_attempts}) do
    Localization.perform_translation_run(run_id, attempt, max_attempts)
  end
end

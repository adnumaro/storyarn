defmodule Storyarn.Localization.Translation do
  @moduledoc false

  alias Storyarn.Localization.Translation.Adapters.PubSub.Broadcaster
  alias Storyarn.Localization.Translation.Commands.Runs, as: RunCommands
  alias Storyarn.Localization.Translation.Execution.BatchTranslationJob
  alias Storyarn.Localization.Translation.Execution.BatchTranslator
  alias Storyarn.Localization.Translation.Queries.Runs, as: RunQueries

  @type result :: BatchTranslator.result()

  defdelegate translate_batch(project_id, target_locale, opts \\ []), to: BatchTranslator
  defdelegate translate_single(project_id, text_id), to: BatchTranslator

  defdelegate enqueue(project_id, target_locale, requested_by_id, opts \\ []), to: RunCommands
  defdelegate get(run_id), to: RunQueries
  defdelegate get_for_project(project_id, run_id), to: RunQueries
  defdelegate get_active(project_id, target_locale), to: RunQueries
  defdelegate cancelled?(run_id), to: RunQueries

  defdelegate update_run(run, attrs), to: RunCommands
  defdelegate transition_active(run_id, attrs), to: RunCommands
  defdelegate transition_terminal(run_id, attrs), to: RunCommands
  defdelegate cancel(run), to: RunCommands

  defdelegate broadcast(run), to: Broadcaster
  defdelegate topic(project_id), to: Broadcaster

  defdelegate perform(run_id, attempt, max_attempts), to: BatchTranslationJob
end

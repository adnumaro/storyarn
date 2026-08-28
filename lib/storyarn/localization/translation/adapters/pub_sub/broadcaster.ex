defmodule Storyarn.Localization.Translation.Adapters.PubSub.Broadcaster do
  @moduledoc false

  alias Storyarn.Localization.TranslationRun

  @spec broadcast(TranslationRun.t()) :: :ok | {:error, term()}
  def broadcast(%TranslationRun{} = run) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      topic(run.project_id),
      {:translation_run_updated, run}
    )
  end

  @spec topic(pos_integer()) :: String.t()
  def topic(project_id), do: "project:#{project_id}:localization"
end

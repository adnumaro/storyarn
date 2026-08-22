defmodule Storyarn.Localization.TranslationJobQueue do
  @moduledoc false

  @config Application.compile_env(:storyarn, __MODULE__, [])
  @worker Keyword.fetch!(@config, :worker)
  @queue Keyword.get(@config, :queue, :localization)
  @max_attempts Keyword.get(@config, :max_attempts, 3)

  @spec new(pos_integer()) :: Ecto.Changeset.t()
  def new(run_id) when is_integer(run_id) and run_id > 0 do
    Oban.Job.new(
      %{run_id: run_id},
      worker: @worker,
      queue: @queue,
      max_attempts: @max_attempts
    )
  end
end

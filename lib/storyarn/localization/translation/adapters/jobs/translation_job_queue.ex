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

  @spec enqueue(pos_integer()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(run_id) when is_integer(run_id) and run_id > 0 do
    run_id
    |> new()
    |> Oban.insert()
  end

  @spec cancel(integer() | nil) :: :ok | {:error, term()}
  def cancel(nil), do: :ok
  def cancel(job_id) when is_integer(job_id), do: Oban.cancel_job(job_id)
end

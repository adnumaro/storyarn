defmodule Storyarn.Workers.ExpireIdeationTimerWorker do
  @moduledoc "Durable safety delivery for a persisted brainstorming timer version."
  use Oban.Worker,
    queue: :ideation_timers,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args], states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Ideation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"timer_id" => id, "version" => version}})
      when is_integer(id) and id > 0 and is_integer(version) and version > 0 do
    case Ideation.expire_timer(id, version) do
      {:ok, %{outcome: :not_due, timer: timer}} ->
        remaining = DateTime.to_unix(timer.deadline_at, :millisecond) - System.system_time(:millisecond)
        {:snooze, max(div(remaining + 999, 1_000), 1)}

      {:ok, _receipt} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_ideation_timer_job}
end

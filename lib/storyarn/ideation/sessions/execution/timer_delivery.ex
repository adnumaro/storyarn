defmodule Storyarn.Ideation.Sessions.Execution.TimerDelivery do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workers.ExpireIdeationTimerWorker

  def schedule(%{status: :running} = timer) do
    if Repo.in_transaction?() do
      %{timer_id: timer.id, version: timer.version}
      |> ExpireIdeationTimerWorker.new(scheduled_at: timer.deadline_at)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :timer_transaction_required}
    end
  end

  def schedule(_timer), do: :ok
end

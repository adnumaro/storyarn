defmodule Storyarn.Workers.BuildProjectSnapshotWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.BuildProjectSnapshotWorker

  test "snoozes preserve the five-attempt backoff budget" do
    assert Keyword.fetch!(BuildProjectSnapshotWorker.__opts__(), :max_attempts) == 5

    for {attempt, logical_attempt} <- Enum.zip(25..29, 1..5) do
      snoozed = %Oban.Job{attempt: attempt, max_attempts: 29}
      logical = %Oban.Job{attempt: logical_attempt, max_attempts: 5}

      assert seeded_backoff(snoozed) == seeded_oban_backoff(logical)
    end
  end

  test "many snoozes cannot turn the next failure into a multi-day backoff" do
    snoozed = %Oban.Job{attempt: 721, max_attempts: 725}

    assert seeded_backoff(snoozed) in 17..18
  end

  defp seeded_backoff(job) do
    :rand.seed(:exsss, {101, 102, 103})
    BuildProjectSnapshotWorker.backoff(job)
  end

  defp seeded_oban_backoff(job) do
    :rand.seed(:exsss, {101, 102, 103})
    Oban.Worker.backoff(job)
  end
end

defmodule Storyarn.Workers.BuildProjectSnapshotWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.BuildProjectSnapshotWorker

  test "uses the canonical archive queue" do
    assert Keyword.fetch!(BuildProjectSnapshotWorker.__opts__(), :queue) == :snapshot_archives
  end

  test "snoozes preserve the three-attempt failure budget" do
    assert Keyword.fetch!(BuildProjectSnapshotWorker.__opts__(), :max_attempts) == 3

    for logical_attempt <- 1..3 do
      errors = List.duplicate(%{}, logical_attempt - 1)
      snoozed = %Oban.Job{attempt: 24 + logical_attempt, max_attempts: 27, errors: errors}
      logical = %Oban.Job{attempt: logical_attempt, max_attempts: 3}

      assert seeded_backoff(snoozed) == seeded_oban_backoff(logical)
    end
  end

  test "many snoozes cannot turn the next failure into a multi-day backoff" do
    snoozed = %Oban.Job{attempt: 721, max_attempts: 723, errors: []}

    assert seeded_backoff(snoozed) in 17..18
  end

  test "legacy five-attempt jobs are capped by persisted failures" do
    assert BuildProjectSnapshotWorker.canonical_attempt(%Oban.Job{
             attempt: 2,
             max_attempts: 5,
             errors: [%{}]
           }) == 2

    assert BuildProjectSnapshotWorker.canonical_attempt(%Oban.Job{
             attempt: 3,
             max_attempts: 5,
             errors: [%{}, %{}]
           }) == 3
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

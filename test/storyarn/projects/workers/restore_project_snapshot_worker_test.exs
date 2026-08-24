defmodule Storyarn.Workers.RestoreProjectSnapshotWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Workers.RestoreProjectSnapshotWorker

  test "uses the isolated snapshot restore queue and a stable unique delivery" do
    opts = RestoreProjectSnapshotWorker.__opts__()

    assert Keyword.fetch!(opts, :queue) == :snapshot_restores
    assert Keyword.fetch!(opts, :max_attempts) == 5

    unique = Keyword.fetch!(opts, :unique)
    assert Keyword.fetch!(unique, :fields) == [:worker, :args]
    assert Keyword.fetch!(unique, :period) == :infinity
  end

  test "rejects incomplete delivery arguments" do
    assert {:discard, :invalid_project_snapshot_restore_job} =
             RestoreProjectSnapshotWorker.perform(%Oban.Job{args: %{}})
  end
end

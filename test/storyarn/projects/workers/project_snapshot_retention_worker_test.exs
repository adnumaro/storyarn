defmodule Storyarn.Workers.ProjectSnapshotRetentionWorkerTest do
  use ExUnit.Case, async: true

  alias Oban.Plugins.Cron
  alias Storyarn.Projects.Workers.ProjectSnapshotRetentionWorker

  @eng_37_floor_seconds 15 * 60
  @expired_build_reclamation_sla_seconds 15 * 60

  test "cron bounds expired-build reclamation without violating the ENG-37 floor" do
    {expression, ProjectSnapshotRetentionWorker} =
      :storyarn
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find_value(fn
        {Cron, opts} ->
          opts
          |> Keyword.fetch!(:crontab)
          |> Enum.find(fn {_expression, worker} -> worker == ProjectSnapshotRetentionWorker end)

        _plugin ->
          nil
      end)

    interval_seconds = cron_interval_seconds(expression)
    unique = Keyword.fetch!(ProjectSnapshotRetentionWorker.__opts__(), :unique)

    assert interval_seconds >= @eng_37_floor_seconds
    assert interval_seconds <= @expired_build_reclamation_sla_seconds
    assert Keyword.fetch!(unique, :period) == 600
    refute :completed in Keyword.fetch!(unique, :states)
    assert ProjectSnapshotRetentionWorker.timeout(%Oban.Job{}) == 10 * 60 * 1_000
  end

  defp cron_interval_seconds("*/" <> expression) do
    expression
    |> String.split(" ", parts: 2)
    |> hd()
    |> String.to_integer()
    |> Kernel.*(60)
  end
end

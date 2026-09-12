defmodule Storyarn.Workers.ExpireIdeationTimerWorkerTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Changeset
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Sessions.Execution.TimerDelivery
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Workers.ExpireIdeationTimerWorker

  setup do
    ideation_fixture()
  end

  test "starting commits a unique durable expiry for the exact timer version and deadline", ctx do
    timer = start(ctx)
    assert [job] = all_enqueued(worker: ExpireIdeationTimerWorker)
    assert job.queue == "ideation_timers"
    assert job.args == %{"timer_id" => timer.id, "version" => timer.version}
    assert job.scheduled_at == timer.deadline_at
    assert {:error, :timer_transaction_required} = TimerDelivery.schedule(timer)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, TimerDelivery.schedule(timer)} end)
    assert [_] = all_enqueued(worker: ExpireIdeationTimerWorker)
  end

  test "rolling back the enclosing command also rolls back its durable expiry", ctx do
    assert {:error, :abort} =
             Repo.transact(fn ->
               assert {:ok, _} =
                        Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{seconds: 30})

               assert [_] = all_enqueued(worker: ExpireIdeationTimerWorker)
               {:error, :abort}
             end)

    assert {:ok, nil} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert [] = all_enqueued(worker: ExpireIdeationTimerWorker)
  end

  test "the durable delivery expires after a lost wakeup with no browser or runtime", ctx do
    timer = start(ctx)
    assert [job] = all_enqueued(worker: ExpireIdeationTimerWorker)
    due(timer)
    assert :ok = perform_job(ExpireIdeationTimerWorker, job.args)
    assert {:ok, elapsed} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert elapsed.status == :elapsed
    assert elapsed.expiry_outcome == :completed
    assert elapsed.version == timer.version + 1
    assert :ok = perform_job(ExpireIdeationTimerWorker, job.args)
    assert {:ok, ^elapsed} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "reprogramming leaves old deliveries harmless and creates a new durable deadline", ctx do
    timer = start(ctx)
    assert [old_job] = all_enqueued(worker: ExpireIdeationTimerWorker)
    assert {:ok, _} = Ideation.extend_timer(ctx.owner, ctx.project.id, ctx.session.id, 2, timer.version, 30)
    assert {:ok, extended} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert extended.version == timer.version + 1
    assert length(all_enqueued(worker: ExpireIdeationTimerWorker)) == 2
    assert :ok = perform_job(ExpireIdeationTimerWorker, old_job.args)
    assert {:ok, ^extended} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)

    assert_enqueued(
      worker: ExpireIdeationTimerWorker,
      args: %{timer_id: timer.id, version: extended.version},
      scheduled_at: extended.deadline_at
    )
  end

  test "early delivery defers without applying expiry effects", ctx do
    timer = start(ctx)
    assert {:snooze, seconds} = perform_job(ExpireIdeationTimerWorker, %{timer_id: timer.id, version: timer.version})
    assert seconds in 1..30
    assert {:ok, ^timer} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "invalid job arguments are discarded" do
    for args <- [%{}, %{timer_id: nil, version: 1}, %{timer_id: 1, version: -1}] do
      assert {:discard, :invalid_ideation_timer_job} = perform_job(ExpireIdeationTimerWorker, args)
    end
  end

  defp start(ctx) do
    assert {:ok, _} = Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{seconds: 30})
    assert {:ok, timer} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    timer
  end

  defp due(timer) do
    deadline = %{DateTime.shift(TimeHelpers.now(), second: -1) | microsecond: {0, 6}}
    Timer |> Repo.get!(timer.id) |> change(deadline_at: deadline) |> Repo.update!()
  end
end

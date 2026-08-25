defmodule Storyarn.Workers.ReconcileAIReservationsWorkerTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Oban.Plugins.Cron
  alias Storyarn.AI
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.Result
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workers.AIExecutionWorker
  alias Storyarn.Workers.ExpireAIResultsWorker
  alias Storyarn.Workers.ReconcileAIReservationsWorker
  alias StoryarnTest.AI.ContractTask

  # Pinned through config in `setup` rather than read from the worker's default,
  # so these cases keep testing the behaviour they describe when the default
  # moves for compute-budget reasons (ENG-37).
  @stale_after 300

  # The cadence floor the crontab is allowed to use. Anything finer keeps the
  # database compute from ever idling — see the Oban block in config/config.exs.
  @min_cron_interval_seconds 900

  # A DB clock leading the app clock by tens of milliseconds is well within what
  # NTP-synced but separate machines drift to. Any positive lead larger than the
  # BEGIN round-trip reproduces the same result.
  @db_clock_lead_ms 50

  setup do
    original_reconciler_config =
      Application.get_env(:storyarn, ReconcileAIReservationsWorker, [])

    Application.put_env(:storyarn, ReconcileAIReservationsWorker, stale_after_seconds: @stale_after)

    on_exit(fn ->
      Application.put_env(:storyarn, ReconcileAIReservationsWorker, original_reconciler_config)
    end)

    original_config = Application.get_env(:storyarn, ContractTask, [])
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)

    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: user)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_config)
      FunWithFlags.disable(:ai_integrations, for_actor: user)
    end)

    %{user: user, scope: scope, workspace: workspace, project: project}
  end

  describe "queue isolation" do
    test "the reaper does not share a queue with the work it reaps" do
      execution_queue = Keyword.fetch!(AIExecutionWorker.__opts__(), :queue)

      assert execution_queue == :ai
      assert Keyword.fetch!(ReconcileAIReservationsWorker.__opts__(), :queue) == :ai_maintenance
      assert Keyword.fetch!(ExpireAIResultsWorker.__opts__(), :queue) == :ai_maintenance

      refute Keyword.fetch!(ReconcileAIReservationsWorker.__opts__(), :queue) == execution_queue
      refute Keyword.fetch!(ExpireAIResultsWorker.__opts__(), :queue) == execution_queue
    end

    test "the expiration follow-up chain stays off the execution queue" do
      # Mirrors the private `schedule_followup/0`, which builds its continuation
      # with `new/2` and therefore inherits the module's queue.
      assert %Ecto.Changeset{changes: %{queue: "ai_maintenance"}} =
               ExpireAIResultsWorker.new(%{}, schedule_in: 1)
    end

    test "the maintenance queue is configured with serial concurrency" do
      queues = :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:queues)

      assert Keyword.fetch!(queues, :ai_maintenance) == 1
      assert Keyword.fetch!(queues, :ai) == 2
    end
  end

  describe "uniqueness window" do
    test "every uniqueness window stays strictly below the cron interval it runs at" do
      for {worker, interval} <- scheduled_intervals(),
          unique = Keyword.get(worker.__opts__(), :unique),
          is_list(unique) do
        assert unique[:period] < interval,
               "#{inspect(worker)} has a #{unique[:period]}s uniqueness window on a " <>
                 "#{interval}s schedule — it will dedupe its own ticks"
      end
    end

    test "a window equal to the cron interval drops the next tick under a small clock lead" do
      # Positive control for the hazard itself. Oban stamps `inserted_at` from the
      # DB clock (Postgres `now()` at transaction start) but computes the window
      # cutoff from the app clock, with an inclusive `>=`. Two ticks of a schedule
      # land exactly one interval apart, so the second dedupes against the first as
      # soon as the DB clock leads the app clock by more than the BEGIN round-trip.
      # The lead is a property of the deployment, so simulate it rather than race it.
      insert_completed_reconciler_job!(seconds_ago: 300, lead_ms: @db_clock_lead_ms)

      assert {:ok, %Oban.Job{conflict?: true}} =
               Oban.insert(ReconcileAIReservationsWorker.new(%{}, unique: [period: 300]))
    end

    test "the configured window survives the same clock lead" do
      insert_completed_reconciler_job!(seconds_ago: 300, lead_ms: @db_clock_lead_ms)

      assert {:ok, %Oban.Job{conflict?: false}} =
               Oban.insert(ReconcileAIReservationsWorker.new(%{}))
    end

    test "the window still dedupes a tick genuinely inside it" do
      insert_completed_reconciler_job!(seconds_ago: 60)

      assert {:ok, %Oban.Job{conflict?: true}} =
               Oban.insert(ReconcileAIReservationsWorker.new(%{}))
    end
  end

  describe "database compute budget" do
    # The production database suspends its compute after five minutes without a
    # query, so any background poll finer than that pins it at 100% and burns the
    # monthly compute budget on an idle app. These are the guards for ENG-37.

    test "no scheduled job runs finer than the cadence floor" do
      for {worker, interval} <- scheduled_intervals() do
        assert interval >= @min_cron_interval_seconds,
               "#{inspect(worker)} runs every #{interval}s, below the #{@min_cron_interval_seconds}s " <>
                 "floor — it will keep the database compute from ever idling"
      end
    end

    test "staging does not poll finer than the cadence floor" do
      # Oban's default is one second. Staging is a query like any other.
      stage_interval = :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:stage_interval)

      assert stage_interval >= to_timeout(second: @min_cron_interval_seconds)
    end

    test "the notifier does not hold a connection open to wait" do
      # Postgres LISTEN/NOTIFY keeps a connection parked purely to receive.
      assert {Oban.Notifiers.PG, _} =
               :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:notifier)
    end
  end

  describe "stale managed reservations" do
    test "terminalizes a queued operation and files one critical alert", ctx do
      operation = execute!(ctx, "queued past its staleness window")
      assert operation.execution_status == "queued"
      reserve_stale!(operation, @stale_after + 1)

      assert :ok = ReconcileAIReservationsWorker.perform(%Oban.Job{})

      reconciled = Repo.get!(Operation, operation.id)
      assert reconciled.execution_status == "failed"
      assert reconciled.error_classification == "stale_reservation"
      assert reconciled.settlement_status == "released"
      refute Repo.get_by(Result, operation_id: operation.id)
      refute Repo.get_by(UsageEvent, operation_id: operation.id)

      assert %OperatorAlert{} = alert = Repo.get_by!(OperatorAlert, operation_id: operation.id)
      assert alert.kind == "stale_reservation"
      assert alert.severity == "critical"
      assert alert.dedupe_key == "stale-reservation:#{operation.id}"
    end

    test "terminalizes a running operation through the interruption recovery path", ctx do
      operation = execute!(ctx, "running past its staleness window")
      task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))
      assert {:ok, running, ^task, _route} = Operations.claim(operation.id)
      reserve_stale!(running, @stale_after + 1)

      assert :ok = ReconcileAIReservationsWorker.perform(%Oban.Job{})

      reconciled = Repo.get!(Operation, running.id)
      # `running` with no started attempt is the "interrupted before the provider
      # was ever called" branch, so it fails rather than going `unknown`.
      assert reconciled.execution_status == "failed"
      assert reconciled.error_classification == "worker_interrupted_before_attempt"
      assert reconciled.settlement_status == "released"
      refute Repo.get_by(UsageEvent, operation_id: running.id)
    end

    test "leaves an operation whose reservation is still inside the window alone", ctx do
      operation = execute!(ctx, "queued but recent")
      reserve_stale!(operation, @stale_after - 60)

      assert :ok = ReconcileAIReservationsWorker.perform(%Oban.Job{})

      untouched = Repo.get!(Operation, operation.id)
      assert untouched.execution_status == "queued"
      assert untouched.error_classification == nil
      assert Repo.aggregate(OperatorAlert, :count) == 0
    end

    test "ignores operations whose reservation is already settled", ctx do
      operation = execute!(ctx, "already settled")
      reservation = reserve_stale!(operation, @stale_after + 1)

      reservation
      |> AllowanceReservation.settle_changeset("released", TimeHelpers.now())
      |> Repo.update!()

      assert :ok = ReconcileAIReservationsWorker.perform(%Oban.Job{})

      assert Repo.get!(Operation, operation.id).execution_status == "queued"
      assert Repo.aggregate(OperatorAlert, :count) == 0
    end

    test "bounds both sweeps and resumes them from one fair continuation", ctx do
      Application.put_env(:storyarn, ReconcileAIReservationsWorker,
        stale_after_seconds: @stale_after,
        batch_size: 2
      )

      operations =
        for index <- 1..3 do
          operation = execute!(ctx, "stale batch #{index}")
          reserve_stale!(operation, @stale_after + 1)
          operation
        end

      expired_at = DateTime.add(TimeHelpers.now(), -60, :second)

      grants =
        for index <- 1..3 do
          owner = user_fixture()
          workspace = workspace_fixture(owner)

          assert {:ok, grant} =
                   Allowance.grant(workspace.id, owner.id, %{
                     grant_key: "reconciler-batch-#{index}",
                     kind: "one_time",
                     units: 1,
                     expires_at: expired_at
                   })

          grant
        end

      assert {:ok, root_job} = Oban.insert(ReconcileAIReservationsWorker.new(%{}))
      assert :ok = ReconcileAIReservationsWorker.perform(%Oban.Job{})

      [first_operation, second_operation, third_operation] = operations
      [first_grant, second_grant, third_grant] = grants

      assert Repo.get!(Operation, first_operation.id).execution_status == "failed"
      assert Repo.get!(Operation, second_operation.id).execution_status == "failed"
      assert Repo.get!(Operation, third_operation.id).execution_status == "queued"
      assert Repo.get!(AllowanceGrant, first_grant.id).remaining_units == 0
      assert Repo.get!(AllowanceGrant, second_grant.id).remaining_units == 0
      assert Repo.get!(AllowanceGrant, third_grant.id).remaining_units == 1

      followup =
        Repo.one!(
          from(job in Oban.Job,
            where: job.worker == ^inspect(ReconcileAIReservationsWorker),
            order_by: [desc: job.id],
            limit: 1
          )
        )

      assert followup.id == root_job.id
      assert followup.state == "available"
      assert followup.queue == "ai_maintenance"
      assert followup.args["after_operation_id"] == second_operation.id
      assert followup.args["after_account_id"] == second_grant.account_id
      assert is_binary(followup.args["sweep_started_at"])

      assert :ok = ReconcileAIReservationsWorker.perform(followup)

      assert Repo.get!(Operation, third_operation.id).execution_status == "failed"
      assert Repo.get!(AllowanceGrant, third_grant.id).remaining_units == 0
    end

    test "an aged colliding root job keeps done flags and the frozen sweep cutoff", ctx do
      Application.put_env(:storyarn, ReconcileAIReservationsWorker,
        stale_after_seconds: @stale_after,
        batch_size: 1
      )

      operations =
        for index <- 1..2 do
          operation = execute!(ctx, "colliding continuation #{index}")
          reserve_stale!(operation, @stale_after + 1)
          operation
        end

      sweep_started_at = TimeHelpers.now()
      sweep_started_at_arg = DateTime.to_iso8601(sweep_started_at)

      assert {:ok, root_job} = Oban.insert(ReconcileAIReservationsWorker.new(%{}))

      assert {1, nil} =
               Repo.update_all(
                 from(job in Oban.Job, where: job.id == ^root_job.id),
                 set: [inserted_at: DateTime.add(TimeHelpers.now(), -241, :second)]
               )

      assert :ok =
               ReconcileAIReservationsWorker.perform(%Oban.Job{
                 args: %{
                   "allowance_done" => true,
                   "sweep_started_at" => sweep_started_at_arg
                 }
               })

      [first_operation, _second_operation] = operations
      replaced_root_job = Repo.get!(Oban.Job, root_job.id)

      assert replaced_root_job.args == %{
               "after_operation_id" => first_operation.id,
               "allowance_done" => true,
               "sweep_started_at" => sweep_started_at_arg
             }

      assert Repo.aggregate(
               from(job in Oban.Job,
                 where: job.worker == ^inspect(ReconcileAIReservationsWorker)
               ),
               :count
             ) == 1
    end
  end

  defp execute!(ctx, text) do
    base = intent!(ctx, text)

    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(base)

    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               requested_route_ref: route_ref,
               idempotency_key: "op-#{System.unique_integer([:positive])}"
             })

    assert {:ok, operation} = AI.execute(intent)
    operation
  end

  defp intent!(ctx, text) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text}
             })

    intent
  end

  # The fake settlement adapter is deliberately non-financial and inserts no
  # reservation row, so the reaper's inner join has nothing to match. Seed the
  # row the managed adapter would have written, backdated past the cutoff.
  defp reserve_stale!(%Operation{} = operation, seconds_ago) do
    inserted_at = DateTime.add(TimeHelpers.now(), -seconds_ago, :second)

    %AllowanceReservation{}
    |> AllowanceReservation.create_changeset(%{
      operation_id: operation.id,
      workspace_id: operation.workspace_id,
      workspace_id_snapshot: operation.workspace_id_snapshot,
      price_id: "contract.echo",
      price_version: 1,
      units: 1,
      status: "reserved"
    })
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Ecto.Changeset.put_change(:updated_at, inserted_at)
    |> Repo.insert!()
  end

  defp insert_completed_reconciler_job!(opts) do
    seconds_ago = Keyword.fetch!(opts, :seconds_ago)
    lead_ms = Keyword.get(opts, :lead_ms, 0)

    inserted_at =
      DateTime.utc_now()
      |> DateTime.add(-seconds_ago, :second)
      |> DateTime.add(lead_ms, :millisecond)

    %{}
    |> ReconcileAIReservationsWorker.new()
    |> Ecto.Changeset.put_change(:state, "completed")
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Repo.insert!()
  end

  defp crontab do
    {Cron, opts} =
      :storyarn
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> Enum.find(&match?({Cron, _}, &1))

    Keyword.fetch!(opts, :crontab)
  end

  defp scheduled_intervals do
    Enum.map(crontab(), fn {expression, worker} -> {worker, cron_interval(expression)} end)
  end

  # Covers only the shapes the crontab actually uses. A new shape should fail
  # loudly here rather than be silently treated as "coarse enough".
  defp cron_interval(expression) do
    case String.split(expression, " ") do
      # A bare `*` in the minute field means every minute — it must be matched
      # before the literal-minute clause below, which would otherwise read it as
      # hourly and wave the worst case straight through.
      ["*", "*", "*", "*", "*"] -> 60
      ["*/" <> minutes, "*", "*", "*", "*"] -> String.to_integer(minutes) * 60
      [_minute, "*", "*", "*", "*"] -> 3600
      [_minute, "*/" <> hours, "*", "*", "*"] -> String.to_integer(hours) * 3600
      [_minute, _hour, "*", "*", "*"] -> 86_400
    end
  end
end

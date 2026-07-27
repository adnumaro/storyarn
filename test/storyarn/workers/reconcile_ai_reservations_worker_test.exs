defmodule Storyarn.Workers.ReconcileAIReservationsWorkerTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.Result
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workers.AIExecutionWorker
  alias Storyarn.Workers.ExpireAIResultsWorker
  alias Storyarn.Workers.ReconcileAIReservationsWorker
  alias StoryarnTest.AI.ContractTask

  @stale_after 900

  # A DB clock leading the app clock by tens of milliseconds is well within what
  # NTP-synced but separate machines drift to. Any positive lead larger than the
  # BEGIN round-trip reproduces the same result.
  @db_clock_lead_ms 50

  setup do
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
    test "the window stays strictly below the cron interval it is scheduled at" do
      assert Keyword.fetch!(ReconcileAIReservationsWorker.__opts__(), :unique)[:period] < 300
    end

    test "a window equal to the cron interval drops the next tick under a small clock lead" do
      # Positive control for the hazard itself. Oban stamps `inserted_at` from the
      # DB clock (Postgres `now()` at transaction start) but computes the window
      # cutoff from the app clock, with an inclusive `>=`. Two `*/5` ticks land
      # exactly 300s apart, so the second dedupes against the first as soon as the
      # DB clock leads the app clock by more than the BEGIN round-trip. The lead is
      # a property of the deployment, so simulate it rather than race it.
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
end

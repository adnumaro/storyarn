defmodule Storyarn.Repo.Migrations.SplitInvitationDeliveryWorkersObanContractTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Migration.Runner
  alias Storyarn.Platform.Adapters.Oban.QueueWakeup
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.SplitInvitationDeliveryWorkers
  alias Storyarn.Test.Migrations.ObanSchema

  @oban_name Storyarn.InvitationDeliveryCutoverOban
  @oban_schema_migration_version 20_260_829_110_000
  @cutover_migration_version 20_260_829_120_000
  @legacy_worker "Storyarn.Workers.DeliverInvitationWorker"
  @project_worker "Storyarn.Workers.DeliverProjectInvitationWorker"

  if !Code.ensure_loaded?(SplitInvitationDeliveryWorkers) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260829120000_split_invitation_delivery_workers.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "invitation_worker_oban_contract_#{System.unique_integer([:positive])}"

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("CREATE SCHEMA #{prefix}")

      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])

        assert :ok = run_migration(ObanSchema, @oban_schema_migration_version, :up, prefix)
        assert :ok = run_migration(SplitInvitationDeliveryWorkers, @cutover_migration_version, :up, prefix)
      end)
    end)

    on_exit(fn ->
      if oban_pid = Process.whereis(@oban_name), do: Supervisor.stop(oban_pid)
      Sandbox.checkin(Repo)
      Sandbox.unboxed_run(Repo, fn -> Repo.query!("DROP SCHEMA #{prefix} CASCADE") end)
    end)

    start_supervised!(
      {Oban, name: @oban_name, repo: Repo, prefix: prefix, testing: :manual, notifier: {Oban.Notifiers.Isolated, []}}
    )

    :ok = Sandbox.checkout(Repo)

    %{prefix: prefix}
  end

  test "legacy Oban insertion exposes the stale notification and the bounded wakeup compensates", %{
    prefix: prefix
  } do
    :ok = Oban.Notifier.listen(@oban_name, :insert)

    changeset =
      Oban.Job.new(
        %{"context" => "project", "encrypted_token" => "opaque", "locale" => "en"},
        worker: @legacy_worker,
        queue: :default,
        max_attempts: 5
      )

    assert {:ok, returned_job} = Oban.insert(@oban_name, changeset)

    assert returned_job.worker == @legacy_worker
    assert returned_job.queue == "default"
    assert_receive {:notification, :insert, %{"queue" => "default"}}

    persisted_job = Repo.get!(Oban.Job, returned_job.id, prefix: prefix)
    assert persisted_job.worker == @project_worker
    assert persisted_job.queue == "invitation_delivery"
    assert persisted_job.args["context"] == "project"

    pid =
      start_supervised!({QueueWakeup, oban_name: @oban_name, queue: :invitation_delivery, interval: 1, repetitions: 0})

    monitor = Process.monitor(pid)

    assert_receive {:notification, :insert, %{"queue" => "invitation_delivery"}}
    assert_receive {:DOWN, ^monitor, :process, ^pid, reason}
    assert reason in [:normal, :noproc]
  end

  test "retrying terminal legacy history routes it to the owner worker", %{prefix: prefix} do
    changeset =
      %{"context" => "project", "encrypted_token" => "opaque", "locale" => "en"}
      |> Oban.Job.new(
        worker: @legacy_worker,
        queue: :default,
        max_attempts: 5
      )
      |> Ecto.Changeset.put_change(:state, "discarded")
      |> Ecto.Changeset.put_change(:discarded_at, ~U[2026-08-29 00:00:00.000000Z])

    assert {:ok, terminal_job} = Oban.insert(@oban_name, changeset)
    assert Repo.get!(Oban.Job, terminal_job.id, prefix: prefix).worker == @legacy_worker

    assert :ok = Oban.retry_job(@oban_name, terminal_job)

    retried_job = Repo.get!(Oban.Job, terminal_job.id, prefix: prefix)
    assert retried_job.state == "available"
    assert retried_job.worker == @project_worker
    assert retried_job.queue == "invitation_delivery"
    assert retried_job.args["context"] == "project"
  end

  test "the cutover round-trips against Oban's complete schema", %{prefix: prefix} do
    owner_changeset =
      Oban.Job.new(
        %{"context" => "project", "encrypted_token" => "owner", "locale" => "en"},
        worker: @project_worker,
        queue: :invitation_delivery,
        max_attempts: 5
      )

    assert {:ok, owner_job} = Oban.insert(@oban_name, owner_changeset)
    assert :ok = run_cutover(:down, prefix)

    restored_owner_job = Repo.get!(Oban.Job, owner_job.id, prefix: prefix)
    assert restored_owner_job.worker == @legacy_worker
    assert restored_owner_job.queue == "default"
    assert restored_owner_job.args["context"] == "project"

    legacy_changeset =
      Oban.Job.new(
        %{"context" => "project", "encrypted_token" => "legacy", "locale" => "en"},
        worker: @legacy_worker,
        queue: :default,
        max_attempts: 5
      )

    assert {:ok, legacy_job} = Oban.insert(@oban_name, legacy_changeset)
    assert Repo.get!(Oban.Job, legacy_job.id, prefix: prefix).worker == @legacy_worker

    assert :ok = run_cutover(:up, prefix)

    for job_id <- [owner_job.id, legacy_job.id] do
      routed_job = Repo.get!(Oban.Job, job_id, prefix: prefix)
      assert routed_job.worker == @project_worker
      assert routed_job.queue == "invitation_delivery"
      assert routed_job.args["context"] == "project"
    end
  end

  defp run_cutover(direction, prefix) do
    case Repo.transaction(fn ->
           Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
           run_migration(SplitInvitationDeliveryWorkers, @cutover_migration_version, direction, prefix)
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_migration(module, version, direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      version,
      module,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end
end

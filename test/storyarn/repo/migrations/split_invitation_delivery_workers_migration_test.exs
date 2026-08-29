defmodule Storyarn.Repo.Migrations.SplitInvitationDeliveryWorkersMigrationTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Migration.Runner
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.SplitInvitationDeliveryWorkers

  @migration_version 20_260_829_120_000
  @legacy_worker "Storyarn.Workers.DeliverInvitationWorker"
  @project_worker "Storyarn.Workers.DeliverProjectInvitationWorker"
  @workspace_worker "Storyarn.Workers.DeliverWorkspaceInvitationWorker"
  @constraint "oban_jobs_invitation_worker_routing"
  @rollback_constraint "oban_jobs_invitation_worker_rollback_fence"
  @routing_trigger "storyarn_route_legacy_invitation_delivery_job"
  @lock_gate_timeout 10_000

  if !Code.ensure_loaded?(SplitInvitationDeliveryWorkers) do
    Code.require_file(
      Path.expand(
        "../../../../priv/repo/migrations/20260829120000_split_invitation_delivery_workers.exs",
        __DIR__
      )
    )
  end

  setup do
    prefix = "invitation_worker_cutover_#{System.unique_integer([:positive])}"

    Repo.query!("CREATE SCHEMA #{prefix}")
    create_jobs_table!(prefix)
    Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])

    %{prefix: prefix}
  end

  test "routes every non-executing incomplete legacy job without changing its payload or execution history", %{
    prefix: prefix
  } do
    rows = [
      {"available", "project", @project_worker},
      {"scheduled", "workspace", @workspace_worker},
      {"retryable", "project", @project_worker},
      {"suspended", "workspace", @workspace_worker}
    ]

    before =
      for {{state, context, _worker}, index} <- Enum.with_index(rows, 1) do
        id = insert_job!(prefix, state, context, index)
        {id, job_snapshot(prefix, id)}
      end

    assert :ok = run_migration(:up, prefix)

    for {{_state, _context, expected_worker}, {id, original}} <- Enum.zip(rows, before) do
      current = job_snapshot(prefix, id)

      assert current.worker == expected_worker
      assert current.queue == "invitation_delivery"
      assert Map.drop(current, [:worker, :queue]) == Map.drop(original, [:worker, :queue])
    end

    assert constraint_exists?(prefix)
    assert trigger_exists?(prefix)
  end

  test "cancels unknown active contexts and leaves terminal legacy history untouched", %{
    prefix: prefix
  } do
    unknown_id = insert_job!(prefix, "available", "unknown", 1)
    missing_id = insert_job!(prefix, "suspended", nil, 2)
    terminal_id = insert_job!(prefix, "completed", "project", 3)
    terminal_before = job_snapshot(prefix, terminal_id)

    assert :ok = run_migration(:up, prefix)

    for id <- [unknown_id, missing_id] do
      job = job_snapshot(prefix, id)
      assert job.worker == @legacy_worker
      assert job.state == "cancelled"
      assert %NaiveDateTime{} = job.cancelled_at
    end

    assert job_snapshot(prefix, terminal_id) == terminal_before
  end

  test "fails closed before rewriting anything while a legacy job is executing", %{
    prefix: prefix
  } do
    available_id = insert_job!(prefix, "available", "project", 1)
    executing_id = insert_job!(prefix, "executing", "workspace", 2)

    error = assert_raise Postgrex.Error, fn -> run_migration(:up, prefix) end

    assert error.postgres.code == :object_not_in_prerequisite_state
    assert error.postgres.pg_code == "55000"
    assert job_snapshot(prefix, available_id).worker == @legacy_worker
    assert job_snapshot(prefix, executing_id).worker == @legacy_worker
    refute constraint_exists?(prefix)
    refute trigger_exists?(prefix)
  end

  test "fails within the bounded timeout when another transaction holds oban_jobs" do
    prefix = "invitation_worker_lock_#{System.unique_integer([:positive])}"

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("CREATE SCHEMA #{prefix}")
      create_jobs_table!(prefix)

      parent = self()
      barrier = make_ref()

      gate =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.query!("LOCK TABLE #{prefix}.oban_jobs IN ACCESS SHARE MODE")
              send(parent, {barrier, :locked})

              receive do
                {^barrier, :release} -> :released
              after
                @lock_gate_timeout -> exit(:invitation_worker_lock_release_timeout)
              end
            end)
          end)
        end)

      try do
        assert_receive {^barrier, :locked}, @lock_gate_timeout

        error =
          assert_raise Postgrex.Error, fn ->
            Repo.transaction(fn ->
              Repo.query!("SELECT set_config('search_path', $1, true)", ["#{prefix}, public"])
              run_migration(:up, prefix)
            end)
          end

        assert error.postgres.code == :lock_not_available
        assert error.postgres.pg_code == "55P03"
        refute constraint_exists?(prefix)
        refute trigger_exists?(prefix)
      after
        send(gate.pid, {barrier, :release})
        assert {:ok, :released} = Task.await(gate, @lock_gate_timeout)
        Repo.query!("DROP SCHEMA #{prefix} CASCADE")
      end
    end)
  end

  test "rolling ingress rewrites jobs from an older node before the routing fence", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    project_id =
      insert_raw_job!(prefix, @legacy_worker, "default", "available", %{"context" => "project"})

    workspace_id =
      insert_raw_job!(prefix, @legacy_worker, "default", "scheduled", %{"context" => "workspace"})

    assert %{worker: @project_worker, queue: "invitation_delivery", state: "available"} =
             job_snapshot(prefix, project_id)

    assert %{worker: @workspace_worker, queue: "invitation_delivery", state: "scheduled"} =
             job_snapshot(prefix, workspace_id)

    assert_check_violation(fn ->
      insert_raw_job(prefix, @legacy_worker, "default", "retryable", %{"context" => "unknown"})
    end)
  end

  test "routing fence pins each owner worker to its context and queue but allows terminal history", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    for {worker, context, foreign_context} <- [
          {@project_worker, "project", "workspace"},
          {@workspace_worker, "workspace", "project"}
        ] do
      assert_check_violation(fn ->
        insert_raw_job(prefix, worker, "default", "retryable", %{"context" => context})
      end)

      assert_check_violation(fn ->
        insert_raw_job(prefix, worker, "invitation_delivery", "retryable", %{
          "context" => foreign_context
        })
      end)

      assert_check_violation(fn ->
        insert_raw_job(prefix, worker, "invitation_delivery", "retryable", %{})
      end)

      assert {:ok, _result} =
               insert_raw_job(
                 prefix,
                 worker,
                 "invitation_delivery",
                 "suspended",
                 %{"context" => context}
               )

      assert {:ok, _result} =
               insert_raw_job(prefix, worker, "default", "completed", %{"context" => "project"})
    end

    assert {:ok, _result} =
             insert_raw_job(prefix, @legacy_worker, "default", "discarded", %{"context" => "project"})
  end

  test "rollback fails closed for executing owner jobs then restores all owner job identities", %{
    prefix: prefix
  } do
    assert :ok = run_migration(:up, prefix)

    project_id =
      insert_raw_job!(
        prefix,
        @project_worker,
        "invitation_delivery",
        "scheduled",
        %{"encrypted_token" => "project-token", "context" => "project"}
      )

    terminal_id =
      insert_raw_job!(
        prefix,
        @workspace_worker,
        "invitation_delivery",
        "completed",
        %{"encrypted_token" => "workspace-token", "context" => "stale"}
      )

    executing_id =
      insert_raw_job!(
        prefix,
        @workspace_worker,
        "invitation_delivery",
        "executing",
        %{"context" => "workspace"}
      )

    error = assert_raise Postgrex.Error, fn -> run_migration(:down, prefix) end
    assert error.postgres.code == :object_not_in_prerequisite_state
    assert constraint_exists?(prefix)
    assert job_snapshot(prefix, executing_id).worker == @workspace_worker

    Repo.query!("UPDATE #{prefix}.oban_jobs SET state = 'available' WHERE id = $1", [executing_id])

    project_before = job_snapshot(prefix, project_id)
    terminal_before = job_snapshot(prefix, terminal_id)

    assert :ok = run_migration(:down, prefix)
    refute constraint_exists?(prefix)
    assert rollback_constraint_exists?(prefix)
    refute trigger_exists?(prefix)

    project = job_snapshot(prefix, project_id)
    terminal = job_snapshot(prefix, terminal_id)

    assert project.worker == @legacy_worker
    assert project.queue == "default"
    assert project.state == project_before.state
    assert project.args["context"] == "project"

    assert Map.drop(project, [:worker, :queue, :args]) ==
             Map.drop(project_before, [:worker, :queue, :args])

    assert terminal.worker == @legacy_worker
    assert terminal.queue == "default"
    assert terminal.state == terminal_before.state
    assert terminal.args["context"] == "workspace"

    assert Map.drop(terminal, [:worker, :queue, :args]) ==
             Map.drop(terminal_before, [:worker, :queue, :args])

    legacy_id =
      insert_raw_job!(prefix, @legacy_worker, "default", "available", %{"context" => "project"})

    assert %{worker: @legacy_worker, queue: "default", state: "available"} =
             job_snapshot(prefix, legacy_id)

    assert_check_violation(fn ->
      insert_raw_job(
        prefix,
        @project_worker,
        "invitation_delivery",
        "available",
        %{"context" => "project"}
      )
    end)

    assert :ok = run_migration(:up, prefix)
    refute rollback_constraint_exists?(prefix)
    assert constraint_exists?(prefix)
    assert trigger_exists?(prefix)

    assert %{worker: @project_worker, queue: "invitation_delivery", state: "available"} =
             job_snapshot(prefix, legacy_id)
  end

  defp create_jobs_table!(prefix) do
    Repo.query!("""
    CREATE TABLE #{prefix}.oban_jobs (
      id bigserial PRIMARY KEY,
      state text NOT NULL,
      queue text NOT NULL,
      worker text NOT NULL,
      args jsonb NOT NULL DEFAULT '{}'::jsonb,
      attempt integer NOT NULL DEFAULT 0,
      max_attempts integer NOT NULL DEFAULT 20,
      inserted_at timestamp(6) without time zone NOT NULL,
      scheduled_at timestamp(6) without time zone NOT NULL,
      attempted_at timestamp(6) without time zone,
      completed_at timestamp(6) without time zone,
      discarded_at timestamp(6) without time zone,
      cancelled_at timestamp(6) without time zone
    )
    """)
  end

  defp insert_job!(prefix, state, context, index) do
    args = maybe_put_context(%{"encrypted_token" => "token-#{index}", "locale" => "es", "sequence" => index}, context)

    inserted_at = ~N[2026-08-20 10:00:00.123456]
    scheduled_at = NaiveDateTime.add(inserted_at, index * 60)
    attempted_at = if state == "retryable", do: NaiveDateTime.add(inserted_at, index)

    %Postgrex.Result{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO #{prefix}.oban_jobs (
          state, queue, worker, args, attempt, max_attempts,
          inserted_at, scheduled_at, attempted_at
        )
        VALUES ($1, 'default', $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
        """,
        [
          state,
          @legacy_worker,
          args,
          index,
          index + 5,
          inserted_at,
          scheduled_at,
          attempted_at
        ]
      )

    id
  end

  defp insert_raw_job(prefix, worker, queue, state, args) do
    Repo.query(
      """
      INSERT INTO #{prefix}.oban_jobs (
        state, queue, worker, args, inserted_at, scheduled_at
      )
      VALUES ($1, $2, $3, $4, $5, $5)
      RETURNING id
      """,
      [state, queue, worker, args, ~N[2026-08-20 10:00:00.123456]],
      mode: :savepoint
    )
  end

  defp insert_raw_job!(prefix, worker, queue, state, args) do
    assert {:ok, %Postgrex.Result{rows: [[id]]}} =
             insert_raw_job(prefix, worker, queue, state, args)

    id
  end

  defp job_snapshot(prefix, id) do
    %Postgrex.Result{
      columns: columns,
      rows: [row]
    } =
      Repo.query!(
        """
        SELECT worker, queue, state, args, attempt, max_attempts,
               inserted_at, scheduled_at, attempted_at, completed_at,
               discarded_at, cancelled_at
        FROM #{prefix}.oban_jobs
        WHERE id = $1
        """,
        [id]
      )

    columns
    |> Enum.map(&String.to_existing_atom/1)
    |> Enum.zip(row)
    |> Map.new()
  end

  defp maybe_put_context(args, nil), do: args
  defp maybe_put_context(args, context), do: Map.put(args, "context", context)

  defp constraint_exists?(prefix) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
      )
      """,
      [prefix, @constraint]
    ).rows == [[true]]
  end

  defp rollback_constraint_exists?(prefix) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM pg_constraint AS constraint_row
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = $1 AND constraint_row.conname = $2
      )
      """,
      [prefix, @rollback_constraint]
    ).rows == [[true]]
  end

  defp trigger_exists?(prefix) do
    Repo.query!(
      """
      SELECT EXISTS (
        SELECT 1
        FROM pg_trigger AS trigger_row
        JOIN pg_class AS table_row ON table_row.oid = trigger_row.tgrelid
        JOIN pg_namespace AS namespace_row ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = $1
          AND table_row.relname = 'oban_jobs'
          AND trigger_row.tgname = $2
          AND NOT trigger_row.tgisinternal
      )
      """,
      [prefix, @routing_trigger]
    ).rows == [[true]]
  end

  defp assert_check_violation(fun) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} = fun.()
  end

  defp run_migration(direction, prefix) do
    Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      SplitInvitationDeliveryWorkers,
      :forward,
      direction,
      direction,
      prefix: prefix,
      log: false
    )
  end
end

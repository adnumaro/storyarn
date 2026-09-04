defmodule Storyarn.Workers.ProjectSnapshotCleanupWorkersTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SnapshotReconciliationTestHelpers, only: [process_cleanup_until_boundary: 2]

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.CleanupProjectSnapshotWorker
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker
  alias Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker

  test "cleanup worker discards missing and invalid durable intent identities" do
    assert {:discard, :snapshot_cleanup_intent_not_found} =
             CleanupProjectSnapshotWorker.perform(%Oban.Job{
               args: %{"intent_id" => 9_223_372_036_854_775_807},
               attempt: 1,
               max_attempts: 10
             })

    assert {:discard, :invalid_snapshot_cleanup_intent} =
             CleanupProjectSnapshotWorker.perform(%Oban.Job{
               args: %{"intent_id" => -1},
               attempt: 1,
               max_attempts: 10
             })
  end

  test "cleanup worker backoff is exponential and capped" do
    assert CleanupProjectSnapshotWorker.backoff(%Oban.Job{attempt: 1}) == 300
    assert CleanupProjectSnapshotWorker.backoff(%Oban.Job{attempt: 2}) == 600
    assert CleanupProjectSnapshotWorker.backoff(%Oban.Job{attempt: 8}) == 21_600
    assert CleanupProjectSnapshotWorker.backoff(%Oban.Job{attempt: 100}) == 21_600
    assert CleanupProjectSnapshotWorker.timeout(%Oban.Job{}) == 2 * 60 * 60 * 1_000
  end

  test "maintenance roots suppress immediate duplicates but allow the next bounded sweep" do
    for worker <- [ReconcileProjectSnapshotCleanupWorker, ProjectSnapshotRetentionWorker] do
      unique = Keyword.fetch!(worker.__opts__(), :unique)

      assert Keyword.fetch!(unique, :fields) == [:worker, :args]
      assert Keyword.fetch!(unique, :period) == 600
      refute :completed in Keyword.fetch!(unique, :states)
      assert worker.timeout(%Oban.Job{}) == 10 * 60 * 1_000

      args = %{sweep: "#{inspect(worker)}-#{System.unique_integer([:positive])}"}
      assert {:ok, first} = args |> worker.new() |> Oban.insert()
      assert {:ok, %Oban.Job{conflict?: true}} = args |> worker.new() |> Oban.insert()

      first
      |> Ecto.Changeset.change(inserted_at: %{DateTime.add(TimeHelpers.now(), -601, :second) | microsecond: {0, 6}})
      |> Repo.update!()

      assert {:ok, %Oban.Job{conflict?: false}} = args |> worker.new() |> Oban.insert()
    end
  end

  test "maintenance reaper is scoped by worker, queue, state, and age" do
    stale_at = DateTime.add(TimeHelpers.now(), -31 * 60, :second)
    recent_at = DateTime.add(TimeHelpers.now(), -29 * 60, :second)

    stale = executing_job!(ProjectSnapshotRetentionWorker, %{}, attempted_at: stale_at)
    recent = executing_job!(ProjectSnapshotRetentionWorker, %{cursor: 1}, attempted_at: recent_at)

    wrong_queue =
      executing_job!(ProjectSnapshotRetentionWorker, %{cursor: 2},
        attempted_at: stale_at,
        queue: "default"
      )

    foreign =
      executing_job!(BuildProjectSnapshotWorker, %{snapshot_id: 9_223_372_036_854_775_807}, attempted_at: stale_at)

    assert %{discarded_count: 1} = Versioning.discard_stale_project_snapshot_maintenance_jobs()
    assert Repo.get!(Oban.Job, stale.id).state == "discarded"
    assert Repo.get!(Oban.Job, recent.id).state == "executing"
    assert Repo.get!(Oban.Job, wrong_queue.id).state == "executing"
    assert Repo.get!(Oban.Job, foreign.id).state == "executing"
  end

  test "reconciler restores a nonterminal intent whose cleanup job is dead" do
    intent = cleanup_intent_fixture(0)
    terminal_intent = cleanup_intent_fixture(0, seed_content: "terminal cleanup")
    handler_id = "snapshot-cleanup-recovery-#{System.unique_integer([:positive])}"
    parent = self()

    expire_initial_handoff!(terminal_intent)

    assert {:ok, :terminal} =
             process_cleanup_until_boundary(terminal_intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    assert {:ok, dead_job} =
             %{intent_id: intent.id}
             |> CleanupProjectSnapshotWorker.new()
             |> Oban.insert()

    dead_job |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:storyarn, :snapshot, :cleanup, :recovery, :stop],
          [:storyarn, :snapshot, :cleanup, :backlog]
        ],
        fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok =
             ReconcileProjectSnapshotCleanupWorker.perform(%Oban.Job{
               args: %{},
               attempt: 1,
               max_attempts: 5
             })

    assert_enqueued(worker: CleanupProjectSnapshotWorker, args: %{intent_id: intent.id})

    assert_receive {
      [:storyarn, :snapshot, :cleanup, :recovery, :stop],
      %{
        recovered_count: 1,
        failure_count: 0,
        continuation_count: 0
      },
      %{status: :ok}
    }

    assert_receive {
      [:storyarn, :snapshot, :cleanup, :backlog],
      %{
        terminal_retry_count: 1,
        repeated_terminal_failures: 0,
        observed_at_unix_seconds: observed_at
      },
      %{}
    }

    assert is_integer(observed_at)
  end

  test "recovery ignores a cleanup worker stranded on the wrong queue" do
    intent = cleanup_intent_fixture(0)

    wrong_queue_job =
      %{intent_id: intent.id}
      |> CleanupProjectSnapshotWorker.new()
      |> Ecto.Changeset.put_change(:queue, "snapshots")
      |> Repo.insert!()

    assert intent.id in Versioning.list_project_snapshot_cleanup_recovery_candidates()
    assert {:ok, :recovered} = Versioning.recover_project_snapshot_cleanup_intent(intent.id)

    assert Repo.exists?(
             from(job in Oban.Job,
               where:
                 job.id != ^wrong_queue_job.id and job.worker == ^wrong_queue_job.worker and
                   job.queue == "storage_cleanup" and
                   fragment("(?->>'intent_id') = ?", job.args, ^Integer.to_string(intent.id))
             )
           )
  end

  test "reconciler rescues stale executing cleanup jobs with attempts remaining" do
    intent = cleanup_intent_fixture(0)

    stale_job =
      executing_job!(CleanupProjectSnapshotWorker, %{intent_id: intent.id},
        attempted_at: DateTime.add(TimeHelpers.now(), -4 * 60 * 60, :second),
        attempt: 3
      )

    assert :ok = perform_reconciler()

    assert %Oban.Job{state: "available", attempt: 3} = Repo.get!(Oban.Job, stale_job.id)

    assert [%Oban.Job{id: recovered_id}] =
             all_enqueued(worker: CleanupProjectSnapshotWorker, args: %{intent_id: intent.id})

    assert recovered_id == stale_job.id
  end

  test "reconciler leaves stale executing jobs from other workers untouched" do
    stale_job =
      executing_job!(BuildProjectSnapshotWorker, %{snapshot_id: 9_223_372_036_854_775_807},
        attempted_at: DateTime.add(TimeHelpers.now(), -4 * 60 * 60, :second),
        attempt: 3
      )

    assert :ok = perform_reconciler()

    assert %Oban.Job{state: "executing", attempt: 3} = Repo.get!(Oban.Job, stale_job.id)
  end

  test "reconciler leaves recent executing cleanup jobs untouched" do
    intent = cleanup_intent_fixture(0)

    recent_job =
      executing_job!(CleanupProjectSnapshotWorker, %{intent_id: intent.id},
        attempted_at: DateTime.add(TimeHelpers.now(), -60 * 60, :second),
        attempt: 3
      )

    assert :ok = perform_reconciler()

    assert %Oban.Job{state: "executing", attempt: 3} = Repo.get!(Oban.Job, recent_job.id)
    assert Versioning.list_project_snapshot_cleanup_recovery_candidates(through_id: intent.id) == []
  end

  test "reconciler discards exhausted stale cleanup jobs and restores their durable intent" do
    intent = cleanup_intent_fixture(0)

    stale_job =
      executing_job!(CleanupProjectSnapshotWorker, %{intent_id: intent.id},
        attempted_at: DateTime.add(TimeHelpers.now(), -4 * 60 * 60, :second),
        attempt: 10,
        max_attempts: 10
      )

    assert :ok = perform_reconciler()

    assert %Oban.Job{state: "discarded", discarded_at: %DateTime{}} = Repo.get!(Oban.Job, stale_job.id)

    assert [%Oban.Job{id: recovered_id, state: "available"}] =
             all_enqueued(worker: CleanupProjectSnapshotWorker, args: %{intent_id: intent.id})

    refute recovered_id == stale_job.id
  end

  test "reconciler ignores an intent while any active cleanup continuation owns it" do
    intent = cleanup_intent_fixture(0)

    assert {:ok, _job} =
             %{intent_id: intent.id, continuation: 7}
             |> CleanupProjectSnapshotWorker.new()
             |> Oban.insert()

    assert Versioning.list_project_snapshot_cleanup_recovery_candidates(through_id: intent.id) == []
  end

  test "reconciler hands invalid ownership to a worker that can terminalize it" do
    intent = cleanup_intent_fixture(0, invalid_ownership?: true)

    assert :ok =
             ReconcileProjectSnapshotCleanupWorker.perform(%Oban.Job{
               args: %{},
               attempt: 1,
               max_attempts: 5
             })

    assert [%Oban.Job{} = cleanup_job] =
             all_enqueued(worker: CleanupProjectSnapshotWorker, args: %{intent_id: intent.id})

    assert :ok = CleanupProjectSnapshotWorker.perform(%{cleanup_job | attempt: 10, max_attempts: 10})

    assert %SnapshotCleanupIntent{
             status: "terminal",
             last_error_code: "invalid_ownership",
             remaining_storage_keys: remaining
           } = Repo.get!(SnapshotCleanupIntent, intent.id)

    assert remaining == intent.storage_keys
  end

  test "terminal cleanup logs an actionable operator replay command and preserves failures" do
    intent = cleanup_intent_fixture(0)

    failed_key =
      Enum.find(intent.storage_keys, &String.ends_with?(&1, "/ready/cleanupTest00001/manifest.json"))

    storage_path = storage_path(failed_key)
    File.mkdir_p!(storage_path)
    on_exit(fn -> File.rmdir(storage_path) end)

    expire_initial_handoff!(intent)

    log =
      capture_log(fn ->
        assert :ok = perform_cleanup_worker_until_boundary(cleanup_job(intent.id))
      end)

    assert log =~ "Snapshot cleanup exhausted retries intent_id=#{intent.id}"
    assert log =~ "Versioning.replay_terminal_project_snapshot_cleanup(#{intent.id})"

    assert %SnapshotCleanupIntent{status: "terminal", remaining_storage_keys: remaining} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert failed_key in remaining
    assert remaining == intent.storage_keys
  end

  test "cleanup cannot report progress while a snapshot row still owns its namespace" do
    intent = cleanup_intent_fixture(0, archive?: true)

    assert {:error, :snapshot_cleanup_namespace_still_owned} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id)

    assert %SnapshotCleanupIntent{status: "processing", remaining_storage_keys: remaining} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert remaining == intent.storage_keys

    assert {:ok, :terminal} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id, final_attempt?: true)

    assert %SnapshotCleanupIntent{
             status: "terminal",
             last_error_code: "namespace_still_owned",
             remaining_storage_keys: ^remaining
           } = Repo.get!(SnapshotCleanupIntent, intent.id)
  end

  test "a superseded cleanup claim cannot apply a stale terminal result" do
    intent = cleanup_intent_fixture(0, seed_content: "stale claim")
    test_process = self()

    expire_initial_handoff!(intent)

    stale_worker =
      Task.async(fn ->
        process_cleanup_until_boundary(intent.id,
          final_attempt?: true,
          delete_fun: fn keys ->
            send(test_process, {:stale_claim_started, self()})
            receive do: (:resume_stale_claim -> {:error, keys})
          end
        )
      end)

    assert_receive {:stale_claim_started, stale_worker_pid}
    generation_before = Repo.get!(SnapshotCleanupIntent, intent.id).processing_generation

    assert {:ok, {:deferred, seconds}} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id,
               delete_fun: fn _keys -> flunk("the active provider claim must defer a second delivery") end
             )

    assert seconds > 0

    assert %SnapshotCleanupIntent{status: "processing", processing_generation: generation_after} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert generation_after == generation_before + 1

    send(stale_worker_pid, :resume_stale_claim)
    assert {:ok, :stale_claim} = Task.await(stale_worker)

    assert %SnapshotCleanupIntent{status: "processing", processing_generation: ^generation_after} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert {:ok, {:deferred, seconds}} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id)

    assert seconds > 0
  end

  test "cleanup fails closed when its durable ownership receipt does not match" do
    intent = cleanup_intent_fixture(0, invalid_ownership?: true)

    assert {:error, :invalid_snapshot_cleanup_ownership} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id)

    assert %SnapshotCleanupIntent{status: "pending", remaining_storage_keys: remaining} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert remaining == intent.storage_keys

    log =
      capture_log(fn ->
        assert :ok =
                 CleanupProjectSnapshotWorker.perform(%Oban.Job{
                   args: %{"intent_id" => intent.id},
                   attempt: 10,
                   max_attempts: 10
                 })
      end)

    assert log =~ "Snapshot cleanup integrity failure requires manual repair intent_id=#{intent.id}"
    assert log =~ "error_code=invalid_ownership automatic_replay=disabled"
    refute log =~ "replay_terminal_project_snapshot_cleanup"

    assert {:error, {:snapshot_cleanup_manual_repair_required, "invalid_ownership"}} =
             Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

    assert %SnapshotCleanupIntent{
             status: "terminal",
             last_error_code: "invalid_ownership",
             remaining_storage_keys: ^remaining
           } = Repo.get!(SnapshotCleanupIntent, intent.id)
  end

  test "a malformed immutable inventory becomes terminal on the final worker attempt" do
    intent = cleanup_intent_fixture(0, invalid_inventory?: true)

    assert {:error, :invalid_snapshot_cleanup_inventory} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id)

    assert %SnapshotCleanupIntent{status: "pending", remaining_storage_keys: remaining} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert remaining == intent.storage_keys

    log =
      capture_log(fn ->
        assert :ok =
                 CleanupProjectSnapshotWorker.perform(%Oban.Job{
                   args: %{"intent_id" => intent.id},
                   attempt: 10,
                   max_attempts: 10
                 })
      end)

    assert log =~ "Snapshot cleanup integrity failure requires manual repair intent_id=#{intent.id}"
    assert log =~ "error_code=invalid_inventory automatic_replay=disabled"
    refute log =~ "replay_terminal_project_snapshot_cleanup"

    assert {:error, {:snapshot_cleanup_manual_repair_required, "invalid_inventory"}} =
             Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

    assert %SnapshotCleanupIntent{
             status: "terminal",
             last_error_code: "invalid_inventory",
             remaining_storage_keys: ^remaining
           } = Repo.get!(SnapshotCleanupIntent, intent.id)
  end

  test "database rejects an initial cleanup inventory that is not exact" do
    intent = cleanup_intent_fixture(0)
    Repo.delete!(intent)

    invalid_attrs =
      intent
      |> raw_intent_attrs()
      |> Map.put(:remaining_storage_keys, tl(intent.storage_keys))

    assert_raise Postgrex.Error,
                 ~r/snapshot cleanup initial inventory must be exact, non-null, and unique/,
                 fn -> Repo.insert_all(SnapshotCleanupIntent, [invalid_attrs]) end
  end

  test "database rejects nulls in an initial cleanup inventory" do
    intent = cleanup_intent_fixture(0)
    Repo.delete!(intent)
    storage_keys = [nil | tl(intent.storage_keys)]

    invalid_attrs =
      intent
      |> raw_intent_attrs()
      |> Map.put(:storage_keys, storage_keys)
      |> Map.put(:remaining_storage_keys, storage_keys)

    assert_raise Postgrex.Error,
                 ~r/snapshot cleanup initial inventory must be exact, non-null, and unique/,
                 fn -> Repo.insert_all(SnapshotCleanupIntent, [invalid_attrs]) end
  end

  test "database rejects duplicate keys in an initial cleanup inventory" do
    intent = cleanup_intent_fixture(0)
    Repo.delete!(intent)
    [first_key | remaining_keys] = intent.storage_keys
    storage_keys = [first_key, first_key | tl(remaining_keys)]

    invalid_attrs =
      intent
      |> raw_intent_attrs()
      |> Map.put(:storage_keys, storage_keys)
      |> Map.put(:remaining_storage_keys, storage_keys)

    assert_raise Postgrex.Error,
                 ~r/snapshot cleanup initial inventory must be exact, non-null, and unique/,
                 fn -> Repo.insert_all(SnapshotCleanupIntent, [invalid_attrs]) end
  end

  test "database never allows a removed cleanup key to be reintroduced" do
    intent = cleanup_intent_fixture(0)
    remaining_storage_keys = tl(intent.storage_keys)

    Repo.query!(
      "UPDATE snapshot_cleanup_intents SET remaining_storage_keys = $1 WHERE id = $2",
      [remaining_storage_keys, intent.id]
    )

    assert_raise Postgrex.Error,
                 ~r/snapshot cleanup remaining inventory can only shrink/,
                 fn ->
                   Repo.query!(
                     "UPDATE snapshot_cleanup_intents SET remaining_storage_keys = $1 WHERE id = $2",
                     [intent.storage_keys, intent.id]
                   )
                 end
  end

  test "database rejects inventory progress disguised as a processing claim" do
    intent = cleanup_intent_fixture(0)
    [_removed | remaining] = intent.remaining_storage_keys

    assert_raise Postgrex.Error,
                 ~r/processing generation must advance on an exact claim/,
                 fn ->
                   Repo.query!(
                     "UPDATE snapshot_cleanup_intents SET status = 'processing', processing_generation = processing_generation + 1, remaining_storage_keys = $1 WHERE id = $2",
                     [remaining, intent.id]
                   )
                 end
  end

  defp cleanup_intent_fixture(_blob_count, opts \\ []) do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    archive? = Keyword.get(opts, :archive?, false)
    token = "cleanupTest00001"

    {ready_prefix, staging_prefix} =
      if archive? do
        {
          snapshot.object_prefix,
          String.replace(snapshot.object_prefix, "/ready/", "/staging/", global: false)
        }
      else
        {
          SnapshotArchiveStorage.ready_prefix(project.id, token),
          SnapshotArchiveStorage.staging_prefix(project.id, token)
        }
      end

    paths = ["manifest.json", "snapshot.zip"]

    storage_keys =
      Enum.map(paths, &"#{ready_prefix}/#{&1}") ++
        Enum.map(paths, &"#{staging_prefix}/#{&1}")

    # Bind the cleanup ownership to an existing local namespace. Creating the
    # configured root after the handoff is intentionally a namespace change.
    File.mkdir_p!(Path.dirname(storage_path("namespace-probe")))

    if content = Keyword.get(opts, :seed_content) do
      storage_key = hd(storage_keys)
      assert {:ok, _url} = Storage.upload(storage_key, content, "application/octet-stream")
      on_exit(fn -> Storage.delete(storage_key) end)
    end

    assert {:ok, provider_namespace_fingerprint} = Storage.namespace_fingerprint()

    receipt_storage_keys =
      if Keyword.get(opts, :invalid_ownership?, false),
        do: storage_keys ++ ["projects/999/assets/#{Ecto.UUID.generate()}/foreign.bin"],
        else: storage_keys

    assert {:ok, cleanup_request} =
             StorageCompensation.persist_snapshot_lifecycle_cleanup(
               receipt_storage_keys,
               Ecto.UUID.generate(),
               provider_namespace_fingerprint
             )

    attrs = %{
      project_snapshot_id: snapshot.id,
      cleanup_request_id: cleanup_request.id,
      workspace_id_snapshot: project.workspace_id,
      project_id_snapshot: project.id,
      project_snapshot_id_snapshot: snapshot.id,
      deletion_generation: snapshot.lifecycle_generation,
      mode: "full",
      origin: "user",
      reason: "user_delete",
      authority_kind: "user",
      authority_actor_id: user.id,
      ready_prefix: ready_prefix,
      staging_prefix: staging_prefix,
      storage_keys: storage_keys,
      inventory_digest: inventory_digest(storage_keys),
      object_count: length(storage_keys),
      estimated_cleanup_bytes: length(storage_keys),
      provider_namespace_fingerprint: provider_namespace_fingerprint,
      requested_at: TimeHelpers.now()
    }

    if Keyword.get(opts, :invalid_inventory?, false) do
      now = TimeHelpers.now()
      invalid_digest = corrupt_digest(attrs.inventory_digest)

      raw_attrs =
        attrs
        |> Map.put(:inventory_digest, invalid_digest)
        |> Map.put(:remaining_storage_keys, storage_keys)
        |> Map.put(:status, "pending")
        |> Map.put(:retry_count, 0)
        |> Map.put(:required_delete_passes, 1)
        |> Map.put(:completed_delete_passes, 0)
        |> Map.put(:processing_generation, 0)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)

      assert {1, [%{id: intent_id}]} =
               Repo.insert_all(SnapshotCleanupIntent, [raw_attrs], returning: [:id])

      Repo.get!(SnapshotCleanupIntent, intent_id)
    else
      %SnapshotCleanupIntent{}
      |> SnapshotCleanupIntent.create_changeset(attrs)
      |> Repo.insert!()
    end
  end

  defp corrupt_digest(<<first, rest::binary>>) when first == ?0, do: "1" <> rest
  defp corrupt_digest(<<_first, rest::binary>>), do: "0" <> rest

  defp executing_job!(worker, args, opts) do
    attempted_at = %{Keyword.fetch!(opts, :attempted_at) | microsecond: {0, 6}}
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 10)

    changeset = worker.new(args, max_attempts: max_attempts)

    changeset =
      case Keyword.get(opts, :queue) do
        queue when is_binary(queue) -> Ecto.Changeset.put_change(changeset, :queue, queue)
        _default -> changeset
      end

    changeset
    |> Ecto.Changeset.put_change(:state, "executing")
    |> Ecto.Changeset.put_change(:attempt, attempt)
    |> Ecto.Changeset.put_change(:attempted_at, attempted_at)
    |> Repo.insert!()
  end

  defp perform_reconciler do
    ReconcileProjectSnapshotCleanupWorker.perform(%Oban.Job{
      args: %{},
      attempt: 1,
      max_attempts: 5
    })
  end

  defp expire_initial_handoff!(intent) do
    request = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)
    assert request.multipart_cleanup_phase == "discover"
    assert request.multipart_cleanup_generation == 0
    now = TimeHelpers.now()

    request
    |> StorageCleanupRequest.multipart_quiescence_changeset(
      DateTime.add(now, -2, :second),
      DateTime.add(now, -1, :second)
    )
    |> Repo.update!()
  end

  defp cleanup_job(intent_id) do
    %Oban.Job{
      args: %{"intent_id" => intent_id},
      attempt: 10,
      max_attempts: 10
    }
  end

  defp perform_cleanup_worker_until_boundary(job, attempts_left \\ 100)

  defp perform_cleanup_worker_until_boundary(job, attempts_left) when attempts_left > 0 do
    case CleanupProjectSnapshotWorker.perform(job) do
      {:snooze, 1} -> perform_cleanup_worker_until_boundary(job, attempts_left - 1)
      result -> result
    end
  end

  defp perform_cleanup_worker_until_boundary(_job, 0),
    do: flunk("snapshot cleanup worker did not reach a durable delivery boundary")

  defp raw_intent_attrs(intent) do
    intent
    |> Map.from_struct()
    |> Map.take(SnapshotCleanupIntent.__schema__(:fields) -- [:id])
  end

  defp inventory_digest(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn key -> "#{byte_size(key)}:#{key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp storage_path(storage_key) do
    :storyarn
    |> Application.fetch_env!(:storage)
    |> Keyword.fetch!(:upload_dir)
    |> Path.expand()
    |> Path.join(storage_key)
  end
end

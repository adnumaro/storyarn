defmodule Storyarn.Workers.ProjectSnapshotCleanupWorkersTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Workers.CleanupProjectSnapshotWorker
  alias Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker

  test "a large cleanup continues immediately through another available job" do
    intent = cleanup_intent_fixture(49)

    assert :ok =
             CleanupProjectSnapshotWorker.perform(%Oban.Job{
               args: %{"intent_id" => intent.id},
               attempt: 1,
               max_attempts: 10
             })

    assert %SnapshotCleanupIntent{status: "processing", remaining_storage_keys: remaining} =
             Repo.get!(SnapshotCleanupIntent, intent.id)

    assert length(remaining) == 2

    assert [%Oban.Job{state: "available"} = continuation] =
             all_enqueued(
               worker: CleanupProjectSnapshotWorker,
               args: %{intent_id: intent.id, continuation: 1}
             )

    assert :ok = CleanupProjectSnapshotWorker.perform(%{continuation | attempt: 1})
    assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "completed"
  end

  test "reconciler restores a nonterminal intent whose cleanup job is dead" do
    intent = cleanup_intent_fixture(0)
    handler_id = "snapshot-cleanup-recovery-#{System.unique_integer([:positive])}"
    parent = self()

    assert {:ok, dead_job} =
             %{intent_id: intent.id}
             |> CleanupProjectSnapshotWorker.new()
             |> Oban.insert()

    dead_job |> Ecto.Changeset.change(state: "discarded") |> Repo.update!()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :cleanup, :recovery, :stop],
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
      %{recovered_count: 1, failure_count: 0, continuation_count: 0},
      %{status: :ok}
    }
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
    intent = cleanup_intent_fixture(0)

    intent.cleanup_request_id
    |> then(&Repo.get!(StorageCleanupRequest, &1))
    |> Ecto.Changeset.change(owner_kind: "storage_compensation", owner_token: nil)
    |> Repo.update!()

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

  test "operator replay keeps a unique chain identity across every cleanup batch" do
    intent = cleanup_intent_fixture(49)

    assert {:ok, :terminal} =
             Versioning.process_project_snapshot_cleanup_intent(intent.id,
               delete_fun: fn keys -> {:error, keys} end,
               final_attempt?: true
             )

    %{intent_id: intent.id, continuation: 1}
    |> CleanupProjectSnapshotWorker.new()
    |> Ecto.Changeset.put_change(:state, "executing")
    |> Repo.insert!()

    assert {:ok, %SnapshotCleanupIntent{status: "retrying"}} =
             Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

    replay_job =
      CleanupProjectSnapshotWorker
      |> then(&all_enqueued(worker: &1))
      |> Enum.find(&is_binary(&1.args["replay_token"]))

    assert %Oban.Job{conflict?: false} = replay_job
    replay_token = replay_job.args["replay_token"]

    assert :ok = CleanupProjectSnapshotWorker.perform(%{replay_job | attempt: 1, max_attempts: 10})

    continuation =
      CleanupProjectSnapshotWorker
      |> then(&all_enqueued(worker: &1))
      |> Enum.find(fn job ->
        job.args["replay_token"] == replay_token and job.args["continuation"] == 1
      end)

    assert %Oban.Job{conflict?: false} = continuation
  end

  test "terminal cleanup logs an actionable operator replay command and preserves failures" do
    intent = cleanup_intent_fixture(0)

    failed_key =
      Enum.find(intent.storage_keys, &String.ends_with?(&1, "/ready/cleanupTest00001/manifest.json"))

    storage_path = storage_path(failed_key)
    File.mkdir_p!(storage_path)
    on_exit(fn -> File.rmdir(storage_path) end)

    log =
      capture_log(fn ->
        assert :ok =
                 CleanupProjectSnapshotWorker.perform(%Oban.Job{
                   args: %{"intent_id" => intent.id},
                   attempt: 10,
                   max_attempts: 10
                 })
      end)

    assert log =~ "Snapshot cleanup exhausted retries intent_id=#{intent.id}"
    assert log =~ "Versioning.replay_terminal_project_snapshot_cleanup(#{intent.id})"

    assert %SnapshotCleanupIntent{status: "terminal", remaining_storage_keys: [^failed_key]} =
             Repo.get!(SnapshotCleanupIntent, intent.id)
  end

  test "cleanup cannot report progress while a snapshot row still owns its namespace" do
    intent = cleanup_intent_fixture(0)

    intent.project_snapshot_id
    |> then(&Repo.get!(ProjectSnapshot, &1))
    |> Ecto.Changeset.change(
      object_prefix: intent.ready_prefix,
      project_storage_key: "#{intent.ready_prefix}/project.json",
      manifest_storage_key: "#{intent.ready_prefix}/manifest.json"
    )
    |> Repo.update!()

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

  test "cleanup fails closed when its durable ownership receipt is changed" do
    intent = cleanup_intent_fixture(0)

    intent.cleanup_request_id
    |> then(&Repo.get!(StorageCleanupRequest, &1))
    |> Ecto.Changeset.change(owner_kind: "storage_compensation", owner_token: nil)
    |> Repo.update!()

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

    assert log =~ "Snapshot cleanup exhausted retries intent_id=#{intent.id}"

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

    assert log =~ "Snapshot cleanup exhausted retries intent_id=#{intent.id}"

    assert %SnapshotCleanupIntent{
             status: "terminal",
             last_error_code: "invalid_inventory",
             remaining_storage_keys: ^remaining
           } = Repo.get!(SnapshotCleanupIntent, intent.id)
  end

  defp cleanup_intent_fixture(blob_count, opts \\ []) do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, snapshot} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    token = "cleanupTest00001"
    ready_prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/#{token}"
    staging_prefix = "projects/#{project.id}/snapshots/object-sets/v1/staging/#{token}"

    blob_paths =
      if blob_count > 0 do
        Enum.map(1..blob_count, fn index ->
          digest = :sha256 |> :crypto.hash("cleanup-blob-#{index}") |> Base.encode16(case: :lower)
          "blobs/#{digest}.bin"
        end)
      else
        []
      end

    paths = ["manifest.json", "project.json" | blob_paths]

    storage_keys =
      Enum.map(paths, &"#{ready_prefix}/#{&1}") ++
        Enum.map(paths, &"#{staging_prefix}/#{&1}")

    assert {:ok, cleanup_request} =
             StorageCompensation.persist_snapshot_lifecycle_cleanup(storage_keys, Ecto.UUID.generate())

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

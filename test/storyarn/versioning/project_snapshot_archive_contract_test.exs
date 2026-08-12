defmodule Storyarn.Versioning.ProjectSnapshotArchiveContractTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim

  @checksum String.duplicate("a", 64)
  @manifest_checksum String.duplicate("b", 64)
  @archive_checksum String.duplicate("c", 64)
  @capture_digest String.duplicate("d", 64)

  test "v2 changesets keep logical inventory separate from the two physical objects" do
    prefix = SnapshotArchiveStorage.ready_prefix(7, "ArchiveContract1")
    pending_attrs = pending_attrs(7, prefix)

    pending = ProjectSnapshot.pending_object_set_changeset(%ProjectSnapshot{}, pending_attrs)

    assert pending.valid?
    assert Ecto.Changeset.get_field(pending, :archive_storage_key) == prefix <> "/snapshot.zip"
    assert Ecto.Changeset.get_field(pending, :archive_checksum) == nil
    assert Ecto.Changeset.get_field(pending, :object_count) == 2

    ready = ProjectSnapshot.object_set_changeset(ready_source(), ready_attrs(7, prefix))

    assert ready.valid?
    assert Ecto.Changeset.get_field(ready, :total_size_bytes) == 12
    assert Ecto.Changeset.get_field(ready, :accounted_size_bytes) == 12
    assert Ecto.Changeset.get_field(ready, :asset_blob_size_bytes) == 41

    refute ProjectSnapshot.object_set_changeset(
             ready_source(),
             7 |> ready_attrs(prefix) |> Map.put(:total_size_bytes, 53)
           ).valid?

    refute ProjectSnapshot.object_set_changeset(
             ready_source(),
             7 |> ready_attrs(prefix) |> Map.put(:object_count, 3)
           ).valid?

    refute ProjectSnapshot.pending_object_set_changeset(
             %ProjectSnapshot{},
             Map.put(pending_attrs, :archive_checksum, @archive_checksum)
           ).valid?
  end

  test "database rejects partially materialized capture metadata" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, queued} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(
               """
               UPDATE project_snapshots
               SET project_size_bytes = 1,
                   capture_digest = $2,
                   captured_at = clock_timestamp(),
                   archive_size_bytes = 1,
                   progress_total_bytes = 1
               WHERE id = $1
               """,
               [queued.id, @capture_digest],
               mode: :savepoint
             )

    queued.build_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: 1,
      attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()

    assert {:ok, :captured} = ProjectSnapshotBuild.materialize_capture(queued.id, queued.build_job_id)

    captured = Repo.get!(ProjectSnapshot, queued.id)
    assert captured.capture_digest
    assert captured.project_checksum
    assert captured.manifest_checksum
    assert captured.total_size_bytes == captured.archive_size_bytes + captured.manifest_size_bytes
    assert captured.object_count == 2
  end

  test "publication digests bind the canonical archive without the post-stream checksum" do
    prefix = SnapshotArchiveStorage.ready_prefix(1, "ClaimContract002")
    v2 = ready_attrs(1, prefix)

    assert SnapshotObjectPublicationClaim.inventory_digest(v2) ==
             SnapshotObjectPublicationClaim.inventory_digest(Map.put(v2, :archive_checksum, String.duplicate("e", 64)))

    refute SnapshotObjectPublicationClaim.inventory_digest(v2) ==
             SnapshotObjectPublicationClaim.inventory_digest(Map.put(v2, :capture_digest, String.duplicate("f", 64)))
  end

  test "cleanup intent accepts exactly the paired archive and sidecar inventories" do
    ready_prefix = SnapshotArchiveStorage.ready_prefix(1, "CleanupContract1")
    staging_prefix = SnapshotArchiveStorage.staging_prefix(1, "CleanupContract1")
    paths = ["manifest.json", "snapshot.zip"]

    keys =
      Enum.flat_map([staging_prefix, ready_prefix], fn prefix ->
        Enum.map(paths, &"#{prefix}/#{&1}")
      end)

    attrs = cleanup_intent_attrs(ready_prefix, staging_prefix, keys)

    assert SnapshotCleanupIntent.create_changeset(%SnapshotCleanupIntent{}, attrs).valid?

    extra_keys = keys ++ [ready_prefix <> "/project.json", staging_prefix <> "/project.json"]

    refute SnapshotCleanupIntent.create_changeset(
             %SnapshotCleanupIntent{},
             cleanup_intent_attrs(ready_prefix, staging_prefix, extra_keys)
           ).valid?
  end

  test "v2 lifecycle deletion owns four exact keys without retaining a capture row" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = insert_ready_archive_snapshot(project.id)

    refute Repo.exists?(Storyarn.Versioning.ProjectSnapshotCapture)

    assert {:ok, intent} =
             Versioning.delete_project_snapshot(user_scope_fixture(user), project, snapshot.id)

    refute Repo.get(ProjectSnapshot, snapshot.id)
    assert intent.object_count == 4
    assert MapSet.new(intent.storage_keys) == archive_cleanup_keys(snapshot)
    assert intent.estimated_cleanup_bytes == 2 * snapshot.accounted_size_bytes
  end

  test "storage compensation retains adopted v2 objects but deletes conditional-copy remnants" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = insert_ready_archive_snapshot(project.id)
    archive_key = snapshot.archive_storage_key
    temporary_key = snapshot.object_prefix <> "/.storyarn-copy/ConditionalCopy1"
    invalid_key = snapshot.object_prefix <> "/project.json"

    assert {:ok, _url} = Storage.upload(archive_key, "archive", "application/zip")
    temporary_path = write_internal_storage_object!(temporary_key, "partial")

    on_exit(fn ->
      Storage.adapter().delete(archive_key)
      Storage.adapter().delete(temporary_key)
    end)

    assert :ok = StorageCompensation.delete_storage_keys([archive_key, temporary_key])
    assert {:ok, "archive"} = Storage.download(archive_key)
    refute File.exists?(temporary_path)

    assert {:error, :invalid_storage_key} =
             StorageCompensation.delete_or_enqueue(invalid_key,
               delete_fun: fn key -> send(self(), {:unexpected_delete, key}) end
             )

    refute_receive {:unexpected_delete, ^invalid_key}
  end

  defp insert_ready_archive_snapshot(project_id) do
    token = "Archive#{project_id |> Integer.to_string() |> String.pad_leading(9, "0")}"
    prefix = SnapshotArchiveStorage.ready_prefix(project_id, token)

    ready_source()
    |> ProjectSnapshot.object_set_changeset(ready_attrs(project_id, prefix))
    |> Repo.insert!()
  end

  defp pending_attrs(project_id, prefix) do
    %{
      project_id: project_id,
      version_number: 1,
      format_version: 2,
      object_prefix: prefix,
      archive_size_bytes: 10,
      project_size_bytes: 3,
      project_checksum: @checksum,
      manifest_size_bytes: 2,
      manifest_checksum: @manifest_checksum,
      total_size_bytes: 12,
      object_count: 2,
      asset_count: 2,
      blob_count: 1,
      mode: "full",
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: @capture_digest,
      progress_total_bytes: 12
    }
  end

  defp ready_attrs(project_id, prefix) do
    now = TimeHelpers.now()

    project_id
    |> pending_attrs(prefix)
    |> Map.merge(%{
      archive_storage_key: SnapshotArchiveStorage.archive_key(prefix),
      archive_checksum: @archive_checksum,
      manifest_storage_key: SnapshotArchiveStorage.manifest_key(prefix),
      asset_blob_size_bytes: 41,
      progress_phase: "complete",
      progress_bytes: 12,
      progress_total_bytes: 12,
      verifying_started_at: now,
      ready_at: now,
      state_updated_at: now
    })
  end

  defp ready_source do
    now = TimeHelpers.now()

    %ProjectSnapshot{
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: @capture_digest,
      captured_at: now,
      build_attempt: 1,
      building_started_at: now
    }
  end

  defp cleanup_intent_attrs(ready_prefix, staging_prefix, keys) do
    %{
      project_snapshot_id: 1,
      cleanup_request_id: 1,
      workspace_id_snapshot: 1,
      project_id_snapshot: 1,
      project_snapshot_id_snapshot: 1,
      deletion_generation: 1,
      mode: "full",
      origin: "user",
      reason: "user_delete",
      authority_kind: "user",
      authority_actor_id: 1,
      ready_prefix: ready_prefix,
      staging_prefix: staging_prefix,
      storage_keys: keys,
      inventory_digest: inventory_digest(keys),
      object_count: length(keys),
      estimated_cleanup_bytes: 24,
      provider_namespace_fingerprint: String.duplicate("f", 64),
      requested_at: ~U[2026-08-11 00:00:00Z]
    }
  end

  defp inventory_digest(keys) do
    keys
    |> Enum.sort()
    |> Enum.map_join(fn key -> "#{byte_size(key)}:#{key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp archive_cleanup_keys(snapshot) do
    {:ok, scope} = SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)
    MapSet.new(scope.storage_keys)
  end

  defp write_internal_storage_object!(key, contents) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    path = upload_dir |> Path.join(key) |> Path.expand()
    true = String.starts_with?(path, upload_dir <> "/")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    path
  end
end

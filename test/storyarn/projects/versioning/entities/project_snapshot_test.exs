defmodule Storyarn.Projects.Versioning.ProjectSnapshotTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Repo

  @checksum String.duplicate("a", 64)

  describe "update_changeset/2" do
    test "updates only editable metadata" do
      snapshot = %ProjectSnapshot{title: "Old", description: "Old description"}
      changeset = ProjectSnapshot.update_changeset(snapshot, %{title: "New", description: nil})

      assert changeset.valid?
      assert changeset.changes == %{title: "New", description: nil}
    end
  end

  describe "reconciliation_integrity_changeset/2" do
    test "degrades only integrity while preserving the canonical archive identity" do
      user = user_fixture()
      project = project_fixture(user)
      snapshot = full_project_snapshot_fixture(project)

      preserved =
        Map.take(snapshot, [
          :project_id,
          :object_prefix,
          :archive_storage_key,
          :manifest_storage_key,
          :lifecycle_state,
          :lifecycle_generation,
          :accounting_generation
        ])

      missing =
        snapshot
        |> ProjectSnapshot.reconciliation_integrity_changeset("missing")
        |> Repo.update!()

      assert Map.take(missing, Map.keys(preserved)) == preserved
      assert missing.integrity_state == "missing"

      corrupt =
        missing
        |> ProjectSnapshot.reconciliation_integrity_changeset("corrupt")
        |> Repo.update!()

      assert Map.take(corrupt, Map.keys(preserved)) == preserved
      assert corrupt.integrity_state == "corrupt"
    end

    test "rejects ineligible sources and unsupported targets" do
      eligible = %ProjectSnapshot{
        mode: "full",
        lifecycle_state: "ready",
        integrity_state: "verified",
        lifecycle_generation: 7
      }

      for {field, snapshot} <- [
            mode: %{eligible | mode: "unsupported"},
            lifecycle_state: %{eligible | lifecycle_state: "building", integrity_state: "unknown"},
            integrity_state: %{eligible | integrity_state: "incomplete"}
          ] do
        changeset = ProjectSnapshot.reconciliation_integrity_changeset(snapshot, "missing")

        refute changeset.valid?
        assert Map.has_key?(errors_on(changeset), field)
      end

      changeset = ProjectSnapshot.reconciliation_integrity_changeset(eligible, "verified")
      refute changeset.valid?
      assert %{integrity_state: ["is not a reconciliation repair target"]} = errors_on(changeset)
    end
  end

  describe "canonical archive changesets" do
    test "persists only format 2 with two physical objects" do
      prefix = ready_prefix(1)
      changeset = ProjectSnapshot.object_set_changeset(ready_source(), ready_attrs(1, prefix))

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :format_version) == 2
      assert Ecto.Changeset.get_field(changeset, :archive_storage_key) == prefix <> "/snapshot.zip"
      assert Ecto.Changeset.get_field(changeset, :manifest_storage_key) == prefix <> "/manifest.json"
      assert Ecto.Changeset.get_field(changeset, :object_count) == 2
      assert Ecto.Changeset.get_field(changeset, :total_size_bytes) == 12
      assert Ecto.Changeset.get_field(changeset, :accounted_size_bytes) == 12
      assert Ecto.Changeset.get_field(changeset, :accounting_generation) == 1
    end

    test "rejects legacy format values, noncanonical prefixes and inconsistent physical accounting" do
      prefix = ready_prefix(1)

      for attrs <- [
            Map.put(ready_attrs(1, prefix), :format_version, 1),
            Map.put(ready_attrs(1, prefix), :object_prefix, "projects/1/snapshots/legacy"),
            Map.put(ready_attrs(1, prefix), :object_count, 3),
            Map.put(ready_attrs(1, prefix), :total_size_bytes, 11)
          ] do
        refute ProjectSnapshot.object_set_changeset(ready_source(), attrs).valid?
      end
    end

    test "queues archive identity without inventing capture bytes" do
      prefix = ready_prefix(1)

      changeset =
        ProjectSnapshot.queued_archive_changeset(%ProjectSnapshot{}, %{
          project_id: 1,
          version_number: 1,
          created_by_id: 1,
          mode: "full",
          object_prefix: prefix,
          idempotency_key: Ecto.UUID.generate(),
          capture_boundary: Ecto.UUID.generate()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :format_version) == 2
      assert Ecto.Changeset.get_field(changeset, :archive_storage_key) == prefix <> "/snapshot.zip"
      assert Ecto.Changeset.get_field(changeset, :progress_total_bytes) == 0
      assert is_nil(Ecto.Changeset.get_field(changeset, :capture_digest))
      assert is_nil(Ecto.Changeset.get_field(changeset, :archive_size_bytes))
    end

    test "materializes only a pending v2 archive" do
      prefix = ready_prefix(1)
      attrs = pending_attrs(1, prefix)

      changeset = ProjectSnapshot.pending_object_set_changeset(%ProjectSnapshot{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :format_version) == 2
      assert Ecto.Changeset.get_field(changeset, :archive_size_bytes) == 10
      assert is_nil(Ecto.Changeset.get_field(changeset, :archive_checksum))

      refute ProjectSnapshot.pending_object_set_changeset(
               %ProjectSnapshot{},
               Map.put(attrs, :format_version, 1)
             ).valid?
    end

    test "allows a queued archive to fail before capture" do
      now = TimeHelpers.now()

      queued =
        %ProjectSnapshot{}
        |> ProjectSnapshot.queued_archive_changeset(%{
          project_id: 1,
          version_number: 1,
          created_by_id: 1,
          mode: "full",
          object_prefix: ready_prefix(1),
          idempotency_key: Ecto.UUID.generate(),
          capture_boundary: Ecto.UUID.generate(),
          state_updated_at: now
        })
        |> Ecto.Changeset.apply_changes()

      changeset =
        ProjectSnapshot.build_state_changeset(queued, %{
          lifecycle_state: "failed",
          integrity_state: "incomplete",
          progress_phase: "failed",
          failure_code: "build_failed",
          failure_message: "The snapshot could not be created.",
          failed_at: now,
          state_updated_at: now
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :progress_total_bytes) == 0
    end
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
      manifest_checksum: String.duplicate("b", 64),
      total_size_bytes: 12,
      object_count: 2,
      asset_count: 2,
      blob_count: 1,
      mode: "full",
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: String.duplicate("c", 64),
      progress_total_bytes: 12
    }
  end

  defp ready_attrs(project_id, prefix) do
    now = TimeHelpers.now()

    project_id
    |> pending_attrs(prefix)
    |> Map.merge(%{
      archive_storage_key: SnapshotArchiveStorage.archive_key(prefix),
      archive_checksum: String.duplicate("d", 64),
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
      capture_digest: String.duplicate("c", 64),
      captured_at: now,
      build_attempt: 1,
      building_started_at: now
    }
  end

  defp ready_prefix(project_id), do: SnapshotArchiveStorage.ready_prefix(project_id, "AbCdEfGhIjKlMnOp")
end

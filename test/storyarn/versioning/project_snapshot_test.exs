defmodule Storyarn.Versioning.ProjectSnapshotTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot

  @checksum String.duplicate("a", 64)
  @ready_prefix "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp"

  describe "update_changeset/2" do
    test "allows updating title and description" do
      snapshot = %ProjectSnapshot{title: "Old", description: "Old desc"}

      changeset =
        ProjectSnapshot.update_changeset(snapshot, %{title: "New", description: "New desc"})

      assert changeset.valid?
    end

    test "allows clearing title" do
      snapshot = %ProjectSnapshot{title: "Old"}
      changeset = ProjectSnapshot.update_changeset(snapshot, %{title: nil})
      assert changeset.valid?
    end
  end

  describe "object_set_changeset/2" do
    test "persists independently verified ready object-set metadata" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/project.json",
        project_size_bytes: 1_024,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp",
        manifest_storage_key: "projects/1/snapshots/object-sets/v1/ready/AbCdEfGhIjKlMnOp/manifest.json",
        manifest_size_bytes: 512,
        manifest_checksum: String.duplicate("b", 64),
        total_size_bytes: 4_096,
        object_count: 4,
        asset_count: 3,
        blob_count: 2
      }

      changeset = object_set_changeset(attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :project_storage_key) == attrs.project_storage_key
      assert Ecto.Changeset.get_field(changeset, :project_size_bytes) == 1_024
      assert Ecto.Changeset.get_field(changeset, :project_checksum) == @checksum
      assert Ecto.Changeset.get_field(changeset, :mode) == "full"
      assert Ecto.Changeset.get_field(changeset, :lifecycle_state) == "ready"
      assert Ecto.Changeset.get_field(changeset, :integrity_state) == "verified"
      assert Ecto.Changeset.get_field(changeset, :accounted_size_bytes) == 4_096
      assert Ecto.Changeset.get_field(changeset, :asset_blob_size_bytes) == 2_560
      assert Ecto.Changeset.get_field(changeset, :accounting_version) == 1
      assert Ecto.Changeset.get_field(changeset, :accounting_generation) == 1
      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :accounting_measured_at)
    end

    test "preserves an explicitly supplied accounting measurement time" do
      measured_at = ~U[2026-08-04 12:00:00Z]

      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: @ready_prefix <> "/project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: @ready_prefix,
        manifest_storage_key: @ready_prefix <> "/manifest.json",
        manifest_size_bytes: 10,
        manifest_checksum: @checksum,
        total_size_bytes: 20,
        object_count: 2,
        asset_count: 0,
        blob_count: 0,
        accounting_measured_at: measured_at
      }

      changeset = object_set_changeset(attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :accounting_measured_at) == measured_at
    end

    test "rejects conflicting accounting state and version metadata" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: @ready_prefix <> "/project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: @ready_prefix,
        manifest_storage_key: @ready_prefix <> "/manifest.json",
        manifest_size_bytes: 10,
        manifest_checksum: @checksum,
        total_size_bytes: 20,
        object_count: 2,
        asset_count: 0,
        blob_count: 0
      }

      for {field, conflicting_value} <- [
            mode: "linked",
            lifecycle_state: "building",
            integrity_state: "unverified",
            accounting_version: 2
          ] do
        changeset = object_set_changeset(Map.put(attrs, field, conflicting_value))

        refute changeset.valid?
        assert Map.has_key?(errors_on(changeset), field)
      end
    end

    test "rejects conflicting accounted and asset blob sizes" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: @ready_prefix <> "/project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: @ready_prefix,
        manifest_storage_key: @ready_prefix <> "/manifest.json",
        manifest_size_bytes: 10,
        manifest_checksum: @checksum,
        total_size_bytes: 30,
        object_count: 2,
        asset_count: 0,
        blob_count: 0
      }

      accounted_changeset = object_set_changeset(Map.put(attrs, :accounted_size_bytes, 29))

      asset_blob_changeset = object_set_changeset(Map.put(attrs, :asset_blob_size_bytes, 9))

      refute accounted_changeset.valid?
      assert %{accounted_size_bytes: ["must equal the total snapshot size"]} = errors_on(accounted_changeset)
      refute asset_blob_changeset.valid?

      assert %{asset_blob_size_bytes: ["must equal total size minus project and manifest sizes"]} =
               errors_on(asset_blob_changeset)
    end

    test "rejects inconsistent object and deduplication counts" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: @ready_prefix <> "/project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: @ready_prefix,
        manifest_storage_key: @ready_prefix <> "/manifest.json",
        manifest_size_bytes: 10,
        manifest_checksum: @checksum,
        total_size_bytes: 20,
        object_count: 9,
        asset_count: 1,
        blob_count: 2
      }

      changeset = object_set_changeset(attrs)

      refute changeset.valid?
      assert %{object_count: [_]} = errors_on(changeset)
    end

    test "requires at least one snapshot-owned blob when a full snapshot catalogs assets" do
      attrs =
        1
        |> object_set_attrs(@ready_prefix)
        |> Map.put(:asset_count, 1)

      changeset = object_set_changeset(attrs)

      refute changeset.valid?

      assert %{blob_count: ["must include at least one owned blob when assets are cataloged"]} =
               errors_on(changeset)
    end

    test "rejects a total size smaller than the manifest before insert" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: @ready_prefix <> "/project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: @ready_prefix,
        manifest_storage_key: @ready_prefix <> "/manifest.json",
        manifest_size_bytes: 11,
        manifest_checksum: @checksum,
        total_size_bytes: 10,
        object_count: 2,
        asset_count: 0,
        blob_count: 0
      }

      changeset = object_set_changeset(attrs)

      refute changeset.valid?
      assert %{total_size_bytes: ["must be at least the manifest size"]} = errors_on(changeset)
    end

    test "rejects an empty project object for a ready snapshot" do
      attrs =
        1
        |> object_set_attrs(@ready_prefix)
        |> Map.merge(%{project_size_bytes: 0, total_size_bytes: 1})

      changeset = object_set_changeset(attrs)

      refute changeset.valid?
      assert %{project_size_bytes: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "pending_object_set_changeset/2" do
    test "allocates a non-ready unaccounted object-set target" do
      prefix = @ready_prefix

      changeset = pending_object_set_changeset(1, prefix)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :project_storage_key) == prefix <> "/project.json"
      assert Ecto.Changeset.get_field(changeset, :manifest_storage_key) == prefix <> "/manifest.json"
      assert Ecto.Changeset.get_field(changeset, :project_size_bytes) == 1
      assert Ecto.Changeset.get_field(changeset, :progress_total_bytes) == 2
      assert Ecto.Changeset.get_field(changeset, :lifecycle_state) == "pending"
      assert Ecto.Changeset.get_field(changeset, :integrity_state) == "unknown"
      assert is_nil(Ecto.Changeset.get_field(changeset, :accounted_size_bytes))
      assert is_nil(Ecto.Changeset.get_field(changeset, :accounting_version))
      assert is_nil(Ecto.Changeset.get_field(changeset, :accounting_generation))
    end

    test "rejects ready or already-sized pending targets" do
      prefix = @ready_prefix

      for attrs <- [
            %{lifecycle_state: "ready"},
            %{integrity_state: "verified"},
            %{project_size_bytes: 0}
          ] do
        changeset = pending_object_set_changeset(1, prefix, attrs)

        refute changeset.valid?
      end
    end

    test "database rejects a ready v1 row without a complete object inventory" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/INCOMPLETE123456"

      changeset =
        Ecto.Changeset.change(ready_snapshot(), %{
          project_id: project.id,
          version_number: 1,
          project_storage_key: prefix <> "/project.json",
          project_size_bytes: 5,
          project_checksum: @checksum,
          format_version: 1,
          object_prefix: prefix,
          manifest_storage_key: prefix <> "/manifest.json",
          mode: "full",
          lifecycle_state: "ready",
          integrity_state: "verified",
          manifest_size_bytes: 5,
          total_size_bytes: 10,
          object_count: 2,
          asset_count: 0,
          blob_count: 0,
          accounted_size_bytes: 10,
          asset_blob_size_bytes: 0,
          accounting_version: 1,
          accounting_generation: 1,
          accounting_measured_at: TimeHelpers.now(),
          progress_phase: "complete",
          progress_bytes: 10,
          progress_total_bytes: 10,
          verifying_started_at: TimeHelpers.now(),
          ready_at: TimeHelpers.now(),
          state_updated_at: TimeHelpers.now()
        })

      assert_raise Ecto.ConstraintError, ~r/project_snapshots_ready_object_set/, fn ->
        Repo.insert!(changeset)
      end
    end

    test "database rejects a canonical row with a null format version" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/NULLVERSION12345"

      snapshot =
        project.id
        |> pending_object_set_changeset(prefix)
        |> Repo.insert!()

      changeset =
        snapshot
        |> Ecto.Changeset.change(format_version: nil)
        |> Ecto.Changeset.check_constraint(:format_version,
          name: :project_snapshots_accounting_identity
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{format_version: [_]} = errors_on(rejected)
    end

    test "database rejects null ready inventory metadata" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/NULLMANIFEST1234"

      snapshot =
        project.id
        |> object_set_attrs(prefix)
        |> object_set_changeset()
        |> Repo.insert!()

      changeset =
        snapshot
        |> Ecto.Changeset.change(manifest_checksum: nil)
        |> Ecto.Changeset.check_constraint(:manifest_checksum,
          name: :project_snapshots_ready_object_set
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{manifest_checksum: [_]} = errors_on(rejected)
    end

    test "database rejects a zero-byte project object once ready" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/ZEROPROJECT12345"

      snapshot =
        project.id
        |> object_set_attrs(prefix)
        |> object_set_changeset()
        |> Repo.insert!()

      changeset =
        snapshot
        |> Ecto.Changeset.change(%{
          project_size_bytes: 0,
          total_size_bytes: 1,
          accounted_size_bytes: 1
        })
        |> Ecto.Changeset.check_constraint(:project_size_bytes,
          name: :project_snapshots_ready_object_set
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{project_size_bytes: [_]} = errors_on(rejected)
    end

    test "database rejects a full ready snapshot with assets but no owned blobs" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/NOBLOBASSETS1234"

      snapshot =
        project.id
        |> object_set_attrs(prefix)
        |> object_set_changeset()
        |> Repo.insert!()

      changeset =
        snapshot
        |> Ecto.Changeset.change(asset_count: 1)
        |> Ecto.Changeset.check_constraint(:blob_count,
          name: :project_snapshots_full_asset_blobs
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{blob_count: [_]} = errors_on(rejected)
    end

    test "database rejects a pending row without its allocated object target" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/NULLTARGET123456"

      snapshot =
        project.id
        |> pending_object_set_changeset(prefix)
        |> Repo.insert!()

      changeset =
        snapshot
        |> Ecto.Changeset.change(object_prefix: nil)
        |> Ecto.Changeset.check_constraint(:object_prefix,
          name: :project_snapshots_object_target
        )

      assert {:error, rejected} = Repo.update(changeset)
      assert %{object_prefix: [_]} = errors_on(rejected)
    end

    test "database rejects a linked row outside the canonical object-set namespace" do
      user = user_fixture()
      project = project_fixture(user)
      token = "LEGACYLINKED1234"
      prefix = "projects/#{project.id}/snapshots/linked/v1/ready/#{token}"

      changeset =
        Ecto.Changeset.change(ready_snapshot(), %{
          project_id: project.id,
          version_number: 1,
          project_storage_key: prefix <> "/project.json",
          project_size_bytes: 10,
          project_checksum: @checksum,
          format_version: 1,
          object_prefix: prefix,
          manifest_storage_key: prefix <> "/manifest.json",
          manifest_size_bytes: 10,
          manifest_checksum: @checksum,
          total_size_bytes: 20,
          object_count: 2,
          asset_count: 0,
          blob_count: 0,
          mode: "linked",
          lifecycle_state: "ready",
          integrity_state: "verified",
          accounted_size_bytes: 20,
          asset_blob_size_bytes: 0,
          accounting_version: 1,
          accounting_generation: 1,
          accounting_measured_at: TimeHelpers.now(),
          progress_phase: "complete",
          progress_bytes: 20,
          progress_total_bytes: 20,
          verifying_started_at: TimeHelpers.now(),
          ready_at: TimeHelpers.now(),
          state_updated_at: TimeHelpers.now()
        })

      assert_raise Ecto.ConstraintError, ~r/project_snapshots_object_target/, fn ->
        Repo.insert!(changeset)
      end
    end
  end

  describe "accounting generation fencing" do
    test "rejects a stale direct accounting update" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/STALELOCK1234567"

      snapshot =
        project.id
        |> object_set_attrs(prefix)
        |> object_set_changeset()
        |> Repo.insert!()

      first_measurement = Repo.get!(ProjectSnapshot, snapshot.id)
      stale_measurement = Repo.get!(ProjectSnapshot, snapshot.id)

      updated =
        first_measurement
        |> ProjectSnapshot.object_set_changeset(object_set_attrs(project.id, prefix))
        |> Repo.update!()

      assert updated.accounting_generation == 2

      assert_raise Ecto.StaleEntryError, fn ->
        stale_measurement
        |> ProjectSnapshot.object_set_changeset(object_set_attrs(project.id, prefix))
        |> Repo.update!()
      end
    end

    test "pending finalization fails outside the matching reservation commit" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/FINALIZE12345678"

      pending =
        project.id
        |> pending_object_set_changeset(prefix)
        |> Repo.insert!()

      assert {:error, :snapshot_storage_commit_context_required} =
               Versioning.finalize_project_snapshot_object_set(
                 pending.id,
                 0,
                 object_set_attrs(project.id, prefix)
               )

      persisted = Repo.get!(ProjectSnapshot, pending.id)
      assert is_nil(persisted.accounting_generation)
      assert persisted.lifecycle_state == "pending"
    end

    test "remeasurement uses a workspace lock and rejects a stale generation" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/REMEASURE1234567"

      snapshot =
        project.id
        |> object_set_attrs(prefix)
        |> object_set_changeset()
        |> Repo.insert!()

      assert {:ok, remeasured} =
               Versioning.remeasure_project_snapshot_object_set(
                 snapshot.id,
                 1,
                 object_set_attrs(project.id, prefix)
               )

      assert remeasured.accounting_generation == 2

      assert {:error, :stale_snapshot_accounting_measurement} =
               Versioning.remeasure_project_snapshot_object_set(
                 snapshot.id,
                 1,
                 object_set_attrs(project.id, prefix)
               )
    end

    test "remeasurement cannot rewrite immutable snapshot inventory" do
      user = user_fixture()
      project = project_fixture(user)
      prefix = "projects/#{project.id}/snapshots/object-sets/v1/ready/IMMUTABLE1234567"
      attrs = object_set_attrs(project.id, prefix)

      snapshot =
        attrs
        |> object_set_changeset()
        |> Repo.insert!()

      changed_attrs =
        attrs
        |> Map.put(:manifest_checksum, String.duplicate("d", 64))
        |> Map.put(:manifest_size_bytes, 2)
        |> Map.put(:total_size_bytes, 3)

      assert {:error, changeset} =
               Versioning.remeasure_project_snapshot_object_set(snapshot.id, 1, changed_attrs)

      refute changeset.valid?
      assert %{manifest_checksum: [_], manifest_size_bytes: [_], total_size_bytes: [_]} = errors_on(changeset)
      assert Repo.get!(ProjectSnapshot, snapshot.id).accounting_generation == 1
    end
  end

  defp object_set_attrs(project_id, prefix) do
    checksum = String.duplicate("c", 64)

    %{
      project_id: project_id,
      version_number: 1,
      project_storage_key: prefix <> "/project.json",
      project_size_bytes: 1,
      project_checksum: checksum,
      format_version: 1,
      object_prefix: prefix,
      manifest_storage_key: prefix <> "/manifest.json",
      manifest_size_bytes: 1,
      manifest_checksum: checksum,
      total_size_bytes: 2,
      object_count: 2,
      asset_count: 0,
      blob_count: 0
    }
  end

  defp object_set_changeset(attrs) do
    total_size = Map.fetch!(attrs, :total_size_bytes)
    now = TimeHelpers.now()

    attrs =
      Map.merge(
        %{
          progress_phase: "complete",
          progress_bytes: total_size,
          progress_total_bytes: total_size,
          verifying_started_at: now,
          ready_at: now,
          state_updated_at: now
        },
        attrs
      )

    ProjectSnapshot.object_set_changeset(ready_snapshot(now), attrs)
  end

  defp pending_object_set_changeset(project_id, prefix, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          project_id: project_id,
          version_number: 1,
          object_prefix: prefix,
          project_size_bytes: 1,
          project_checksum: @checksum,
          manifest_size_bytes: 1,
          manifest_checksum: String.duplicate("b", 64),
          total_size_bytes: 2,
          object_count: 2,
          asset_count: 0,
          blob_count: 0,
          mode: "full",
          idempotency_key: Ecto.UUID.generate(),
          capture_boundary: Ecto.UUID.generate(),
          capture_digest: String.duplicate("c", 64),
          progress_total_bytes: 2
        },
        overrides
      )

    ProjectSnapshot.pending_object_set_changeset(%ProjectSnapshot{}, attrs)
  end

  defp ready_snapshot(now \\ TimeHelpers.now()) do
    %ProjectSnapshot{
      idempotency_key: Ecto.UUID.generate(),
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: String.duplicate("c", 64),
      captured_at: now,
      build_attempt: 1,
      building_started_at: now
    }
  end
end

defmodule Storyarn.Versioning.ProjectSnapshotTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.ProjectSnapshot

  @checksum String.duplicate("a", 64)

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "projects/1/snapshots/project/1.json.gz",
        snapshot_size_bytes: 1024,
        checksum: @checksum
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, %{})
      refute changeset.valid?

      assert %{
               project_id: ["can't be blank"],
               version_number: ["can't be blank"],
               storage_key: ["can't be blank"],
               snapshot_size_bytes: ["can't be blank"],
               checksum: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates title max length" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: 100,
        checksum: @checksum,
        title: String.duplicate("a", 256)
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert %{title: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "validates description max length" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: 100,
        checksum: @checksum,
        description: String.duplicate("a", 501)
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert %{description: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end

    test "validates snapshot_size_bytes is non-negative" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: -1,
        checksum: @checksum
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert %{snapshot_size_bytes: [_]} = errors_on(changeset)
    end

    test "accepts optional title, description, entity_counts" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: 100,
        checksum: @checksum,
        title: "Before playtest",
        description: "Full project backup",
        entity_counts: %{"sheets" => 5, "flows" => 3, "scenes" => 2}
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert changeset.valid?
    end

    test "rejects a malformed checksum" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: 100,
        checksum: "not-a-sha256"
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert %{checksum: ["has invalid format"]} = errors_on(changeset)
    end
  end

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

      changeset = ProjectSnapshot.object_set_changeset(%ProjectSnapshot{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :storage_key) == attrs.project_storage_key
      assert Ecto.Changeset.get_field(changeset, :snapshot_size_bytes) == 1_024
      assert Ecto.Changeset.get_field(changeset, :checksum) == @checksum
    end

    test "rejects inconsistent object and deduplication counts" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: "project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: "ready/prefix",
        manifest_storage_key: "ready/prefix/manifest.json",
        manifest_size_bytes: 10,
        manifest_checksum: @checksum,
        total_size_bytes: 20,
        object_count: 9,
        asset_count: 1,
        blob_count: 2
      }

      changeset = ProjectSnapshot.object_set_changeset(%ProjectSnapshot{}, attrs)

      refute changeset.valid?
      assert %{object_count: [_]} = errors_on(changeset)
    end

    test "rejects a total size smaller than the manifest before insert" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        project_storage_key: "project.json",
        project_size_bytes: 10,
        project_checksum: @checksum,
        format_version: 1,
        object_prefix: "ready/prefix",
        manifest_storage_key: "ready/prefix/manifest.json",
        manifest_size_bytes: 11,
        manifest_checksum: @checksum,
        total_size_bytes: 10,
        object_count: 2,
        asset_count: 0,
        blob_count: 0
      }

      changeset = ProjectSnapshot.object_set_changeset(%ProjectSnapshot{}, attrs)

      refute changeset.valid?
      assert %{total_size_bytes: ["must be at least the manifest size"]} = errors_on(changeset)
    end
  end
end

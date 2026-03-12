defmodule Storyarn.Versioning.ProjectSnapshotTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.ProjectSnapshot

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "projects/1/snapshots/project/1.json.gz",
        snapshot_size_bytes: 1024
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
               snapshot_size_bytes: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates title max length" do
      attrs = %{
        project_id: 1,
        version_number: 1,
        storage_key: "key",
        snapshot_size_bytes: 100,
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
        snapshot_size_bytes: -1
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
        title: "Before playtest",
        description: "Full project backup",
        entity_counts: %{"sheets" => 5, "flows" => 3, "scenes" => 2}
      }

      changeset = ProjectSnapshot.changeset(%ProjectSnapshot{}, attrs)
      assert changeset.valid?
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
end

defmodule Storyarn.Projects.Versioning.ProjectSnapshotCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotCrud

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  describe "canonical rollout boundary" do
    test "database rejects a project snapshot with a noncanonical object target", %{project: project} do
      now = Storyarn.Platform.Shared.TimeHelpers.now()

      noncanonical_changeset =
        %ProjectSnapshot{}
        |> Ecto.Changeset.change(%{
          project_id: project.id,
          version_number: 1,
          archive_storage_key: "snapshots/invalid-monolith/snapshot.zip",
          archive_size_bytes: 100,
          project_size_bytes: 100,
          project_checksum: String.duplicate("a", 64),
          format_version: 2,
          object_prefix: "snapshots/invalid-monolith",
          manifest_storage_key: "snapshots/invalid-monolith/manifest.json",
          manifest_size_bytes: 50,
          manifest_checksum: String.duplicate("b", 64),
          total_size_bytes: 150,
          object_count: 2,
          asset_count: 0,
          blob_count: 0,
          mode: "full",
          lifecycle_state: "pending",
          integrity_state: "unknown",
          idempotency_key: Ecto.UUID.generate(),
          capture_boundary: Ecto.UUID.generate(),
          capture_digest: String.duplicate("c", 64),
          captured_at: now,
          progress_phase: "pending",
          progress_bytes: 0,
          progress_total_bytes: 150,
          build_attempt: 0,
          state_updated_at: now
        })
        |> Ecto.Changeset.check_constraint(:object_prefix,
          name: :project_snapshots_object_target
        )

      assert {:error, changeset} = Repo.insert(noncanonical_changeset)

      assert {"is invalid", constraint: :check, constraint_name: "project_snapshots_object_target"} =
               changeset.errors[:object_prefix]
    end
  end

  describe "canonical queries" do
    test "lists snapshots newest first with pagination and creator preload", %{project: project, user: user} do
      first = full_project_snapshot_fixture(project, %{version_number: 1, created_by_id: user.id})
      second = full_project_snapshot_fixture(project, %{version_number: 2, created_by_id: user.id})
      third = pending_project_snapshot_fixture(project, %{version_number: 3, created_by_id: user.id})

      assert [listed_third, listed_second] = ProjectSnapshotCrud.list_snapshots(project.id, limit: 2)
      assert [listed_third.id, listed_second.id] == [third.id, second.id]
      assert listed_third.created_by.id == user.id
      assert [listed_first] = ProjectSnapshotCrud.list_snapshots(project.id, limit: 1, offset: 2)
      assert listed_first.id == first.id
    end

    test "gets only snapshots owned by the requested project", %{project: project} do
      other_project = project_fixture()
      snapshot = full_project_snapshot_fixture(project)

      assert ProjectSnapshotCrud.get_snapshot(project.id, snapshot.version_number).id == snapshot.id
      assert ProjectSnapshotCrud.get_snapshot_by_id(project.id, snapshot.id).id == snapshot.id
      assert ProjectSnapshotCrud.get_snapshot_by_id(other_project.id, snapshot.id) == nil
    end

    test "counts canonical lifecycle rows and allocates the next version", %{project: project} do
      full_project_snapshot_fixture(project, %{version_number: 2})
      pending_project_snapshot_fixture(project, %{version_number: 7})

      assert ProjectSnapshotCrud.count_snapshots(project.id) == 2
      assert ProjectSnapshotCrud.next_version_number(project.id) == 8
    end
  end

  describe "canonical mutations" do
    test "updates only editable metadata", %{project: project} do
      snapshot = full_project_snapshot_fixture(project, %{title: "Before"})

      assert {:ok, updated} =
               ProjectSnapshotCrud.update_snapshot(snapshot, %{
                 title: "After",
                 description: "Portable capture"
               })

      assert updated.title == "After"
      assert updated.description == "Portable capture"
      assert updated.object_prefix == snapshot.object_prefix
      assert updated.accounted_size_bytes == snapshot.accounted_size_bytes
    end

    test "finalization cannot bypass the reservation commit context", %{project: project} do
      pending = pending_project_snapshot_fixture(project)

      assert {:error, :snapshot_storage_commit_context_required} =
               ProjectSnapshotCrud.finalize_object_set(pending.id, 0, %{})
    end

    test "remeasure rejects a stale generation without changing accounting", %{project: project} do
      snapshot = full_project_snapshot_fixture(project)

      assert {:error, :stale_snapshot_accounting_measurement} =
               ProjectSnapshotCrud.remeasure_object_set(
                 snapshot.id,
                 snapshot.accounting_generation + 1,
                 %{}
               )

      assert Repo.get!(ProjectSnapshot, snapshot.id).accounting_generation ==
               snapshot.accounting_generation
    end
  end
end

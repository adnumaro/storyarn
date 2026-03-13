defmodule Storyarn.Versioning.ChangeDetectorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Drafts
  alias Storyarn.Versioning.ChangeDetector
  alias Storyarn.Versioning.ProjectSnapshot

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures

  describe "project_changed_since_last_snapshot?/1" do
    test "returns true when no snapshots exist" do
      project = project_fixture()
      assert ChangeDetector.project_changed_since_last_snapshot?(project.id)
    end

    test "returns false when no entities modified after last snapshot" do
      project = project_fixture()
      _flow = flow_fixture(project)

      # Create a snapshot record (simulate one existing)
      insert_snapshot(project.id)

      # No modifications since snapshot
      refute ChangeDetector.project_changed_since_last_snapshot?(project.id)
    end

    test "returns true when entity modified after last snapshot" do
      project = project_fixture()

      # Create snapshot with inserted_at in the past
      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)
      insert_snapshot(project.id, inserted_at: past)

      # Now create an entity (updated_at will be after snapshot)
      _flow = flow_fixture(project)

      assert ChangeDetector.project_changed_since_last_snapshot?(project.id)
    end

    test "ignores draft entity modifications" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Push flow timestamps into the past
      past = DateTime.add(DateTime.utc_now(), -120, :second) |> DateTime.truncate(:second)
      Repo.query!("UPDATE flows SET updated_at = $1 WHERE id = $2", [past, flow.id])

      # Create snapshot after the flow modifications
      snapshot_time = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)
      insert_snapshot(project.id, inserted_at: snapshot_time)

      # No changes since snapshot
      refute ChangeDetector.project_changed_since_last_snapshot?(project.id)

      # Creating a draft clones the flow with draft_id set
      {:ok, _draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # The cloned flow has draft_id set, so it should NOT trigger change detection.
      # The original flow was not modified, so the only "new" flow is the draft clone.
      refute ChangeDetector.project_changed_since_last_snapshot?(project.id)
    end
  end

  describe "recent_manual_snapshot?/2" do
    test "returns false when no snapshots exist" do
      project = project_fixture()
      refute ChangeDetector.recent_manual_snapshot?(project.id)
    end

    test "returns true when manual snapshot within window" do
      project = project_fixture()
      insert_snapshot(project.id, is_auto: false)

      assert ChangeDetector.recent_manual_snapshot?(project.id, 6)
    end

    test "returns false for auto snapshots" do
      project = project_fixture()
      insert_snapshot(project.id, is_auto: true)

      refute ChangeDetector.recent_manual_snapshot?(project.id, 6)
    end
  end

  defp insert_snapshot(project_id, opts \\ []) do
    is_auto = Keyword.get(opts, :is_auto, false)
    inserted_at = Keyword.get(opts, :inserted_at)
    version = System.unique_integer([:positive])

    snapshot =
      %ProjectSnapshot{}
      |> ProjectSnapshot.changeset(%{
        project_id: project_id,
        version_number: version,
        storage_key: "test/snapshot/#{version}.json.gz",
        snapshot_size_bytes: 100,
        entity_counts: %{},
        is_auto: is_auto
      })
      |> Repo.insert!()

    if inserted_at do
      Repo.query!("UPDATE project_snapshots SET inserted_at = $1 WHERE id = $2", [
        inserted_at,
        snapshot.id
      ])
    end

    snapshot
  end
end

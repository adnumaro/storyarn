defmodule Storyarn.Projects.RestorationLockTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Versioning
  alias Storyarn.Workers.RestoreProjectWorker

  setup do
    user = user_fixture()
    project = project_fixture(user)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project.id, user.id)

    %{user: user, project: project, snapshot: snapshot}
  end

  describe "acquire_restoration_lock/3" do
    test "succeeds on unlocked project", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      assert {:ok, locked_project} =
               Projects.acquire_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id
               )

      assert locked_project.restoration_in_progress == true
      assert locked_project.restoration_started_by_id == user.id
      assert locked_project.restoration_started_at
      assert locked_project.restoration_snapshot_id == snapshot.id
      assert {:ok, _uuid} = Ecto.UUID.cast(locked_project.restoration_token)
      assert locked_project.restoration_claimed_by_job_id == nil
    end

    test "fails on already-locked project", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      other_user = user_fixture()

      assert {:error, :already_locked} =
               Projects.acquire_restoration_lock(
                 project.id,
                 other_user.id,
                 snapshot.id
               )
    end

    test "fails when same user tries to lock twice", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:error, :already_locked} =
               Projects.acquire_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id
               )
    end

    test "rejects a snapshot owned by another project", %{
      project: project,
      user: user
    } do
      other_project = project_fixture(user)

      {:ok, other_snapshot} =
        Versioning.create_project_snapshot(other_project.id, user.id)

      assert {:error, :snapshot_not_found} =
               Projects.acquire_restoration_lock(
                 project.id,
                 user.id,
                 other_snapshot.id
               )
    end
  end

  describe "release_restoration_lock/2" do
    test "clears all lock fields only for the matching token", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, locked} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      {:ok, released} =
        Projects.release_restoration_lock(
          project.id,
          locked.restoration_token
        )

      assert released.restoration_in_progress == false
      assert released.restoration_started_by_id == nil
      assert released.restoration_started_at == nil
      assert released.restoration_token == nil
      assert released.restoration_claimed_by_job_id == nil
      assert released.restoration_snapshot_id == nil
    end

    test "an old release cannot clear a newer lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, first_lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      {:ok, _released} =
        Projects.release_restoration_lock(
          project.id,
          first_lock.restoration_token
        )

      {:ok, second_lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:error, :lock_mismatch} =
               Projects.release_restoration_lock(
                 project.id,
                 first_lock.restoration_token
               )

      assert {:ok, current_lock} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 second_lock.restoration_token
               )

      assert current_lock.restoration_token == second_lock.restoration_token
    end

    test "an invalid token fails closed without raising", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:error, :lock_mismatch} =
               Projects.release_restoration_lock(project.id, "not-a-uuid")

      assert {:ok, _project} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token
               )
    end

    test "an unclaimed or different job cannot release a claimed lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:ok, claimed} =
               Projects.claim_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token,
                 101
               )

      assert claimed.restoration_claimed_by_job_id == 101

      assert {:error, :lock_mismatch} =
               Projects.release_restoration_lock(
                 project.id,
                 lock.restoration_token
               )

      assert {:error, :lock_mismatch} =
               Projects.release_restoration_lock(
                 project.id,
                 lock.restoration_token,
                 202
               )

      assert {:ok, released} =
               Projects.release_restoration_lock(
                 project.id,
                 lock.restoration_token,
                 101
               )

      refute released.restoration_in_progress
      assert released.restoration_claimed_by_job_id == nil
    end

    test "the target snapshot cannot be deleted while its lock is active", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:error, %Ecto.Changeset{}} =
               Versioning.delete_project_snapshot(snapshot)

      assert Versioning.get_project_snapshot(project.id, snapshot.id)
    end
  end

  describe "restoration_in_progress?/1" do
    test "returns false for unlocked project", %{project: project} do
      assert Projects.restoration_in_progress?(project.id) == false
    end

    test "returns {true, info} for locked project", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {true, %{user_id: uid, started_at: %DateTime{}}} =
               Projects.restoration_in_progress?(project.id)

      assert uid == user.id
    end
  end

  describe "clear_stale_restoration_lock/2" do
    test "clears lock older than timeout", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      # Manually set started_at to 20 minutes ago
      old_time = DateTime.add(DateTime.utc_now(), -20 * 60, :second)

      Storyarn.Repo.update_all(
        from(p in Project, where: p.id == ^project.id),
        set: [restoration_started_at: old_time]
      )

      assert {:ok, :cleared} = Projects.clear_stale_restoration_lock(project.id, 15)
      assert Projects.restoration_in_progress?(project.id) == false
    end

    test "does not clear recent lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, _} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      assert {:error, :not_stale} = Projects.clear_stale_restoration_lock(project.id, 15)
      assert {true, _} = Projects.restoration_in_progress?(project.id)
    end

    test "does not clear a stale lock while its worker job is active", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(project.id, user.id, snapshot.id)

      old_time = DateTime.add(DateTime.utc_now(), -20 * 60, :second)

      Storyarn.Repo.update_all(
        from(p in Project, where: p.id == ^project.id),
        set: [restoration_started_at: old_time]
      )

      {:ok, job} =
        %{
          project_id: project.id,
          snapshot_id: snapshot.id,
          user_id: user.id,
          lock_token: lock.restoration_token
        }
        |> RestoreProjectWorker.new()
        |> Oban.insert()

      assert {:ok, claimed_project} =
               Projects.claim_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token,
                 job.id
               )

      assert claimed_project.restoration_claimed_by_job_id == job.id

      Storyarn.Repo.update_all(
        from(candidate in Oban.Job, where: candidate.id == ^job.id),
        set: [state: "executing"]
      )

      assert {:error, :restore_active} =
               Projects.clear_stale_restoration_lock(project.id, 15)

      assert {:ok, _project} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token
               )
    end
  end
end

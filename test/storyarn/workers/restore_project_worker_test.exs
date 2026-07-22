defmodule Storyarn.Workers.RestoreProjectWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Workers.RestoreProjectWorker

  setup do
    restore_policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    on_exit(fn ->
      Application.put_env(
        :storyarn,
        RestorePolicy,
        restore_policy
      )
    end)

    user = user_fixture()
    project = project_fixture(user)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(
        project.id,
        user.id,
        title: "Test"
      )

    %{user: user, project: project, snapshot: snapshot}
  end

  describe "perform/1" do
    test "new/1 keeps restores on the rolling-deploy-safe queue", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      job =
        %{
          project_id: project.id,
          snapshot_id: snapshot.id,
          user_id: user.id,
          lock_token: Ecto.UUID.generate()
        }
        |> RestoreProjectWorker.new()
        |> Ecto.Changeset.apply_changes()

      assert %Oban.Job{queue: "project_restores"} = job
    end

    test "restores snapshot and releases its lock on success", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      Collaboration.subscribe_restoration(project.id)
      Collaboration.subscribe_dashboard(project.id)

      assert :ok =
               perform_job(
                 RestoreProjectWorker,
                 restore_args(project, snapshot, user, lock)
               )

      assert Projects.restoration_in_progress?(project.id) == false

      assert_received {:project_restoration_completed, payload}
      assert payload.snapshot_title == "Test"
      assert_received {:dashboard_invalidate, :all}
    end

    test "rejects a job without an active lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      Collaboration.subscribe_restoration(project.id)

      assert {:error, {:invalid_restoration_lock, :not_locked}} =
               perform_job(RestoreProjectWorker, %{
                 project_id: project.id,
                 snapshot_id: snapshot.id,
                 user_id: user.id,
                 lock_token: Ecto.UUID.generate()
               })

      refute_received {:project_restoration_completed, _payload}
      refute_received {:project_restoration_failed, _payload}
      refute Projects.restoration_in_progress?(project.id)
    end

    test "a stale token cannot run or release the active lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      assert {:error, {:invalid_restoration_lock, :lock_mismatch}} =
               perform_job(RestoreProjectWorker, %{
                 project_id: project.id,
                 snapshot_id: snapshot.id,
                 user_id: user.id,
                 lock_token: Ecto.UUID.generate()
               })

      assert {:ok, _project} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token
               )
    end

    test "a different snapshot cannot run or release the active lock", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, other_snapshot} =
        Versioning.create_project_snapshot(
          project.id,
          user.id,
          title: "Other"
        )

      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      assert {:error, {:invalid_restoration_lock, :lock_mismatch}} =
               perform_job(RestoreProjectWorker, %{
                 project_id: project.id,
                 snapshot_id: other_snapshot.id,
                 user_id: user.id,
                 lock_token: lock.restoration_token
               })

      assert {:ok, _project} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token
               )
    end

    test "a duplicate job with the same token cannot pass another job's claim", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      duplicate_job =
        build_job(
          RestoreProjectWorker,
          restore_args(project, snapshot, user, lock)
        )

      claimed_job_id = duplicate_job.id + 1

      assert {:ok, claimed_project} =
               Projects.claim_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token,
                 claimed_job_id
               )

      assert claimed_project.restoration_claimed_by_job_id == claimed_job_id
      snapshot_count = Versioning.count_project_snapshots(project.id)

      assert {:error, {:invalid_restoration_lock, :already_claimed}} =
               perform_job(duplicate_job)

      assert Versioning.count_project_snapshots(project.id) == snapshot_count

      assert {:ok, current_lock} =
               Projects.verify_restoration_lock(
                 project.id,
                 user.id,
                 snapshot.id,
                 lock.restoration_token
               )

      assert current_lock.restoration_claimed_by_job_id == claimed_job_id
    end

    test "reauthorizes the actor and aborts after their access is revoked", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      project.id
      |> Projects.get_membership(user.id)
      |> Repo.delete!()

      Collaboration.subscribe_restoration(project.id)

      assert {:error, :restore_actor_unauthorized} =
               perform_job(
                 RestoreProjectWorker,
                 restore_args(project, snapshot, user, lock)
               )

      refute Projects.restoration_in_progress?(project.id)
      assert_received {:project_restoration_failed, %{reason: :restore_failed}}
      assert Versioning.count_project_snapshots(project.id) == 1
    end

    test "rejects an owned queued restore and releases its lock when containment is active", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {:ok, lock} =
        Projects.acquire_restoration_lock(
          project.id,
          user.id,
          snapshot.id
        )

      Collaboration.subscribe_restoration(project.id)

      policy =
        Application.get_env(:storyarn, RestorePolicy, [])

      Application.put_env(
        :storyarn,
        RestorePolicy,
        Keyword.put(policy, :project_snapshot_restore, false)
      )

      assert {:error, :restore_temporarily_disabled} =
               perform_job(
                 RestoreProjectWorker,
                 restore_args(project, snapshot, user, lock)
               )

      refute Projects.restoration_in_progress?(project.id)
      assert Versioning.count_project_snapshots(project.id) == 1

      assert_received {:project_restoration_failed, %{reason: :restore_temporarily_disabled}}
    end

    test "normalizes a thrown restore failure, releases the lock, and publishes failure", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {lock, job_id} = acquire_and_claim_lock(project, snapshot, user)
      Collaboration.subscribe_restoration(project.id)

      assert {:error, :restore_exception} =
               RestoreProjectWorker.perform_owned_restore(
                 project.id,
                 snapshot.id,
                 user.id,
                 lock.restoration_token,
                 job_id,
                 restore_fun: fn _project_id, _snapshot, _opts ->
                   throw(:restore_thrown)
                 end
               )

      refute Projects.restoration_in_progress?(project.id)
      assert_received {:project_restoration_failed, %{reason: :restore_failed}}
      refute_received {:project_restoration_completed, _payload}
    end

    test "normalizes a catchable restore exit, releases the lock, and publishes failure", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {lock, job_id} = acquire_and_claim_lock(project, snapshot, user)
      Collaboration.subscribe_restoration(project.id)

      assert {:error, :restore_exception} =
               RestoreProjectWorker.perform_owned_restore(
                 project.id,
                 snapshot.id,
                 user.id,
                 lock.restoration_token,
                 job_id,
                 restore_fun: fn _project_id, _snapshot, _opts ->
                   exit(:restore_exited)
                 end
               )

      refute Projects.restoration_in_progress?(project.id)
      assert_received {:project_restoration_failed, %{reason: :restore_failed}}
      refute_received {:project_restoration_completed, _payload}
    end

    test "suppresses terminal failure when owned lock release is not confirmed", %{
      project: project,
      user: user,
      snapshot: snapshot
    } do
      {lock, job_id} = acquire_and_claim_lock(project, snapshot, user)
      Collaboration.subscribe_restoration(project.id)

      assert {:error, {:restoration_lock_release_failed, :database_unavailable}} =
               RestoreProjectWorker.perform_owned_restore(
                 project.id,
                 snapshot.id,
                 user.id,
                 lock.restoration_token,
                 job_id,
                 restore_fun: fn _project_id, _snapshot, _opts ->
                   {:error, :restore_failed}
                 end,
                 release_fun: fn _project_id, _lock_token, _job_id ->
                   {:error, :database_unavailable}
                 end
               )

      assert {true, _metadata} = Projects.restoration_in_progress?(project.id)
      refute_received {:project_restoration_failed, _payload}
      refute_received {:project_restoration_completed, _payload}
    end
  end

  defp acquire_and_claim_lock(project, snapshot, user) do
    {:ok, lock} =
      Projects.acquire_restoration_lock(
        project.id,
        user.id,
        snapshot.id
      )

    job =
      build_job(
        RestoreProjectWorker,
        restore_args(project, snapshot, user, lock)
      )

    assert {:ok, _project} =
             Projects.claim_restoration_lock(
               project.id,
               user.id,
               snapshot.id,
               lock.restoration_token,
               job.id
             )

    {lock, job.id}
  end

  defp restore_args(project, snapshot, user, lock) do
    %{
      project_id: project.id,
      snapshot_id: snapshot.id,
      user_id: user.id,
      lock_token: lock.restoration_token
    }
  end
end

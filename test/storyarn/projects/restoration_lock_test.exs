defmodule Storyarn.Projects.RestorationLockTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Projects

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "acquire_restoration_lock/2" do
    test "succeeds on unlocked project", %{project: project, user: user} do
      assert {:ok, locked_project} = Projects.acquire_restoration_lock(project.id, user.id)
      assert locked_project.restoration_in_progress == true
      assert locked_project.restoration_started_by_id == user.id
      assert locked_project.restoration_started_at != nil
    end

    test "fails on already-locked project", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      other_user = user_fixture()

      assert {:error, :already_locked} =
               Projects.acquire_restoration_lock(project.id, other_user.id)
    end

    test "fails when same user tries to lock twice", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)
      assert {:error, :already_locked} = Projects.acquire_restoration_lock(project.id, user.id)
    end
  end

  describe "release_restoration_lock/1" do
    test "clears all lock fields", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)
      {:ok, released} = Projects.release_restoration_lock(project.id)

      assert released.restoration_in_progress == false
      assert released.restoration_started_by_id == nil
      assert released.restoration_started_at == nil
    end
  end

  describe "restoration_in_progress?/1" do
    test "returns false for unlocked project", %{project: project} do
      assert Projects.restoration_in_progress?(project.id) == false
    end

    test "returns {true, info} for locked project", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      assert {true, %{user_id: uid, started_at: %DateTime{}}} =
               Projects.restoration_in_progress?(project.id)

      assert uid == user.id
    end
  end

  describe "clear_stale_restoration_lock/2" do
    test "clears lock older than timeout", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      # Manually set started_at to 20 minutes ago
      old_time = DateTime.add(DateTime.utc_now(), -20 * 60, :second)

      Storyarn.Repo.update_all(
        from(p in Storyarn.Projects.Project, where: p.id == ^project.id),
        set: [restoration_started_at: old_time]
      )

      assert {:ok, :cleared} = Projects.clear_stale_restoration_lock(project.id, 15)
      assert Projects.restoration_in_progress?(project.id) == false
    end

    test "does not clear recent lock", %{project: project, user: user} do
      {:ok, _} = Projects.acquire_restoration_lock(project.id, user.id)

      assert {:error, :not_stale} = Projects.clear_stale_restoration_lock(project.id, 15)
      assert {true, _} = Projects.restoration_in_progress?(project.id)
    end
  end
end

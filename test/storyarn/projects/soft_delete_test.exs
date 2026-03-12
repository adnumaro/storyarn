defmodule Storyarn.Projects.SoftDeleteTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Projects

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  describe "soft delete" do
    test "delete_project/2 sets deleted_at and deleted_by_id" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      assert deleted.deleted_at != nil
      assert deleted.deleted_by_id == user.id
    end

    test "soft-deleted projects are filtered from list_projects/1" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(project, user.id)

      assert Projects.list_projects(scope) == []
    end

    test "soft-deleted projects are filtered from get_project/2" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(project, user.id)

      assert {:error, :not_found} = Projects.get_project(scope, project.id)
    end

    test "soft-deleted projects are filtered from list_projects_for_workspace/2" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(project, user.id)

      assert Projects.list_projects_for_workspace(workspace.id, scope) == []
    end

    test "soft-deleted projects are filtered from list_projects_with_auto_snapshots/0" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(project, user.id)

      projects = Projects.list_projects_with_auto_snapshots()
      project_ids = Enum.map(projects, & &1.id)
      refute project.id in project_ids
    end
  end

  describe "list_deleted_projects/1" do
    test "returns soft-deleted projects in workspace" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(project, user.id)

      deleted = Projects.list_deleted_projects(workspace.id)
      assert length(deleted) == 1
      assert hd(deleted).id == project.id
      assert hd(deleted).deleted_at != nil
    end

    test "does not include non-deleted projects" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      _project = project_fixture(user, %{workspace: workspace})

      assert Projects.list_deleted_projects(workspace.id) == []
    end

    test "includes snapshot_count" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(project, user.id)

      [deleted] = Projects.list_deleted_projects(workspace.id)
      assert deleted.snapshot_count == 0
    end

    test "preloads deleted_by user" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(project, user.id)

      [deleted] = Projects.list_deleted_projects(workspace.id)
      assert deleted.deleted_by.id == user.id
    end
  end

  describe "get_deleted_project/2" do
    test "returns a deleted project" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      {:ok, _} = Projects.delete_project(project, user.id)

      deleted = Projects.get_deleted_project(workspace.id, project.id)
      assert deleted != nil
      assert deleted.id == project.id
    end

    test "returns nil for non-deleted project" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      assert Projects.get_deleted_project(workspace.id, project.id) == nil
    end
  end

  describe "permanently_delete_project/1" do
    test "removes the project from the database" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(project, user.id)
      deleted = Storyarn.Repo.get(Projects.Project, project.id)

      assert {:ok, _} = Projects.permanently_delete_project(deleted)
      assert Storyarn.Repo.get(Projects.Project, project.id) == nil
    end
  end
end

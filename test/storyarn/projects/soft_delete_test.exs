defmodule Storyarn.Projects.SoftDeleteTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  describe "soft delete" do
    test "delete_project/2 sets deleted_at and deleted_by_id" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      assert deleted.deleted_at
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
      assert hd(deleted).deleted_at
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
      assert deleted
      assert deleted.id == project.id
    end

    test "returns nil for non-deleted project" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      assert Projects.get_deleted_project(workspace.id, project.id) == nil
    end
  end

  describe "list_deleted_items_for_retention/1" do
    test "uses a stable cursor to page through deleted items" do
      project = project_fixture()
      first_sheet = sheet_fixture(project)
      second_sheet = sheet_fixture(project)

      assert {:ok, _deleted} = Sheets.delete_sheet(first_sheet)
      assert {:ok, _deleted} = Sheets.delete_sheet(second_sheet)

      assert [first_page_item] = Projects.list_deleted_items_for_retention(limit: 1)

      cursor = {first_page_item.deleted_at, first_page_item.type, first_page_item.id}

      assert [second_page_item] =
               Projects.list_deleted_items_for_retention(limit: 1, after: cursor)

      refute second_page_item.id == first_page_item.id

      final_cursor =
        {second_page_item.deleted_at, second_page_item.type, second_page_item.id}

      assert Projects.list_deleted_items_for_retention(limit: 1, after: final_cursor) == []
    end

    test "normalizes invalid limits and caps oversized batches" do
      project = project_fixture()
      sheet = sheet_fixture(project)
      assert {:ok, _deleted} = Sheets.delete_sheet(sheet)

      assert length(Projects.list_deleted_items_for_retention(limit: nil)) == 1
      assert length(Projects.list_deleted_items_for_retention(limit: -10)) == 1
      assert length(Projects.list_deleted_items_for_retention(limit: 10_000)) == 1
    end

    test "keeps a cleanup run bounded to its starting cutoff" do
      project = project_fixture()
      first_sheet = sheet_fixture(project)
      second_sheet = sheet_fixture(project)

      assert {:ok, _deleted} = Sheets.delete_sheet(first_sheet)
      cutoff = Projects.deleted_items_retention_cutoff()
      assert {:ok, _deleted} = Sheets.delete_sheet(second_sheet)

      assert [item] = Projects.list_deleted_items_for_retention(through: cutoff)
      assert item.id == first_sheet.id
    end
  end

  describe "permanently_delete_project/1" do
    test "removes the project from the database" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} = Projects.delete_project(project, user.id)
      deleted = Repo.get(Projects.Project, project.id)

      assert {:ok, _} = Projects.permanently_delete_project(deleted)
      assert Repo.get(Projects.Project, project.id) == nil
    end

    test "cascades a project with recorded voice-overs without violating the asset constraint" do
      user = user_fixture()
      project = project_fixture(user)
      audio = audio_asset_fixture(project, user)
      text = localized_text_fixture(project.id)

      assert {:ok, _recorded} =
               Localization.update_text(text, %{
                 vo_asset_id: audio.id,
                 vo_status: "recorded"
               })

      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(Projects.Project, project.id)
    end
  end
end

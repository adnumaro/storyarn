defmodule Storyarn.AuthorizationTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Authorization

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  describe "get_effective_role/2 for projects" do
    test "returns project role when user has project membership" do
      owner = user_fixture()
      project = project_fixture(owner)

      assert {:ok, "owner", :project} = Authorization.get_effective_role(owner, project)
    end

    test "returns workspace role when user has only workspace membership" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      # Create a project in the workspace by another user
      project_owner = user_fixture()
      workspace_membership_fixture(workspace, project_owner, "admin")

      scope = user_scope_fixture(project_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Test Project",
          workspace_id: workspace.id
        })

      # Workspace owner should have access through workspace membership
      assert {:ok, "owner", :workspace} =
               Authorization.get_effective_role(workspace_owner, project)
    end

    test "returns no_access when user has neither membership" do
      owner = user_fixture()
      project = project_fixture(owner)
      stranger = user_fixture()

      assert {:error, :no_access} = Authorization.get_effective_role(stranger, project)
    end

    test "project membership overrides workspace membership" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      member = user_fixture()
      # Member at workspace level
      workspace_membership_fixture(workspace, member, "member")

      # Create a project in the workspace
      scope = user_scope_fixture(workspace_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Test Project",
          workspace_id: workspace.id
        })

      # Add member as viewer at project level (more restrictive)
      Storyarn.ProjectsFixtures.membership_fixture(project, member, "viewer")

      # Should get project role (viewer), not workspace role (member)
      assert {:ok, "viewer", :project} = Authorization.get_effective_role(member, project)
    end
  end

  describe "can?/3 for projects" do
    test "owner can perform all actions" do
      owner = user_fixture()
      project = project_fixture(owner)

      assert Authorization.can?(owner, :manage_project, project)
      assert Authorization.can?(owner, :manage_members, project)
      assert Authorization.can?(owner, :edit_content, project)
      assert Authorization.can?(owner, :view, project)
    end

    test "editor can edit and view" do
      owner = user_fixture()
      project = project_fixture(owner)
      editor = user_fixture()
      _membership = membership_fixture(project, editor, "editor")

      assert Authorization.can?(editor, :edit_content, project)
      assert Authorization.can?(editor, :view, project)
      refute Authorization.can?(editor, :manage_project, project)
      refute Authorization.can?(editor, :manage_members, project)
    end

    test "viewer can only view" do
      owner = user_fixture()
      project = project_fixture(owner)
      viewer = user_fixture()
      _membership = membership_fixture(project, viewer, "viewer")

      assert Authorization.can?(viewer, :view, project)
      refute Authorization.can?(viewer, :edit_content, project)
      refute Authorization.can?(viewer, :manage_project, project)
    end

    test "stranger cannot access" do
      owner = user_fixture()
      project = project_fixture(owner)
      stranger = user_fixture()

      refute Authorization.can?(stranger, :view, project)
    end
  end

  describe "can?/3 for workspaces" do
    test "owner can perform all actions" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      assert Authorization.can?(owner, :manage_workspace, workspace)
      assert Authorization.can?(owner, :manage_members, workspace)
      assert Authorization.can?(owner, :create_project, workspace)
      assert Authorization.can?(owner, :view, workspace)
    end

    test "admin can manage members and create projects" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      assert Authorization.can?(admin, :manage_members, workspace)
      assert Authorization.can?(admin, :create_project, workspace)
      assert Authorization.can?(admin, :view, workspace)
      refute Authorization.can?(admin, :manage_workspace, workspace)
    end

    test "member can create projects and view" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      assert Authorization.can?(member, :create_project, workspace)
      assert Authorization.can?(member, :view, workspace)
      refute Authorization.can?(member, :manage_members, workspace)
    end

    test "viewer can only view" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")

      assert Authorization.can?(viewer, :view, workspace)
      refute Authorization.can?(viewer, :create_project, workspace)
      refute Authorization.can?(viewer, :manage_members, workspace)
    end

    test "stranger cannot access" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      stranger = user_fixture()

      refute Authorization.can?(stranger, :view, workspace)
    end
  end

  describe "authorize_project/3" do
    test "returns project with role info when authorized" do
      owner = user_fixture()
      project = project_fixture(owner)

      assert {:ok, returned_project, "owner", :project} =
               Authorization.authorize_project(owner, project.id, :view)

      assert returned_project.id == project.id
    end

    test "returns unauthorized for insufficient permissions" do
      owner = user_fixture()
      project = project_fixture(owner)
      viewer = user_fixture()
      _membership = membership_fixture(project, viewer, "viewer")

      assert {:error, :unauthorized} =
               Authorization.authorize_project(viewer, project.id, :manage_project)
    end

    test "returns not_found for non-existent project" do
      user = user_fixture()

      assert {:error, :not_found} = Authorization.authorize_project(user, 999_999, :view)
    end

    test "returns unauthorized when user has no access at all" do
      owner = user_fixture()
      project = project_fixture(owner)
      stranger = user_fixture()

      assert {:error, :unauthorized} =
               Authorization.authorize_project(stranger, project.id, :view)
    end
  end

  describe "get_role_in_workspace/2" do
    test "returns role for a workspace member" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      assert {:ok, "owner"} = Authorization.get_role_in_workspace(owner, workspace)
    end

    test "returns no_access for a non-member" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      stranger = user_fixture()

      assert {:error, :no_access} = Authorization.get_role_in_workspace(stranger, workspace)
    end

    test "returns the correct role for different membership levels" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")
      assert {:ok, "admin"} = Authorization.get_role_in_workspace(admin, workspace)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")
      assert {:ok, "member"} = Authorization.get_role_in_workspace(member, workspace)

      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")
      assert {:ok, "viewer"} = Authorization.get_role_in_workspace(viewer, workspace)
    end
  end

  describe "can?/3 for projects with admin role (via workspace inheritance)" do
    test "admin can edit content and view" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      scope = user_scope_fixture(workspace_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Admin Test Project",
          workspace_id: workspace.id
        })

      # Admin inherits workspace role -> project_action_allowed?("admin", ...)
      assert Authorization.can?(admin, :edit_content, project)
      assert Authorization.can?(admin, :view, project)
    end

    test "admin cannot manage project or members" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      scope = user_scope_fixture(workspace_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Admin Test Project 2",
          workspace_id: workspace.id
        })

      refute Authorization.can?(admin, :manage_project, project)
      refute Authorization.can?(admin, :manage_members, project)
    end
  end

  describe "can?/3 for projects with member role (via workspace inheritance)" do
    test "member can edit content and view" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      scope = user_scope_fixture(workspace_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Member Test Project",
          workspace_id: workspace.id
        })

      # Member inherits workspace role -> project_action_allowed?("member", ...)
      assert Authorization.can?(member, :edit_content, project)
      assert Authorization.can?(member, :view, project)
    end

    test "member cannot manage project or members" do
      workspace_owner = user_fixture()
      workspace = workspace_fixture(workspace_owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      scope = user_scope_fixture(workspace_owner)

      {:ok, project} =
        Storyarn.Projects.create_project(scope, %{
          name: "Member Test Project 2",
          workspace_id: workspace.id
        })

      refute Authorization.can?(member, :manage_project, project)
      refute Authorization.can?(member, :manage_members, project)
    end
  end

  describe "permission_source_label/1" do
    test "returns 'project' for :project source" do
      assert Authorization.permission_source_label(:project) == "project"
    end

    test "returns 'workspace (inherited)' for :workspace source" do
      assert Authorization.permission_source_label(:workspace) == "workspace (inherited)"
    end
  end
end

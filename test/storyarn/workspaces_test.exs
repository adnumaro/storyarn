defmodule Storyarn.WorkspacesTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Workspaces

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  describe "workspaces" do
    test "list_workspaces/1 returns workspaces user has access to" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      # User should have a default workspace created on registration
      result = Workspaces.list_workspaces(scope)
      assert result != []
      assert hd(result).role == "owner"
    end

    test "list_workspaces/1 returns workspaces where user is a member" do
      owner = user_fixture()
      member = user_fixture()
      workspace = workspace_fixture(owner)
      _membership = workspace_membership_fixture(workspace, member, "member")

      member_scope = user_scope_fixture(member)
      result = Workspaces.list_workspaces(member_scope)

      # Should include both the default workspace and the one where user is a member
      workspace_ids = Enum.map(result, & &1.workspace.id)
      assert workspace.id in workspace_ids
    end

    test "list_workspaces_for_user/1 returns all workspaces for a user" do
      user = user_fixture()

      workspaces = Workspaces.list_workspaces_for_user(user)
      # User should have at least the default workspace
      assert workspaces != []
    end

    test "get_default_workspace/1 returns user's default workspace" do
      user = user_fixture()

      workspace = Workspaces.get_default_workspace(user)
      assert workspace != nil
      # Default workspace name should include user's name or email prefix
      assert workspace.name =~ "workspace"
    end

    test "get_workspace/2 returns workspace with membership" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:ok, returned_workspace, membership} = Workspaces.get_workspace(scope, workspace.id)
      assert returned_workspace.id == workspace.id
      assert membership.role == "owner"
    end

    test "get_workspace/2 returns error for non-member" do
      user = user_fixture()
      other_user = user_fixture()
      workspace = workspace_fixture(other_user)

      scope = user_scope_fixture(user)
      assert {:error, :not_found} = Workspaces.get_workspace(scope, workspace.id)
    end

    test "get_workspace_by_slug/2 returns workspace with membership" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:ok, returned_workspace, membership} =
               Workspaces.get_workspace_by_slug(scope, workspace.slug)

      assert returned_workspace.id == workspace.id
      assert membership.role == "owner"
    end

    test "create_workspace/2 creates workspace with owner membership" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      attrs = %{name: "Test Workspace", description: "A test", slug: "test-workspace"}
      assert {:ok, workspace} = Workspaces.create_workspace(scope, attrs)
      assert workspace.name == "Test Workspace"
      assert workspace.description == "A test"
      assert workspace.slug == "test-workspace"
      assert workspace.owner_id == user.id

      # Check owner membership was created
      membership = Workspaces.get_membership(workspace.id, user.id)
      assert membership.role == "owner"
    end

    test "create_workspace/2 with invalid data returns error" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      assert {:error, changeset} = Workspaces.create_workspace(scope, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_workspace/2 updates the workspace" do
      user = user_fixture()
      workspace = workspace_fixture(user)

      assert {:ok, updated} = Workspaces.update_workspace(workspace, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_workspace/1 deletes the workspace" do
      user = user_fixture()
      workspace = workspace_fixture(user)

      assert {:ok, _} = Workspaces.delete_workspace(workspace)
      assert_raise Ecto.NoResultsError, fn -> Workspaces.get_workspace!(workspace.id) end
    end

    test "generate_slug/1 creates URL-safe slug" do
      slug = Workspaces.generate_slug("My Test Workspace")
      assert slug =~ ~r/^[a-z0-9-]+$/
      assert slug =~ "my-test-workspace"
    end

    test "generate_slug/1 handles special characters" do
      slug = Workspaces.generate_slug("Test & Workspace!")
      assert slug =~ ~r/^[a-z0-9-]+$/
    end
  end

  describe "memberships" do
    test "list_workspace_members/1 returns all members" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")

      members = Workspaces.list_workspace_members(workspace.id)
      # Should include owner and the added member
      assert length(members) == 2
      roles = Enum.map(members, & &1.role)
      assert "owner" in roles
      assert "member" in roles
    end

    test "get_membership/2 returns membership" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      membership = Workspaces.get_membership(workspace.id, owner.id)
      assert membership.role == "owner"
    end

    test "create_membership/3 creates a membership" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      new_member = user_fixture()

      assert {:ok, membership} =
               Workspaces.create_membership(workspace.id, new_member.id, "member")

      assert membership.role == "member"
      assert membership.workspace_id == workspace.id
      assert membership.user_id == new_member.id
    end

    test "update_member_role/2 updates the role" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      assert {:ok, updated} = Workspaces.update_member_role(membership, "admin")
      assert updated.role == "admin"
    end

    test "update_member_role/2 cannot change owner role" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      owner_membership = Workspaces.get_membership(workspace.id, owner.id)

      assert {:error, :cannot_change_owner_role} =
               Workspaces.update_member_role(owner_membership, "admin")
    end

    test "remove_member/1 removes the member" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      assert {:ok, _} = Workspaces.remove_member(membership)
      assert Workspaces.get_membership(workspace.id, member.id) == nil
    end

    test "remove_member/1 cannot remove owner" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      owner_membership = Workspaces.get_membership(workspace.id, owner.id)

      assert {:error, :cannot_remove_owner} = Workspaces.remove_member(owner_membership)
    end
  end

  describe "authorization" do
    test "authorize/3 allows owner all actions" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:ok, _, _} = Workspaces.authorize(scope, workspace.id, :manage_workspace)
      assert {:ok, _, _} = Workspaces.authorize(scope, workspace.id, :manage_members)
      assert {:ok, _, _} = Workspaces.authorize(scope, workspace.id, :create_project)
      assert {:ok, _, _} = Workspaces.authorize(scope, workspace.id, :view)
    end

    test "authorize/3 allows admin to manage members and create projects" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      _membership = workspace_membership_fixture(workspace, admin, "admin")
      admin_scope = user_scope_fixture(admin)

      assert {:ok, _, _} = Workspaces.authorize(admin_scope, workspace.id, :manage_members)
      assert {:ok, _, _} = Workspaces.authorize(admin_scope, workspace.id, :create_project)
      assert {:ok, _, _} = Workspaces.authorize(admin_scope, workspace.id, :view)
    end

    test "authorize/3 allows member to create projects and view" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      _membership = workspace_membership_fixture(workspace, member, "member")
      member_scope = user_scope_fixture(member)

      assert {:ok, _, _} = Workspaces.authorize(member_scope, workspace.id, :create_project)
      assert {:ok, _, _} = Workspaces.authorize(member_scope, workspace.id, :view)
    end

    test "authorize/3 allows viewer only to view" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      viewer = user_fixture()
      _membership = workspace_membership_fixture(workspace, viewer, "viewer")
      viewer_scope = user_scope_fixture(viewer)

      assert {:ok, _, _} = Workspaces.authorize(viewer_scope, workspace.id, :view)

      assert {:error, :unauthorized} =
               Workspaces.authorize(viewer_scope, workspace.id, :create_project)
    end

    test "authorize/3 returns error for non-member" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      stranger = user_fixture()
      stranger_scope = user_scope_fixture(stranger)

      assert {:error, :not_found} = Workspaces.authorize(stranger_scope, workspace.id, :view)
    end
  end
end

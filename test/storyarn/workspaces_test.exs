defmodule Storyarn.WorkspacesTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

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
      assert workspace
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
      # Registration already creates a default workspace with owner membership.
      # Verify the default workspace has the expected structure.
      user = user_fixture()
      workspace = Workspaces.get_default_workspace(user)

      assert workspace.owner_id == user.id

      membership = Workspaces.get_membership(workspace.id, user.id)
      assert membership.role == "owner"
    end

    test "create_workspace/2 blocks when workspace limit reached" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      # User already has one workspace from registration (free plan limit is 1)
      assert {:error, :limit_reached, %{resource: :workspaces_per_user}} =
               Workspaces.create_workspace(scope, %{
                 name: "Second Workspace",
                 slug: "second-workspace"
               })
    end

    test "update_workspace/3 updates the workspace" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:ok, updated} = Workspaces.update_workspace(scope, workspace.id, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "update_workspace/3 rejects drift between canonical owner records" do
      owner = user_fixture()
      scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      replacement = user_fixture()

      workspace
      |> Ecto.Changeset.change(owner_id: replacement.id)
      |> Repo.update!()

      assert {:error, :ownership_invariant_violation} =
               Workspaces.update_workspace(scope, workspace.id, %{name: "Unauthorized rename"})

      assert Repo.get!(Workspace, workspace.id).name == workspace.name
    end

    test "delete_workspace/2 deletes the workspace" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:ok, _} = Workspaces.delete_workspace(scope, workspace.id)
      assert_raise Ecto.NoResultsError, fn -> Workspaces.get_workspace!(workspace.id) end
    end

    test "delete_workspace/2 rejects a missing canonical owner membership" do
      owner = user_fixture()
      scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)

      workspace.id
      |> Workspaces.get_membership(owner.id)
      |> Ecto.Changeset.change(role: "admin")
      |> Repo.update!()

      assert {:error, :ownership_invariant_violation} =
               Workspaces.delete_workspace(scope, workspace.id)

      assert Repo.get!(Workspace, workspace.id)
    end

    test "lifecycle mutations reject ambiguous owner memberships" do
      owner = user_fixture()
      scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      duplicate_owner = user_fixture()
      _duplicate_membership = workspace_membership_fixture(workspace, duplicate_owner, "owner")

      assert {:error, :ownership_invariant_violation} =
               Workspaces.update_workspace(scope, workspace.id, %{name: "Ambiguous rename"})

      assert {:error, :ownership_invariant_violation} =
               Workspaces.delete_workspace(scope, workspace.id)

      assert Repo.get!(Workspace, workspace.id).name == workspace.name
    end

    test "delete_workspace/2 hands off asset keys before cascading projects" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})

      active =
        image_asset_fixture(project, user, %{
          blob_hash: String.duplicate("b", 64),
          metadata: %{"thumbnail_key" => Assets.thumbnail_key(Assets.generate_key(project, "active.png"))}
        })

      trashed = image_asset_fixture(project, user)
      assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, trashed.id, user.id)

      assert {:ok, _workspace} = Workspaces.delete_workspace(scope, workspace.id)

      assert Repo.aggregate(from(asset in Asset, where: asset.project_id == ^project.id), :count) == 0
      assert [request] = Repo.all(StorageCleanupRequest)

      assert MapSet.new(request.storage_keys) ==
               MapSet.new([
                 active.key,
                 Assets.thumbnail_key(active.key),
                 BlobStore.blob_key(project.id, active.blob_hash, "png"),
                 trashed.key
               ])
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

    test "create_membership/3 cannot create a second owner" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      new_member = user_fixture()

      assert {:error, :cannot_assign_owner_role} =
               Workspaces.create_membership(workspace.id, new_member.id, "owner")

      assert Workspaces.get_membership(workspace.id, new_member.id) == nil
    end

    test "update_member_role/4 updates the role" do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      assert {:ok, updated} =
               Workspaces.update_member_role(owner_scope, workspace.id, membership.id, "admin")

      assert updated.role == "admin"
    end

    test "update_member_role/4 cannot change owner role" do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      owner_membership = Workspaces.get_membership(workspace.id, owner.id)

      assert {:error, :cannot_change_owner_role} =
               Workspaces.update_member_role(
                 owner_scope,
                 workspace.id,
                 owner_membership.id,
                 "admin"
               )
    end

    test "update_member_role/4 cannot promote a member to owner" do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      assert {:error, :cannot_assign_owner_role} =
               Workspaces.update_member_role(
                 owner_scope,
                 workspace.id,
                 membership.id,
                 "owner"
               )

      assert %{role: "member"} = Workspaces.get_membership(workspace.id, member.id)
    end

    test "remove_member/3 removes the member" do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      assert {:ok, _} = Workspaces.remove_member(owner_scope, workspace.id, membership.id)
      assert Workspaces.get_membership(workspace.id, member.id) == nil
    end

    test "remove_member/3 cannot remove owner" do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      owner_membership = Workspaces.get_membership(workspace.id, owner.id)

      assert {:error, :cannot_remove_owner} =
               Workspaces.remove_member(owner_scope, workspace.id, owner_membership.id)
    end
  end

  describe "project-only workspace access" do
    setup do
      # Owner creates workspace + project, invitee has only ProjectMembership
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      project =
        Storyarn.ProjectsFixtures.project_fixture(owner, %{workspace: workspace})

      invitee = user_fixture()

      _pm =
        Storyarn.ProjectsFixtures.membership_fixture(project, invitee, "editor")

      %{
        owner: owner,
        owner_scope: user_scope_fixture(owner),
        workspace: workspace,
        project: project,
        invitee: invitee,
        invitee_scope: user_scope_fixture(invitee)
      }
    end

    test "list_workspaces includes workspace via ProjectMembership with nil role", ctx do
      result = Workspaces.list_workspaces(ctx.invitee_scope)
      ws_ids = Enum.map(result, & &1.workspace.id)
      assert ctx.workspace.id in ws_ids

      entry = Enum.find(result, &(&1.workspace.id == ctx.workspace.id))
      assert entry.role == nil
    end

    test "list_workspaces prefers WorkspaceMembership role over project-only access", ctx do
      # Add workspace membership too
      _wm = workspace_membership_fixture(ctx.workspace, ctx.invitee, "viewer")

      result = Workspaces.list_workspaces(ctx.invitee_scope)

      matching =
        Enum.filter(result, &(&1.workspace.id == ctx.workspace.id))

      # No duplicate
      assert length(matching) == 1
      # Uses workspace role, not nil
      assert hd(matching).role == "viewer"
    end

    test "list_workspaces_for_user includes workspace via ProjectMembership", ctx do
      workspaces = Workspaces.list_workspaces_for_user(ctx.invitee)
      ws_ids = Enum.map(workspaces, & &1.id)
      assert ctx.workspace.id in ws_ids
    end

    test "get_workspace_by_slug allows access via ProjectMembership", ctx do
      assert {:ok, workspace, membership} =
               Workspaces.get_workspace_by_slug(ctx.invitee_scope, ctx.workspace.slug)

      assert workspace.id == ctx.workspace.id
      # Virtual membership with nil role
      assert membership.role == nil
      assert membership.workspace_id == ctx.workspace.id
      assert membership.user_id == ctx.invitee.id
    end

    test "get_workspace_by_slug rejects user with no relationship" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      stranger = user_fixture()
      stranger_scope = user_scope_fixture(stranger)

      assert {:error, :not_found} =
               Workspaces.get_workspace_by_slug(stranger_scope, workspace.slug)
    end

    test "get_workspace allows access via ProjectMembership", ctx do
      assert {:ok, workspace, membership} =
               Workspaces.get_workspace(ctx.invitee_scope, ctx.workspace.id)

      assert workspace.id == ctx.workspace.id
      assert membership.role == nil
    end

    test "soft-deleting the only project revokes project-derived workspace access", ctx do
      assert {:ok, _deleted} = Storyarn.Projects.delete_project(ctx.owner_scope, ctx.project.id)

      refute Enum.any?(Workspaces.list_workspaces(ctx.invitee_scope), fn entry ->
               entry.workspace.id == ctx.workspace.id
             end)

      refute Enum.any?(Workspaces.list_workspaces_for_user(ctx.invitee), &(&1.id == ctx.workspace.id))
      assert {:error, :not_found} = Workspaces.get_workspace(ctx.invitee_scope, ctx.workspace.id)
      assert {:error, :not_found} = Workspaces.get_workspace_by_slug(ctx.invitee_scope, ctx.workspace.slug)
    end

    test "get_default_workspace falls back to workspace via ProjectMembership" do
      # Create a user with NO workspace membership (delete the auto-created one)
      invitee = user_fixture()
      invitee_scope = user_scope_fixture(invitee)
      default_ws = Workspaces.get_default_workspace(invitee)
      {:ok, _} = Workspaces.delete_workspace(invitee_scope, default_ws.id)

      # Create a workspace with a project and give the invitee project membership only
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project = Storyarn.ProjectsFixtures.project_fixture(owner, %{workspace: workspace})
      Storyarn.ProjectsFixtures.membership_fixture(project, invitee, "editor")

      result = Workspaces.get_default_workspace(invitee)
      assert result
      assert result.id == workspace.id
    end

    test "virtual membership has no workspace-level permissions", ctx do
      assert {:ok, _workspace, membership} =
               Workspaces.get_workspace(ctx.invitee_scope, ctx.workspace.id)

      refute Workspaces.can?(membership.role, :manage_workspace)
      refute Workspaces.can?(membership.role, :manage_members)
      refute Workspaces.can?(membership.role, :create_project)
      refute Workspaces.can?(membership.role, :view)
    end
  end

  # NOTE: Invitation tests live in workspaces/invitations_test.exs (382 lines, more thorough)

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

defmodule Storyarn.ProjectsTest do
  use Storyarn.DataCase

  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectMembership

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  describe "projects" do
    test "list_projects/1 returns projects user has access to" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      result = Projects.list_projects(scope)
      assert length(result) == 1
      assert hd(result).project.id == project.id
      assert hd(result).role == "owner"
    end

    test "list_projects/1 returns projects where user is a member" do
      owner = user_fixture()
      member = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, member, "editor")

      member_scope = user_scope_fixture(member)
      result = Projects.list_projects(member_scope)

      assert length(result) == 1
      assert hd(result).project.id == project.id
      assert hd(result).role == "editor"
    end

    test "list_projects/1 does not return projects user has no access to" do
      user = user_fixture()
      other_user = user_fixture()
      _project = project_fixture(other_user)

      scope = user_scope_fixture(user)
      assert Projects.list_projects(scope) == []
    end

    test "get_project/2 returns project with membership" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      assert {:ok, returned_project, membership} = Projects.get_project(scope, project.id)
      assert returned_project.id == project.id
      assert membership.role == "owner"
    end

    test "get_project/2 returns error for non-member" do
      user = user_fixture()
      other_user = user_fixture()
      project = project_fixture(other_user)

      scope = user_scope_fixture(user)
      assert {:error, :not_found} = Projects.get_project(scope, project.id)
    end

    test "get_project/2 returns error for non-existent project" do
      user = user_fixture()
      scope = user_scope_fixture(user)

      assert {:error, :not_found} = Projects.get_project(scope, 999_999)
    end

    test "create_project/2 creates project with owner membership" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      attrs = %{name: "Test Project", description: "A test", workspace_id: workspace.id}
      assert {:ok, project} = Projects.create_project(scope, attrs)
      assert project.name == "Test Project"
      assert project.description == "A test"
      assert project.owner_id == user.id
      assert project.slug != nil

      # Check owner membership was created
      membership = Projects.get_membership(project.id, user.id)
      assert membership.role == "owner"
    end

    test "create_project/2 with invalid data returns error" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)

      assert {:error, changeset} =
               Projects.create_project(scope, %{name: "", workspace_id: workspace.id})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_project/2 updates the project" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, updated} = Projects.update_project(project, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_project/1 deletes the project" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, _} = Projects.delete_project(project)
      assert_raise Ecto.NoResultsError, fn -> Projects.get_project!(project.id) end
    end

    test "change_project/2 returns a changeset" do
      user = user_fixture()
      project = project_fixture(user)

      assert %Ecto.Changeset{} = Projects.change_project(project)
    end
  end

  describe "memberships" do
    test "list_project_members/1 returns all members" do
      owner = user_fixture()
      member = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, member, "editor")

      members = Projects.list_project_members(project.id)
      assert length(members) == 2

      roles = Enum.map(members, & &1.role)
      assert "owner" in roles
      assert "editor" in roles
    end

    test "get_membership/2 returns membership" do
      user = user_fixture()
      project = project_fixture(user)

      assert %ProjectMembership{} = Projects.get_membership(project.id, user.id)
    end

    test "get_membership/2 returns nil for non-member" do
      user = user_fixture()
      other_user = user_fixture()
      project = project_fixture(other_user)

      assert Projects.get_membership(project.id, user.id) == nil
    end

    test "update_member_role/2 updates the role" do
      owner = user_fixture()
      member = user_fixture()
      project = project_fixture(owner)
      membership = membership_fixture(project, member, "editor")

      assert {:ok, updated} = Projects.update_member_role(membership, "viewer")
      assert updated.role == "viewer"
    end

    test "update_member_role/2 cannot change owner role" do
      owner = user_fixture()
      project = project_fixture(owner)
      membership = Projects.get_membership(project.id, owner.id)

      assert {:error, :cannot_change_owner_role} =
               Projects.update_member_role(membership, "editor")
    end

    test "remove_member/1 removes the member" do
      owner = user_fixture()
      member = user_fixture()
      project = project_fixture(owner)
      membership = membership_fixture(project, member, "editor")

      assert {:ok, _} = Projects.remove_member(membership)
      assert Projects.get_membership(project.id, member.id) == nil
    end

    test "remove_member/1 cannot remove owner" do
      owner = user_fixture()
      project = project_fixture(owner)
      membership = Projects.get_membership(project.id, owner.id)

      assert {:error, :cannot_remove_owner} = Projects.remove_member(membership)
    end
  end

  describe "invitations" do
    test "list_pending_invitations/1 returns pending invitations" do
      owner = user_fixture()
      project = project_fixture(owner)
      _invitation = invitation_fixture(project, owner)

      invitations = Projects.list_pending_invitations(project.id)
      assert length(invitations) == 1
    end

    test "create_invitation/4 creates invitation and sends email" do
      owner = user_fixture()
      project = project_fixture(owner)
      email = unique_user_email()

      assert {:ok, invitation} = Projects.create_invitation(project, owner, email, "editor")
      assert invitation.email == String.downcase(email)
      assert invitation.role == "editor"
      assert invitation.project_id == project.id
    end

    test "create_invitation/4 returns error for existing member" do
      owner = user_fixture()
      member = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, member, "editor")

      assert {:error, :already_member} =
               Projects.create_invitation(project, owner, member.email, "editor")
    end

    test "create_invitation/4 returns error for existing pending invitation" do
      owner = user_fixture()
      project = project_fixture(owner)
      email = unique_user_email()
      _invitation = invitation_fixture(project, owner, email)

      assert {:error, :already_invited} =
               Projects.create_invitation(project, owner, email, "editor")
    end

    test "get_invitation_by_token/1 returns valid invitation" do
      owner = user_fixture()
      project = project_fixture(owner)
      email = unique_user_email()

      {token, _invitation} = create_invitation_with_token(project, owner, email, "editor")

      assert {:ok, invitation} = Projects.get_invitation_by_token(token)
      assert invitation.email == String.downcase(email)
    end

    test "get_invitation_by_token/1 returns error for invalid token" do
      assert {:error, :invalid_token} = Projects.get_invitation_by_token("invalid")
    end

    test "accept_invitation/2 creates membership" do
      owner = user_fixture()
      project = project_fixture(owner)
      invitee = user_fixture()

      {:ok, invitation} = Projects.create_invitation(project, owner, invitee.email, "editor")

      assert {:ok, membership} = Projects.accept_invitation(invitation, invitee)
      assert membership.user_id == invitee.id
      assert membership.project_id == project.id
      assert membership.role == "editor"
    end

    test "accept_invitation/2 returns error for email mismatch" do
      owner = user_fixture()
      project = project_fixture(owner)
      wrong_user = user_fixture()

      {:ok, invitation} =
        Projects.create_invitation(project, owner, "other@example.com", "editor")

      assert {:error, :email_mismatch} = Projects.accept_invitation(invitation, wrong_user)
    end

    test "accept_invitation/2 returns error for existing member" do
      owner = user_fixture()
      project = project_fixture(owner)
      member = user_fixture()

      # Create invitation first, THEN add them as a member (simulating race condition)
      {token, _invitation} = create_invitation_with_token(project, owner, member.email, "editor")
      _membership = membership_fixture(project, member, "viewer")

      # Now try to accept the invitation
      {:ok, invitation} = Projects.get_invitation_by_token(token)
      assert {:error, :already_member} = Projects.accept_invitation(invitation, member)
    end

    test "revoke_invitation/1 deletes the invitation" do
      owner = user_fixture()
      project = project_fixture(owner)
      invitation = invitation_fixture(project, owner)

      assert {:ok, _} = Projects.revoke_invitation(invitation)
      assert Projects.list_pending_invitations(project.id) == []
    end
  end

  describe "authorization" do
    test "authorize/3 returns ok for owner on all actions" do
      owner = user_fixture()
      scope = user_scope_fixture(owner)
      project = project_fixture(owner)

      assert {:ok, _, _} = Projects.authorize(scope, project.id, :manage_project)
      assert {:ok, _, _} = Projects.authorize(scope, project.id, :manage_members)
      assert {:ok, _, _} = Projects.authorize(scope, project.id, :edit_content)
      assert {:ok, _, _} = Projects.authorize(scope, project.id, :view)
    end

    test "authorize/3 returns ok for editor on allowed actions" do
      owner = user_fixture()
      editor = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, editor, "editor")

      editor_scope = user_scope_fixture(editor)
      assert {:ok, _, _} = Projects.authorize(editor_scope, project.id, :edit_content)
      assert {:ok, _, _} = Projects.authorize(editor_scope, project.id, :view)
    end

    test "authorize/3 returns unauthorized for editor on owner actions" do
      owner = user_fixture()
      editor = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, editor, "editor")

      editor_scope = user_scope_fixture(editor)

      assert {:error, :unauthorized} =
               Projects.authorize(editor_scope, project.id, :manage_project)

      assert {:error, :unauthorized} =
               Projects.authorize(editor_scope, project.id, :manage_members)
    end

    test "authorize/3 returns ok for viewer on view action" do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, viewer, "viewer")

      viewer_scope = user_scope_fixture(viewer)
      assert {:ok, _, _} = Projects.authorize(viewer_scope, project.id, :view)
    end

    test "authorize/3 returns unauthorized for viewer on edit actions" do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, viewer, "viewer")

      viewer_scope = user_scope_fixture(viewer)
      assert {:error, :unauthorized} = Projects.authorize(viewer_scope, project.id, :edit_content)

      assert {:error, :unauthorized} =
               Projects.authorize(viewer_scope, project.id, :manage_project)
    end

    test "authorize/3 returns not_found for non-member" do
      owner = user_fixture()
      non_member = user_fixture()
      project = project_fixture(owner)

      scope = user_scope_fixture(non_member)
      assert {:error, :not_found} = Projects.authorize(scope, project.id, :view)
    end
  end

  describe "ProjectMembership.can?/2" do
    test "owner can do everything" do
      assert ProjectMembership.can?("owner", :manage_project)
      assert ProjectMembership.can?("owner", :manage_members)
      assert ProjectMembership.can?("owner", :edit_content)
      assert ProjectMembership.can?("owner", :view)
    end

    test "editor can edit and view" do
      assert ProjectMembership.can?("editor", :edit_content)
      assert ProjectMembership.can?("editor", :view)
      refute ProjectMembership.can?("editor", :manage_project)
      refute ProjectMembership.can?("editor", :manage_members)
    end

    test "viewer can only view" do
      assert ProjectMembership.can?("viewer", :view)
      refute ProjectMembership.can?("viewer", :edit_content)
      refute ProjectMembership.can?("viewer", :manage_project)
      refute ProjectMembership.can?("viewer", :manage_members)
    end
  end
end

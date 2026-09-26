defmodule Storyarn.Commercial.Billing.EditorSeatsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  setup do
    owner = user_fixture()
    %{owner: owner, owner_scope: user_scope_fixture(owner), workspace: workspace_fixture(owner)}
  end

  describe "what takes a seat" do
    test "the owner counts and viewers are free", %{owner: owner, owner_scope: scope, workspace: workspace} do
      for index <- 1..3 do
        assert {:ok, _invitation} =
                 Workspaces.create_invitation(scope, workspace.id, "viewer-#{index}@example.com", "viewer")
      end

      assert Billing.editor_seat_usage(owner.id) == %{used: 1, limit: 2}

      assert {:ok, _invitation} = Workspaces.create_invitation(scope, workspace.id, "editor@example.com", "member")

      assert {:error, :limit_reached, %{resource: :editors_per_account, used: 2, limit: 2}} =
               Workspaces.create_invitation(scope, workspace.id, "second-editor@example.com", "admin")
    end

    test "a pending editor invitation holds a seat until it is revoked", %{
      owner_scope: scope,
      workspace: workspace
    } do
      {:ok, invitation} = Workspaces.create_invitation(scope, workspace.id, "pending@example.com", "member")

      assert {:error, :limit_reached, %{used: 2}} =
               Workspaces.create_invitation(scope, workspace.id, "next@example.com", "member")

      assert {:ok, _revoked} = Workspaces.revoke_invitation(scope, workspace.id, invitation.id)
      assert {:ok, _invitation} = Workspaces.create_invitation(scope, workspace.id, "next@example.com", "member")
    end

    test "an editor counts once across two workspaces of the account", %{
      owner: owner,
      owner_scope: scope,
      workspace: workspace
    } do
      set_plan!(owner, "beta")

      {:ok, second_workspace} =
        Workspaces.create_workspace_with_owner(owner, %{name: "Second saga", slug: unique_slug("second")})

      editor = user_fixture()
      workspace_membership_fixture(workspace, editor, "member")
      workspace_membership_fixture(second_workspace, editor, "admin")
      project = project_fixture(owner, %{workspace: second_workspace})
      membership_fixture(project, editor, "editor")

      assert Billing.editor_seat_usage(owner.id).used == 2

      # Back on Free, the two seats fill the plan, yet the same editor can
      # still be invited somewhere else in the account.
      set_plan!(owner, "free")
      other_project = project_fixture(owner, %{workspace: second_workspace})

      assert {:ok, _invitation} = Projects.create_invitation(scope, other_project.id, editor.email, "editor")

      assert {:error, :limit_reached, %{used: 2, limit: 2}} =
               Projects.create_invitation(scope, other_project.id, "newcomer@example.com", "editor")
    end

    test "people in other accounts' workspaces do not count", %{owner: owner} do
      someone_else = workspace_fixture(user_fixture())
      workspace_membership_fixture(someone_else, user_fixture(), "member")

      assert Billing.editor_seat_usage(owner.id).used == 1
    end

    test "paid plans take one seat per editor instead of a cap", %{
      owner: owner,
      owner_scope: scope,
      workspace: workspace
    } do
      set_plan!(owner, "pro")

      for index <- 1..3 do
        assert {:ok, _invitation} =
                 Workspaces.create_invitation(scope, workspace.id, "pro-#{index}@example.com", "member")
      end

      assert Billing.editor_seat_usage(owner.id) == %{used: 4, limit: :paid_seats}
    end

    test "an operator invitation fills seats up to the plan", %{workspace: workspace} do
      assert {:ok, _invitation} = Workspaces.create_admin_invitation(workspace, "operator-1@example.com", "member")

      assert {:error, :limit_reached, %{resource: :editors_per_account}} =
               Workspaces.create_admin_invitation(workspace, "operator-2@example.com", "member")
    end
  end

  describe "who can add a seat" do
    setup %{owner: owner, workspace: workspace} do
      set_plan!(owner, "beta")
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")
      %{admin: admin, admin_scope: user_scope_fixture(admin)}
    end

    test "an admin cannot add a new seat", %{admin_scope: admin_scope, workspace: workspace} do
      assert {:error, :seat_requires_account_owner} =
               Workspaces.create_invitation(admin_scope, workspace.id, "new-editor@example.com", "member")
    end

    test "an admin can invite viewers", %{admin_scope: admin_scope, workspace: workspace} do
      assert {:ok, _invitation} =
               Workspaces.create_invitation(admin_scope, workspace.id, "reader@example.com", "viewer")
    end

    test "an admin can give an editing role to someone who already holds a seat", %{
      owner: owner,
      admin_scope: admin_scope,
      workspace: workspace
    } do
      {:ok, second_workspace} =
        Workspaces.create_workspace_with_owner(owner, %{name: "Second saga", slug: unique_slug("seat-holder")})

      editor = user_fixture()
      workspace_membership_fixture(second_workspace, editor, "member")

      assert {:ok, _invitation} =
               Workspaces.create_invitation(admin_scope, workspace.id, editor.email, "member")
    end

    test "a project owner who is not the account owner cannot add a seat", %{
      admin: admin,
      admin_scope: admin_scope,
      workspace: workspace
    } do
      project = project_fixture(admin, %{workspace: workspace})

      assert {:error, :seat_requires_account_owner} =
               Projects.create_invitation(admin_scope, project.id, "project-editor@example.com", "editor")

      assert {:ok, _invitation} =
               Projects.create_invitation(admin_scope, project.id, "project-viewer@example.com", "viewer")
    end
  end

  describe "role changes" do
    test "turning a workspace viewer into an editor takes a seat", %{
      owner_scope: scope,
      workspace: workspace
    } do
      editor = user_fixture()
      editor_membership = workspace_membership_fixture(workspace, editor, "member")
      viewer_membership = workspace_membership_fixture(workspace, user_fixture(), "viewer")

      assert {:error, :limit_reached, %{resource: :editors_per_account, used: 2, limit: 2}} =
               Workspaces.update_member_role(scope, workspace.id, viewer_membership.id, "member")

      assert {:ok, _viewer} = Workspaces.update_member_role(scope, workspace.id, editor_membership.id, "viewer")
      assert {:ok, _editor} = Workspaces.update_member_role(scope, workspace.id, viewer_membership.id, "member")
    end

    test "a project owner who is not the account owner cannot turn a viewer into an editor", %{
      owner: owner,
      workspace: workspace
    } do
      set_plan!(owner, "beta")
      project_owner = user_fixture()
      workspace_membership_fixture(workspace, project_owner, "member")
      project = project_fixture(project_owner, %{workspace: workspace})
      viewer_membership = membership_fixture(project, user_fixture(), "viewer")

      assert {:error, :seat_requires_account_owner} =
               Projects.update_member_role(
                 user_scope_fixture(project_owner),
                 project.id,
                 viewer_membership.id,
                 "editor"
               )

      assert Repo.reload!(viewer_membership).role == "viewer"
    end

    test "transferring a project to a viewer takes a seat", %{owner: owner, workspace: workspace} do
      set_plan!(owner, "beta")
      project_owner = user_fixture()
      workspace_membership_fixture(workspace, project_owner, "member")
      project = project_fixture(project_owner, %{workspace: workspace})
      viewer = user_fixture()
      membership_fixture(project, viewer, "viewer")

      assert {:error, :seat_requires_account_owner} =
               Projects.transfer_owner(user_scope_fixture(project_owner), project.id, viewer.id)

      assert Repo.reload!(project).owner_id == project_owner.id
    end
  end

  describe "acceptance" do
    test "counts memberships only, so invitations sent before a smaller plan can still fill it", %{
      owner: owner,
      owner_scope: scope,
      workspace: workspace
    } do
      set_plan!(owner, "beta")
      first = user_fixture()
      second = user_fixture()
      {:ok, first_invitation} = Workspaces.create_invitation(scope, workspace.id, first.email, "member")
      {:ok, second_invitation} = Workspaces.create_invitation(scope, workspace.id, second.email, "member")
      set_plan!(owner, "free")

      assert {:ok, _membership} = Workspaces.accept_invitation(first_invitation, first)

      assert {:error, :limit_reached, %{resource: :editors_per_account, used: 2, limit: 2}} =
               Workspaces.accept_invitation(second_invitation, second)
    end

    test "viewer invitations are accepted whatever the seats", %{owner_scope: scope, workspace: workspace} do
      workspace_membership_fixture(workspace, user_fixture(), "member")
      reader = user_fixture()
      {:ok, invitation} = Workspaces.create_invitation(scope, workspace.id, reader.email, "viewer")

      assert {:ok, _membership} = Workspaces.accept_invitation(invitation, reader)
    end
  end

  defp set_plan!(user, plan) do
    Subscription
    |> Repo.get_by!(user_id: user.id)
    |> Subscription.update_changeset(%{plan: plan, status: "active"})
    |> Repo.update!()
  end

  defp unique_slug(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end

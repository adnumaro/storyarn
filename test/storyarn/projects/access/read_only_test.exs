defmodule Storyarn.Projects.Access.ReadOnlyTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.CommercialFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Memberships

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    editor = user_fixture()
    viewer = user_fixture()
    membership_fixture(project, editor, "editor")
    membership_fixture(project, viewer, "viewer")

    %{
      owner: user_scope_fixture(owner),
      editor: user_scope_fixture(editor),
      viewer: user_scope_fixture(viewer),
      owner_user: owner,
      workspace: workspace,
      project: project
    }
  end

  describe "a read-only workspace" do
    setup %{owner_user: owner} do
      %{extra: lock_account!(owner)}
    end

    test "refuses to change the project", ctx do
      for action <- [:edit_content, :manage_project, :manage_members, :use_ai, :run_bulk_ai] do
        assert {:error, :read_only} = Projects.authorize(ctx.owner, ctx.project.id, action), inspect(action)
      end

      assert {:error, :read_only} = Projects.authorize(ctx.editor, ctx.project.id, :edit_content)
      assert {:error, :read_only} = Projects.authorize(ctx.editor, ctx.project.id, :use_ai)
    end

    test "keeps reading, commenting and everything that brings the account back within its limits", ctx do
      for action <- [
            :view,
            :comment,
            :delete_content,
            :delete_project,
            :remove_members,
            :read_snapshots,
            :delete_snapshot
          ] do
        assert {:ok, _project, _membership} = Projects.authorize(ctx.owner, ctx.project.id, action), inspect(action)
      end

      for action <- [:view, :comment, :delete_content] do
        assert {:ok, _project, _membership} = Projects.authorize(ctx.editor, ctx.project.id, action), inspect(action)
      end
    end

    test "changes nothing for viewers, who could not edit before either", ctx do
      assert {:error, :unauthorized} = Projects.authorize(ctx.viewer, ctx.project.id, :edit_content)
      assert {:error, :unauthorized} = Projects.authorize(ctx.viewer, ctx.project.id, :comment)
      assert {:ok, _project, _membership} = Projects.authorize(ctx.viewer, ctx.project.id, :view)
    end

    test "applies under row locks too", ctx do
      assert {:ok, {:error, :read_only}} =
               Repo.transaction(fn -> Projects.authorize_locked(ctx.owner, ctx.project.id, :edit_content) end)

      assert {:ok, {:ok, _project, _membership}} =
               Repo.transaction(fn -> Projects.authorize_locked(ctx.owner, ctx.project.id, :delete_content) end)
    end

    test "lets work admitted before the lock finish", ctx do
      assert {:ok, _project, _membership} = Memberships.authorize_admitted(ctx.owner, ctx.project.id, :manage_project)

      assert {:ok, {:ok, _project, _membership}} =
               Repo.transaction(fn ->
                 Memberships.authorize_admitted_locked(ctx.owner, ctx.project.id, :manage_project, :update)
               end)

      assert {:error, :unauthorized} = Memberships.authorize_admitted(ctx.viewer, ctx.project.id, :manage_project)
    end

    test "refuses new projects and ownership transfers", ctx do
      assert {:error, :read_only} =
               Projects.create_project(ctx.owner, %{
                 name: "Another",
                 workspace_id: ctx.workspace.id,
                 project_type: "game",
                 project_subtype: "rpg"
               })

      assert {:error, :read_only} = Projects.transfer_owner(ctx.owner, ctx.project.id, ctx.editor.user.id)
    end

    test "refuses invitations but lets the owner remove members and revoke pending ones", ctx do
      pending = pending_invitation(ctx)

      assert {:error, :read_only} = Projects.create_invitation(ctx.owner, ctx.project.id, unique_user_email(), "viewer")
      assert {:ok, _revoked} = Projects.revoke_invitation(ctx.owner, ctx.project.id, pending.id)

      membership = Projects.get_membership(ctx.project.id, ctx.editor.user.id)
      assert {:ok, _removed} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    end

    test "refuses to accept an invitation sent before the lock", ctx do
      invitee = user_fixture()
      {_token, invitation} = create_invitation_with_token(ctx.project, ctx.owner_user, invitee.email, "viewer")

      assert {:error, :read_only} = Projects.accept_invitation(invitation, invitee)
    end

    test "keeps commenting open", ctx do
      flow = flow_fixture(ctx.project)
      node = node_fixture(flow)
      request = %{body: "Still readable", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}

      assert {:ok, _detail} = Projects.create_flow_node_comment(ctx.editor, ctx.project.id, flow.id, node.id, request)
    end

    test "lets the owner delete the project", ctx do
      assert {:ok, _project} = Projects.delete_project(ctx.owner, ctx.project.id)
    end

    test "unlocks as soon as the account is back within its limits", ctx do
      unlock_account!(ctx.extra)

      assert {:ok, _project, _membership} = Projects.authorize(ctx.owner, ctx.project.id, :edit_content)
      assert {:ok, _project, _membership} = Projects.authorize(ctx.editor, ctx.project.id, :edit_content)
    end
  end

  test "a writable workspace authorizes as before", ctx do
    assert {:ok, _project, _membership} = Projects.authorize(ctx.owner, ctx.project.id, :edit_content)
    assert {:ok, _project, _membership} = Projects.authorize(ctx.editor, ctx.project.id, :edit_content)
  end

  # Inserted directly, as if it had been sent while the account was writable.
  defp pending_invitation(ctx) do
    {_token, invitation} = create_invitation_with_token(ctx.project, ctx.owner_user, unique_user_email(), "viewer")
    invitation
  end
end

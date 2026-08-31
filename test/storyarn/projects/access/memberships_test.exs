defmodule Storyarn.Projects.MembershipsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Memberships

  test "locked authorization preserves inherited workspace access" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    member = user_fixture()
    _workspace_membership = workspace_membership_fixture(workspace, member, "member")

    assert {:ok, {:ok, authorized_project, %{role: "editor", id: nil}}} =
             Repo.transaction(fn ->
               Memberships.authorize_locked(user_scope_fixture(member), project.id, :edit_content)
             end)

    assert authorized_project.id == project.id
  end

  test "locked authorization applies the complete inherited workspace role matrix" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    actions = [:view, :edit_content, :use_ai, :run_bulk_ai, :manage_project, :manage_members]

    matrix = [
      {"owner", "editor", [:view, :edit_content, :use_ai]},
      {"admin", "editor", [:view, :edit_content, :use_ai]},
      {"member", "editor", [:view, :edit_content, :use_ai]},
      {"viewer", "viewer", [:view]}
    ]

    for {workspace_role, expected_project_role, allowed_actions} <- matrix do
      user = user_fixture()
      _membership = workspace_membership_fixture(workspace, user, workspace_role)
      scope = user_scope_fixture(user)

      for action <- actions do
        result = authorize_locked(scope, project.id, action)

        if action in allowed_actions do
          assert {:ok, authorized_project, %{role: ^expected_project_role, id: nil}} = result
          assert authorized_project.id == project.id
        else
          assert {:error, :unauthorized} = result
        end
      end
    end
  end

  test "locked authorization keeps direct project membership precedence" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    member = user_fixture()
    _workspace_membership = workspace_membership_fixture(workspace, member, "admin")
    _project_membership = membership_fixture(project, member, "viewer")

    assert {:ok, {:error, :unauthorized}} =
             Repo.transaction(fn ->
               Memberships.authorize_locked(user_scope_fixture(member), project.id, :edit_content)
             end)
  end

  test "locked authorization lets a direct editor override inherited viewer access" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    member = user_fixture()
    _workspace_membership = workspace_membership_fixture(workspace, member, "viewer")
    direct_membership = membership_fixture(project, member, "editor")

    assert {:ok, _project, authorized_membership} =
             authorize_locked(user_scope_fixture(member), project.id, :edit_content)

    assert authorized_membership.id == direct_membership.id
    assert authorized_membership.role == "editor"
  end

  test "locked authorization rejects strangers and soft-deleted projects" do
    owner = user_fixture()
    stranger = user_fixture()
    project = project_fixture(owner)

    assert {:error, :not_found} =
             authorize_locked(user_scope_fixture(stranger), project.id, :view)

    project
    |> Ecto.Changeset.change(deleted_at: ~U[2026-01-01 00:00:00Z])
    |> Repo.update!()

    assert {:error, :not_found} =
             authorize_locked(user_scope_fixture(owner), project.id, :view)
  end

  test "locked authorization requires a transaction and rejects invalid callers" do
    owner = user_fixture()
    project = project_fixture(owner)
    scope = user_scope_fixture(owner)

    assert {:error, :authorization_transaction_required} =
             Memberships.authorize_locked(scope, project.id, :view)

    assert {:error, :unauthorized} = Memberships.authorize_locked(%{}, project.id, :view)
    assert {:error, :unauthorized} = Memberships.authorize_locked(scope, nil, :view)
    assert {:error, :unauthorized} = Memberships.authorize_locked(scope, -1, :view)
  end

  test "locked bulk AI authorization validates the canonical owner" do
    owner = user_fixture()
    project = project_fixture(owner)

    assert {:ok, _project, %{role: "owner"}} =
             authorize_locked(user_scope_fixture(owner), project.id, :run_bulk_ai)

    duplicate_owner = user_fixture()
    _duplicate_owner_membership = membership_fixture(project, duplicate_owner, "owner")

    assert {:error, :ownership_invariant_violation} =
             authorize_locked(user_scope_fixture(owner), project.id, :run_bulk_ai)
  end

  defp authorize_locked(scope, project_id, action) do
    assert {:ok, result} =
             Repo.transaction(fn ->
               Memberships.authorize_locked(scope, project_id, action)
             end)

    result
  end
end

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
end

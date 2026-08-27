defmodule Storyarn.Sheets.Access.Queries.ProjectsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Sheets
  alias Storyarn.Sheets.Access.Projections.ProjectMembershipRecord
  alias Storyarn.Sheets.Access.Projections.ProjectRecord

  test "returns an active project and its direct membership" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:ok, %ProjectRecord{id: project_id} = record, %ProjectMembershipRecord{} = membership} =
             Sheets.get_project(user_scope_fixture(user), project.id)

    assert project_id == project.id
    assert record.workspace.id == project.workspace_id
    assert membership.project_id == project.id
    assert membership.user_id == user.id
  end

  test "resolves the same access contract by workspace and project slugs" do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})

    assert {:ok, %ProjectRecord{id: project_id}, %ProjectMembershipRecord{user_id: user_id}} =
             Sheets.get_project_by_slugs(
               user_scope_fixture(user),
               workspace.slug,
               project.slug
             )

    assert project_id == project.id
    assert user_id == user.id
  end

  test "maps workspace membership to an effective project role" do
    owner = user_fixture()
    viewer = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    workspace_membership_fixture(workspace, viewer, "viewer")

    assert {:ok, %ProjectRecord{id: project_id}, %ProjectMembershipRecord{} = membership} =
             Sheets.get_project(user_scope_fixture(viewer), project.id)

    assert project_id == project.id
    assert membership.project_id == project.id
    assert membership.user_id == viewer.id
    assert membership.role == "viewer"
  end

  test "does not reveal a project to a user without membership" do
    owner = user_fixture()
    outsider = user_fixture()
    project = project_fixture(owner)

    assert {:error, :not_found} = Sheets.get_project(user_scope_fixture(outsider), project.id)
  end

  test "rejects malformed scopes and identifiers without querying membership" do
    assert {:error, :not_found} = Sheets.get_project(%{}, 1)
    assert {:error, :not_found} = Sheets.get_project(%{user: %{id: nil}}, 1)
    assert {:error, :not_found} = Sheets.get_project_by_slugs(%{}, "workspace", "project")
  end
end

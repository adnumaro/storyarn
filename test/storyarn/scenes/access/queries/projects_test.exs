defmodule Storyarn.Scenes.Access.Queries.ProjectsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Access.Projections.ProjectMembershipRecord
  alias Storyarn.Scenes.Access.Projections.ProjectRecord
  alias Storyarn.Scenes.Access.Projections.WorkspaceRecord

  test "authorizes a direct project member through Scene-owned projections" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    collaborator = user_fixture()
    direct_membership = membership_fixture(project, collaborator, "editor")
    scope = user_scope_fixture(collaborator)

    assert {:ok, %ProjectRecord{} = local_project, %ProjectMembershipRecord{id: membership_id, role: "editor"}} =
             Scenes.get_project(scope, project.id)

    assert local_project.id == project.id
    assert membership_id == direct_membership.id
    assert %WorkspaceRecord{id: workspace_id} = local_project.workspace
    assert workspace_id == workspace.id
  end

  test "falls back to workspace membership without borrowing the Projects model" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    workspace_member = user_fixture()
    workspace_membership_fixture(workspace, workspace_member, "admin")
    scope = user_scope_fixture(workspace_member)

    assert {:ok, %ProjectRecord{id: project_id},
            %ProjectMembershipRecord{
              id: nil,
              project_id: projected_project_id,
              user_id: projected_user_id,
              role: "editor"
            }} = Scenes.get_project(scope, project.id)

    assert project_id == project.id
    assert projected_project_id == project.id
    assert projected_user_id == workspace_member.id

    assert {:ok, %ProjectRecord{id: ^project_id}, %ProjectMembershipRecord{id: nil, role: "editor"}} =
             Scenes.get_project_by_slugs(scope, workspace.slug, project.slug)
  end

  test "hides an existing project from a user with no effective membership" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    outsider_scope = user_scope_fixture(user_fixture())

    assert {:error, :not_found} = Scenes.get_project(outsider_scope, project.id)

    assert {:error, :not_found} =
             Scenes.get_project_by_slugs(outsider_scope, workspace.slug, project.slug)
  end

  test "hides a soft-deleted project by id and by slugs" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    scope = user_scope_fixture(owner)

    assert {:ok, _deleted_project} = Projects.delete_project(user_scope_fixture(owner), project.id)

    assert {:error, :not_found} = Scenes.get_project(scope, project.id)

    assert {:error, :not_found} =
             Scenes.get_project_by_slugs(scope, workspace.slug, project.slug)
  end

  test "does not resolve a project when valid workspace and project slugs are crossed" do
    first_owner = user_fixture()
    first_workspace = workspace_fixture(first_owner, %{name: "First Scene Workspace"})
    first_project = project_fixture(first_owner, %{workspace: first_workspace, name: "First Scene Project"})

    second_owner = user_fixture()
    second_workspace = workspace_fixture(second_owner, %{name: "Second Scene Workspace"})

    second_project =
      project_fixture(second_owner, %{workspace: second_workspace, name: "Second Scene Project"})

    membership_fixture(second_project, first_owner, "editor")
    scope = user_scope_fixture(first_owner)

    assert {:ok, %ProjectRecord{id: first_project_id}, _membership} =
             Scenes.get_project_by_slugs(scope, first_workspace.slug, first_project.slug)

    assert first_project_id == first_project.id

    assert {:ok, %ProjectRecord{id: second_project_id}, _membership} =
             Scenes.get_project_by_slugs(scope, second_workspace.slug, second_project.slug)

    assert second_project_id == second_project.id

    assert {:error, :not_found} =
             Scenes.get_project_by_slugs(scope, first_workspace.slug, second_project.slug)

    assert {:error, :not_found} =
             Scenes.get_project_by_slugs(scope, second_workspace.slug, first_project.slug)
  end
end

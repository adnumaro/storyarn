defmodule Storyarn.Localization.Access.Queries.ProjectsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.Access.Data.ProjectMembershipRecord
  alias Storyarn.Localization.Access.Data.ProjectRecord
  alias Storyarn.Localization.Access.Data.WorkspaceRecord
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  test "returns context-owned project and membership records with the workspace preloaded" do
    user = user_fixture()
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})
    scope = %{user: %{id: user.id}}

    assert {:ok, %ProjectRecord{} = local_project, %ProjectMembershipRecord{role: "owner"}} =
             Localization.get_project(scope, project.id)

    assert local_project.id == project.id
    assert %WorkspaceRecord{id: workspace_id, source_locale: source_locale} = local_project.workspace
    assert workspace_id == workspace.id
    assert source_locale == workspace.source_locale

    assert {:ok, %ProjectRecord{} = by_slugs, %ProjectMembershipRecord{role: "owner"}} =
             Localization.get_project_by_slugs(scope, workspace.slug, project.slug)

    assert by_slugs.id == project.id
    assert %WorkspaceRecord{id: ^workspace_id} = by_slugs.workspace
  end

  test "derives workspace access locally and preserves direct project membership precedence" do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    collaborator = user_fixture()
    scope = %{user: %{id: collaborator.id}}

    workspace_membership_fixture(workspace, collaborator, "viewer")

    assert {:ok, %ProjectRecord{id: project_id}, %ProjectMembershipRecord{id: nil, role: "viewer"}} =
             Localization.get_project(scope, project.id)

    assert project_id == project.id

    direct = membership_fixture(project, collaborator, "editor")

    assert {:ok, %ProjectRecord{}, %ProjectMembershipRecord{id: membership_id, role: "editor"}} =
             Localization.get_project(scope, project.id)

    assert membership_id == direct.id
  end

  test "hides inaccessible and soft-deleted projects" do
    owner = user_fixture()
    project = project_fixture(owner)
    outsider = user_fixture()

    assert {:error, :not_found} = Localization.get_project(%{user: %{id: outsider.id}}, project.id)
    assert {:error, :not_found} = Localization.get_project(%{user: nil}, project.id)

    project
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    assert {:error, :not_found} = Localization.get_project(%{user: %{id: owner.id}}, project.id)
  end
end

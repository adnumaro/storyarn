defmodule Storyarn.Architecture.OwnershipIntegrityAuditTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Architecture.OwnershipIntegrityAudit
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  test "reports no findings for canonically owned aggregates" do
    user = Storyarn.AccountsFixtures.user_fixture()
    workspace = Storyarn.WorkspacesFixtures.workspace_fixture(user)
    _project = Storyarn.ProjectsFixtures.project_fixture(user, %{workspace: workspace})

    assert {:ok, []} = OwnershipIntegrityAudit.audit()
    assert :ok = OwnershipIntegrityAudit.audit!()
  end

  test "reports missing owner memberships for both aggregate types without repairing them" do
    user = Storyarn.AccountsFixtures.user_fixture()
    workspace = Storyarn.WorkspacesFixtures.workspace_fixture(user)
    project = Storyarn.ProjectsFixtures.project_fixture(user, %{workspace: workspace})

    {1, _rows} =
      ProjectMembership
      |> where([membership], membership.project_id == ^project.id and membership.role == "owner")
      |> Repo.update_all(set: [role: "editor"])

    {1, _rows} =
      WorkspaceMembership
      |> where([membership], membership.workspace_id == ^workspace.id and membership.role == "owner")
      |> Repo.update_all(set: [role: "member"])

    assert {:ok,
            [
              %{
                aggregate: :project,
                aggregate_id: project_id,
                canonical_owner_id: project_owner_id,
                owner_membership_user_ids: []
              },
              %{
                aggregate: :workspace,
                aggregate_id: workspace_id,
                canonical_owner_id: workspace_owner_id,
                owner_membership_user_ids: []
              }
            ] = findings} = OwnershipIntegrityAudit.audit()

    assert project_id == project.id
    assert project_owner_id == user.id
    assert workspace_id == workspace.id
    assert workspace_owner_id == user.id
    refute OwnershipIntegrityAudit.clean?(findings)

    assert_raise RuntimeError, ~r/Ownership integrity preflight failed/, fn ->
      OwnershipIntegrityAudit.audit!()
    end

    assert Repo.get_by(ProjectMembership, project_id: project.id, user_id: user.id).role == "editor"
    assert Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id).role == "member"
  end

  test "reports canonical owner ids that disagree with the single owner membership" do
    owner = Storyarn.AccountsFixtures.user_fixture()
    replacement = Storyarn.AccountsFixtures.user_fixture()
    workspace = Storyarn.WorkspacesFixtures.workspace_fixture(owner)
    project = Storyarn.ProjectsFixtures.project_fixture(owner, %{workspace: workspace})

    workspace
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    project
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    assert {:ok, findings} = OwnershipIntegrityAudit.audit()

    assert [project_finding, workspace_finding] = findings
    assert project_finding.aggregate == :project
    assert project_finding.aggregate_id == project.id
    assert project_finding.canonical_owner_id == replacement.id
    assert project_finding.owner_membership_user_ids == [owner.id]
    assert workspace_finding.aggregate == :workspace
    assert workspace_finding.aggregate_id == workspace.id
    assert workspace_finding.canonical_owner_id == replacement.id
    assert workspace_finding.owner_membership_user_ids == [owner.id]

    assert Repo.get!(Project, project.id).owner_id == replacement.id
    assert Repo.get!(Workspace, workspace.id).owner_id == replacement.id
  end

  test "reports more than one owner membership for either aggregate" do
    owner = Storyarn.AccountsFixtures.user_fixture()
    project_duplicate_owner = Storyarn.AccountsFixtures.user_fixture()
    workspace_duplicate_owner = Storyarn.AccountsFixtures.user_fixture()
    workspace = Storyarn.WorkspacesFixtures.workspace_fixture(owner)
    project = Storyarn.ProjectsFixtures.project_fixture(owner, %{workspace: workspace})

    _project_duplicate_membership =
      Storyarn.ProjectsFixtures.membership_fixture(project, project_duplicate_owner, "owner")

    _workspace_duplicate_membership =
      Storyarn.WorkspacesFixtures.workspace_membership_fixture(
        workspace,
        workspace_duplicate_owner,
        "owner"
      )

    assert {:ok, findings} = OwnershipIntegrityAudit.audit()

    assert [project_finding, workspace_finding] = findings
    assert project_finding.aggregate == :project
    assert project_finding.aggregate_id == project.id
    assert project_finding.canonical_owner_id == owner.id

    assert project_finding.owner_membership_user_ids ==
             Enum.sort([owner.id, project_duplicate_owner.id])

    assert workspace_finding.aggregate == :workspace
    assert workspace_finding.aggregate_id == workspace.id
    assert workspace_finding.canonical_owner_id == owner.id

    assert workspace_finding.owner_membership_user_ids ==
             Enum.sort([owner.id, workspace_duplicate_owner.id])
  end

  test "includes soft-deleted projects because they can be restored" do
    owner = Storyarn.AccountsFixtures.user_fixture()
    project = Storyarn.ProjectsFixtures.project_fixture(owner)

    project
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    {1, _rows} =
      ProjectMembership
      |> where([membership], membership.project_id == ^project.id and membership.role == "owner")
      |> Repo.update_all(set: [role: "editor"])

    assert {:ok,
            [
              %{
                aggregate: :project,
                aggregate_id: project_id,
                canonical_owner_id: owner_id,
                owner_membership_user_ids: []
              }
            ]} = OwnershipIntegrityAudit.audit()

    assert project_id == project.id
    assert owner_id == owner.id
  end

  test "preflight statement is one read-only query" do
    statement = OwnershipIntegrityAudit.statement()

    assert statement |> String.trim_leading() |> String.starts_with?("WITH")
    refute statement =~ ";"
    refute statement =~ ~r/\b(?:INSERT|UPDATE|DELETE|MERGE|TRUNCATE|COPY)\b/i
  end

  test "audit! fails closed when PostgreSQL rejects the audit query" do
    try do
      Repo.query!("SELECT set_config('search_path', $1, true)", ["pg_catalog"])

      assert_raise RuntimeError, ~r/Ownership integrity preflight could not query the database/, fn ->
        OwnershipIntegrityAudit.audit!()
      end
    after
      Repo.query!("SELECT set_config('search_path', $1, true)", ["\"$user\", public"])
    end
  end
end

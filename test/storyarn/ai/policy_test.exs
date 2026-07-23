defmodule Storyarn.AI.PolicyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)

    %{owner: owner, scope: scope, workspace: workspace}
  end

  test "defaults to AI disabled without creating a policy row", %{scope: scope, workspace: workspace} do
    assert {:ok, policy} = AI.get_workspace_policy(scope, workspace.id)
    assert policy.allowed_lanes == []
    assert policy.version == 1
    refute Repo.get_by(WorkspacePolicy, workspace_id: workspace.id)
  end

  test "nil-user scopes are rejected instead of raising", %{workspace: workspace} do
    assert {:error, :unauthorized} = AI.get_workspace_policy(%Scope{}, workspace.id)
    assert {:error, :unauthorized} = AI.update_workspace_policy(%Scope{}, workspace.id, [])
  end

  test "only the workspace owner can change policy and every transition is versioned and audited",
       %{owner: owner, scope: scope, workspace: workspace} do
    assert {:ok, policy} = AI.update_workspace_policy(scope, workspace.id, ["managed", "managed"])
    assert policy.allowed_lanes == ["managed"]
    assert policy.version == 2

    assert %WorkspacePolicyAudit{} = audit = Repo.one!(WorkspacePolicyAudit)
    assert audit.actor_id == owner.id
    assert audit.workspace_id_snapshot == workspace.id
    assert audit.from_lanes == []
    assert audit.to_lanes == ["managed"]
    assert {audit.from_version, audit.to_version} == {1, 2}

    # A no-op does not manufacture a new version or audit event.
    assert {:ok, same_policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])
    assert same_policy.version == 2
    assert Repo.aggregate(WorkspacePolicyAudit, :count) == 1

    admin = user_fixture()
    workspace_membership_fixture(workspace, admin, "admin")
    admin_scope = user_scope_fixture(admin)

    assert {:ok, readable} = AI.get_workspace_policy(admin_scope, workspace.id)
    assert readable.version == 2
    assert {:error, :unauthorized} = AI.update_workspace_policy(admin_scope, workspace.id, [])

    assert {:ok, personal_only} =
             AI.update_workspace_policy(scope, workspace.id, ["personal_byok"])

    assert personal_only.allowed_lanes == ["personal_byok"]
    assert personal_only.version == 3

    assert {:ok, both} =
             AI.update_workspace_policy(scope, workspace.id, ["personal_byok", "managed"])

    assert both.allowed_lanes == ["managed", "personal_byok"]
    assert both.version == 4
    assert Repo.aggregate(WorkspacePolicyAudit, :count) == 3

    assert {:error, :invalid_policy} =
             AI.update_workspace_policy(scope, workspace.id, ["unknown"])
  end

  test "AI permissions have explicit project and workspace matrices" do
    assert Projects.can?("owner", :use_ai)
    assert Projects.can?("editor", :use_ai)
    refute Projects.can?("viewer", :use_ai)
    assert Projects.can?("owner", :run_bulk_ai)
    refute Projects.can?("editor", :run_bulk_ai)

    assert Workspaces.can?("owner", :use_ai)
    assert Workspaces.can?("admin", :use_ai)
    refute Workspaces.can?("member", :use_ai)
    refute Workspaces.can?("viewer", :use_ai)
    assert Workspaces.can?("owner", :run_bulk_ai)
    refute Workspaces.can?("admin", :run_bulk_ai)
  end

  test "workspace policy audit rejects application updates", %{scope: scope, workspace: workspace} do
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.update_all(WorkspacePolicyAudit, set: [to_version: 99])
    end
  end

  test "workspace policy audit rejects application deletes", %{scope: scope, workspace: workspace} do
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])
    audit = Repo.one!(WorkspacePolicyAudit)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.delete(audit)
    end
  end

  test "workspace policy audit links can only be nilified by their foreign keys", %{
    scope: scope,
    workspace: workspace
  } do
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])
    audit = Repo.one!(WorkspacePolicyAudit)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.query!("UPDATE ai_workspace_policy_audits SET user_id = NULL WHERE id = $1", [audit.id])
    end
  end
end

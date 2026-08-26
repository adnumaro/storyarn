defmodule Storyarn.AI.Governance.PolicyTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Task
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)

    %{owner: owner, scope: scope, workspace: workspace}
  end

  test "defaults to AI disabled without creating a policy row", %{scope: scope, workspace: workspace} do
    assert {:ok, policy} = Governance.get_workspace_policy(scope, workspace.id)
    assert policy.allowed_lanes == []
    assert policy.version == 1
    refute Repo.get_by(WorkspacePolicy, workspace_id: workspace.id)
  end

  test "nil-user scopes are rejected instead of raising", %{workspace: workspace} do
    assert {:error, :unauthorized} = Governance.get_workspace_policy(%{user: nil}, workspace.id)
    assert {:error, :unauthorized} = Governance.update_workspace_policy(%{user: nil}, workspace.id, [])
  end

  test "only the workspace owner can change policy and every transition is versioned and audited",
       %{owner: owner, scope: scope, workspace: workspace} do
    assert {:ok, policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed", "managed"])
    assert policy.allowed_lanes == ["managed"]
    assert policy.version == 2

    assert %WorkspacePolicyAudit{} = audit = Repo.one!(WorkspacePolicyAudit)
    assert audit.actor_id == owner.id
    assert audit.workspace_id_snapshot == workspace.id
    assert audit.from_lanes == []
    assert audit.to_lanes == ["managed"]
    assert {audit.from_version, audit.to_version} == {1, 2}

    # A no-op does not manufacture a new version or audit event.
    assert {:ok, same_policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])
    assert same_policy.version == 2
    assert Repo.aggregate(WorkspacePolicyAudit, :count) == 1

    admin = user_fixture()
    workspace_membership_fixture(workspace, admin, "admin")
    admin_scope = user_scope_fixture(admin)

    assert {:ok, readable} = Governance.get_workspace_policy(admin_scope, workspace.id)
    assert readable.version == 2
    assert {:error, :unauthorized} = Governance.update_workspace_policy(admin_scope, workspace.id, [])

    assert {:ok, personal_only} =
             Governance.update_workspace_policy(scope, workspace.id, ["personal_byok"])

    assert personal_only.allowed_lanes == ["personal_byok"]
    assert personal_only.version == 3

    assert {:ok, both} =
             Governance.update_workspace_policy(scope, workspace.id, ["personal_byok", "managed"])

    assert both.allowed_lanes == ["managed", "personal_byok"]
    assert both.version == 4
    assert Repo.aggregate(WorkspacePolicyAudit, :count) == 3

    assert {:error, :invalid_policy} =
             Governance.update_workspace_policy(scope, workspace.id, ["unknown"])
  end

  test "AI permissions have explicit project and workspace matrices" do
    assert Governance.project_can?("owner", :use_ai)
    assert Governance.project_can?("editor", :use_ai)
    refute Governance.project_can?("viewer", :use_ai)
    assert Governance.project_can?("owner", :run_bulk_ai)
    refute Governance.project_can?("editor", :run_bulk_ai)

    assert Governance.workspace_can?("owner", :use_ai)
    assert Governance.workspace_can?("admin", :use_ai)
    refute Governance.workspace_can?("member", :use_ai)
    refute Governance.workspace_can?("viewer", :use_ai)
    assert Governance.workspace_can?("owner", :run_bulk_ai)
    refute Governance.workspace_can?("admin", :run_bulk_ai)
  end

  test "authorization and reauthorization return the stable decision contract", %{
    owner: owner,
    scope: scope,
    workspace: workspace
  } do
    project = project_fixture(owner, %{workspace: workspace})
    FunWithFlags.enable(:ai_integrations, for_actor: owner)

    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: owner) end)

    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])
    assert {:ok, task} = Task.new(ContractTask, ContractTask.definition())

    assert {:ok, intent} =
             ExecutionIntent.new(scope, %{
               workspace_id: workspace.id,
               project_id: project.id,
               task_id: task.id,
               input: %{"text" => "hello"}
             })

    assert {:ok, %PolicyDecision{} = decision} =
             Governance.authorize(intent, task, :execute, lane: :managed)

    assert decision.actor_id == owner.id
    assert decision.allowed_lanes == [:managed]

    persisted = Governance.decision_to_map(decision)

    operation = %Operation{
      user_id: owner.id,
      workspace_id_snapshot: workspace.id,
      project_id_snapshot: project.id,
      task_id: task.id,
      policy_decision: persisted
    }

    assert {:ok, %PolicyDecision{} = rechecked} =
             Governance.reauthorize(operation, task, :execute, lane: :managed)

    assert Governance.decision_to_map(rechecked) == persisted
  end

  test "workspace policy audit rejects application updates", %{scope: scope, workspace: workspace} do
    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.update_all(WorkspacePolicyAudit, set: [to_version: 99])
    end
  end

  test "workspace policy audit rejects application deletes", %{scope: scope, workspace: workspace} do
    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])
    audit = Repo.one!(WorkspacePolicyAudit)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.delete(audit)
    end
  end

  test "workspace policy audit links can only be nilified by their foreign keys", %{
    scope: scope,
    workspace: workspace
  } do
    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])
    audit = Repo.one!(WorkspacePolicyAudit)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      Repo.query!("UPDATE ai_workspace_policy_audits SET user_id = NULL WHERE id = $1", [audit.id])
    end
  end
end

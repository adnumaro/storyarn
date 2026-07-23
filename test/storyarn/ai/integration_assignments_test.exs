defmodule Storyarn.AI.IntegrationAssignmentsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.AuditEntry
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.Repo

  @stub StoryarnTest.AI.OpenAI

  setup do
    owner = user_fixture()
    owner_scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    member = user_fixture()
    member_scope = user_scope_fixture(member)
    workspace_membership_fixture(workspace, member, "member")

    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    FunWithFlags.enable(:ai_integrations, for_actor: member)

    %{
      owner: owner,
      owner_scope: owner_scope,
      workspace: workspace,
      member: member,
      member_scope: member_scope
    }
  end

  test "owner assignment is actor-scoped, idempotent and audited", ctx do
    integration = connect_openai!(ctx.owner)

    assert {:ok, assignment} =
             AI.assign_integration(ctx.owner_scope, integration.id, ctx.workspace.id)

    assert assignment.user_id == ctx.owner.id
    assert assignment.workspace_id == ctx.workspace.id
    assert assignment.integration_id == integration.id
    assert assignment.provider == "openai"

    assert {:ok, same_assignment} =
             AI.assign_integration(ctx.owner_scope, integration.id, ctx.workspace.id)

    assert same_assignment.id == assignment.id

    audits = Repo.all(AuditEntry)
    assert Enum.count(audits, &(&1.action == "workspace_assigned")) == 1

    assigned_audit = Enum.find(audits, &(&1.action == "workspace_assigned"))

    assert assigned_audit.actor_id == ctx.owner.id
    assert assigned_audit.metadata["integration_id"] == integration.id
    assert assigned_audit.metadata["workspace_id"] == ctx.workspace.id
    assert assigned_audit.metadata["assignment_id"] == assignment.id
  end

  test "concurrent assignment attempts converge on one active row", ctx do
    integration = connect_openai!(ctx.owner)

    results =
      1..2
      |> Enum.map(fn _index ->
        Task.async(fn ->
          AI.assign_integration(
            ctx.owner_scope,
            integration.id,
            ctx.workspace.id
          )
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.all?(results, &match?({:ok, %IntegrationWorkspaceAssignment{}}, &1))

    assignment_ids = Enum.map(results, fn {:ok, assignment} -> assignment.id end)
    assert assignment_ids |> Enum.uniq() |> length() == 1

    assert Repo.aggregate(
             from(assignment in IntegrationWorkspaceAssignment,
               where:
                 assignment.integration_id == ^integration.id and
                   assignment.workspace_id == ^ctx.workspace.id and
                   is_nil(assignment.revoked_at)
             ),
             :count
           ) == 1
  end

  test "a member needs the workspace policy but always assigns their own key", ctx do
    member_integration = connect_openai!(ctx.member, "sk-proj-member-wxyz")

    assert {:error, :member_personal_ai_disabled} =
             AI.assign_integration(
               ctx.member_scope,
               member_integration.id,
               ctx.workspace.id
             )

    assert {:ok, _policy} =
             AI.update_workspace_policy(
               ctx.owner_scope,
               ctx.workspace.id,
               ["personal_byok"]
             )

    assert {:ok, assignment} =
             AI.assign_integration(
               ctx.member_scope,
               member_integration.id,
               ctx.workspace.id
             )

    assert assignment.user_id == ctx.member.id
    assert assignment.integration_id == member_integration.id
  end

  test "cannot assign another actor's integration or an inaccessible workspace", ctx do
    owner_integration = connect_openai!(ctx.owner)

    assert {:ok, _policy} =
             AI.update_workspace_policy(
               ctx.owner_scope,
               ctx.workspace.id,
               ["personal_byok"]
             )

    assert {:error, :integration_unavailable} =
             AI.assign_integration(
               ctx.member_scope,
               owner_integration.id,
               ctx.workspace.id
             )

    outsider = user_fixture()
    outsider_workspace = workspace_fixture(outsider)

    assert {:error, :workspace_unavailable} =
             AI.assign_integration(
               ctx.owner_scope,
               owner_integration.id,
               outsider_workspace.id
             )

    assert Repo.aggregate(IntegrationWorkspaceAssignment, :count) == 0
  end

  test "list states never exposes inaccessible workspaces or another actor's assignment", ctx do
    owner_integration = connect_openai!(ctx.owner)
    member_integration = connect_openai!(ctx.member, "sk-proj-member-wxyz")

    assert {:ok, _owner_assignment} =
             AI.assign_integration(
               ctx.owner_scope,
               owner_integration.id,
               ctx.workspace.id
             )

    owner_states = AI.list_assignment_states(ctx.owner_scope, owner_integration)
    assert Enum.any?(owner_states, &(&1.workspace_id == ctx.workspace.id and &1.assigned))

    member_states = AI.list_assignment_states(ctx.member_scope, member_integration)
    shared_state = Enum.find(member_states, &(&1.workspace_id == ctx.workspace.id))

    refute shared_state.assigned
    assert shared_state.state == "blocked"
    assert shared_state.reason == "member_policy_disabled"

    outsider = user_fixture()
    outsider_workspace = workspace_fixture(outsider)
    refute Enum.any?(owner_states, &(&1.workspace_id == outsider_workspace.id))
  end

  test "unassign is actor-scoped and produces a new identity when re-enabled", ctx do
    integration = connect_openai!(ctx.owner)

    assert {:ok, assignment} =
             AI.assign_integration(ctx.owner_scope, integration.id, ctx.workspace.id)

    assert {:error, :assignment_not_found} =
             AI.unassign_integration(ctx.member_scope, integration.id, ctx.workspace.id)

    assert {:ok, revoked} =
             AI.unassign_integration(ctx.owner_scope, integration.id, ctx.workspace.id)

    assert revoked.id == assignment.id
    assert revoked.revoked_at

    assert {:ok, replacement} =
             AI.assign_integration(ctx.owner_scope, integration.id, ctx.workspace.id)

    refute replacement.id == assignment.id
    assert is_nil(replacement.revoked_at)
  end

  test "database guard rejects an assignment whose owner does not match the integration", ctx do
    integration = connect_openai!(ctx.owner)

    assert_raise Postgrex.Error, ~r/identity does not match/, fn ->
      Repo.transaction(fn ->
        %IntegrationWorkspaceAssignment{
          user_id: ctx.member.id,
          workspace_id: ctx.workspace.id,
          integration_id: integration.id,
          provider: integration.provider
        }
        |> IntegrationWorkspaceAssignment.assign_changeset(Storyarn.Shared.TimeHelpers.now())
        |> Repo.insert!(mode: :savepoint)
      end)
    end
  end

  defp connect_openai!(user, api_key \\ "sk-proj-owner-abcd") do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"data" => [%{"id" => "personal-deterministic-v1"}]})
    end)

    assert {:ok, integration} = AI.connect(user, :openai, api_key)
    integration
  end
end

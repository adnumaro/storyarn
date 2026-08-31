defmodule Storyarn.AI.Governance.BulkOwnerAuthorizationTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.AI.Tasks.ManagedDiagnostic
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceMembership
  alias StoryarnTest.AI.ContractTask

  setup do
    original_task_config = Application.get_env(:storyarn, ContractTask, [])
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)

    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_task_config)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace}
  end

  test "project bulk rejects a missing owner membership", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})

    project
    |> project_owner_membership(context.owner)
    |> Ecto.Changeset.change(role: "editor")
    |> Repo.update!()

    assert_bulk_owner_rejected(project_intent(context, project), task(:project))
  end

  test "project bulk accepts the canonical owner with and without policy locks", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})

    assert_authorized(project_intent(context, project), task(:project))
  end

  test "project bulk rejects an owner membership that does not match owner_id", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})
    replacement = user_fixture()

    project
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    assert_bulk_owner_rejected(project_intent(context, project), task(:project))
  end

  test "project bulk rejects duplicate owner memberships", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})
    duplicate_owner = user_fixture()
    _duplicate_membership = membership_fixture(project, duplicate_owner, "owner")

    assert_bulk_owner_rejected(project_intent(context, project), task(:project))
  end

  test "project bulk requires the canonical project owner even for the workspace owner", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})
    canonical_project_owner = user_fixture()
    actor_membership = project_owner_membership(project, context.owner)

    actor_membership
    |> Ecto.Changeset.change(role: "editor")
    |> Repo.update!()

    _canonical_membership = membership_fixture(project, canonical_project_owner, "owner")

    project
    |> Ecto.Changeset.change(owner_id: canonical_project_owner.id)
    |> Repo.update!()

    assert_bulk_permission_rejected(project_intent(context, project), task(:project))

    Repo.delete!(actor_membership)

    assert_bulk_permission_rejected(project_intent(context, project), task(:project))
  end

  test "workspace bulk rejects a missing owner membership", context do
    context.workspace
    |> workspace_owner_membership(context.owner)
    |> Ecto.Changeset.change(role: "admin")
    |> Repo.update!()

    assert_bulk_owner_rejected(workspace_intent(context), task(:workspace))
  end

  test "workspace bulk accepts the canonical owner with and without policy locks", context do
    assert_authorized(workspace_intent(context), task(:workspace))
  end

  test "workspace bulk rejects an owner membership that does not match owner_id", context do
    replacement = user_fixture()

    context.workspace
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    assert_bulk_owner_rejected(workspace_intent(context), task(:workspace))
  end

  test "workspace bulk rejects duplicate owner memberships", context do
    duplicate_owner = user_fixture()
    _duplicate_membership = workspace_membership_fixture(context.workspace, duplicate_owner, "owner")

    assert_bulk_owner_rejected(workspace_intent(context), task(:workspace))
  end

  test "non-bulk managed diagnostic rejects a workspace owner membership that does not match owner_id", context do
    replacement = user_fixture()

    context.workspace
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    assert_owner_only_rejected(
      workspace_intent(context, false, "operator.managed_diagnostic"),
      managed_diagnostic_task()
    )
  end

  test "non-bulk managed diagnostic rejects duplicate workspace owner memberships", context do
    duplicate_owner = user_fixture()
    _duplicate_membership = workspace_membership_fixture(context.workspace, duplicate_owner, "owner")

    assert_owner_only_rejected(
      workspace_intent(context, false, "operator.managed_diagnostic"),
      managed_diagnostic_task()
    )
  end

  test "non-bulk project owner-only task rejects an owner membership that does not match owner_id", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})
    replacement = user_fixture()

    project
    |> Ecto.Changeset.change(owner_id: replacement.id)
    |> Repo.update!()

    assert_owner_only_rejected(
      project_intent(context, project, false),
      task(:project, %{execute: :manage_project})
    )
  end

  test "non-bulk project owner-only task rejects duplicate owner memberships", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})
    duplicate_owner = user_fixture()
    _duplicate_membership = membership_fixture(project, duplicate_owner, "owner")

    assert_owner_only_rejected(
      project_intent(context, project, false),
      task(:project, %{execute: :manage_project})
    )
  end

  test "non-bulk project authorization keeps accepting the existing editor policy", context do
    project = project_fixture(context.owner, %{workspace: context.workspace})

    project
    |> project_owner_membership(context.owner)
    |> Ecto.Changeset.change(role: "editor")
    |> Repo.update!()

    assert_authorized(project_intent(context, project, false), task(:project))
  end

  test "non-bulk workspace authorization keeps accepting the existing admin policy", context do
    context.workspace
    |> workspace_owner_membership(context.owner)
    |> Ecto.Changeset.change(role: "admin")
    |> Repo.update!()

    assert_authorized(workspace_intent(context, false), task(:workspace))
  end

  defp task(data_scope, required_domain_permissions \\ %{execute: :view, apply: :edit_content}) do
    Application.put_env(:storyarn, ContractTask,
      data_scope: data_scope,
      bulk_allowed?: true
    )

    definition = Map.put(ContractTask.definition(), :required_domain_permissions, required_domain_permissions)

    assert {:ok, task} = AITask.new(ContractTask, definition)
    task
  end

  defp managed_diagnostic_task do
    definition = Map.put(ManagedDiagnostic.definition(), :enabled?, true)

    assert {:ok, task} = AITask.new(ManagedDiagnostic, definition)
    task
  end

  defp project_intent(context, project, bulk? \\ true) do
    assert {:ok, intent} =
             ExecutionIntent.new(context.scope, %{
               workspace_id: context.workspace.id,
               project_id: project.id,
               task_id: "contract.echo",
               input: %{"text" => "bulk owner invariant"},
               bulk?: bulk?
             })

    intent
  end

  defp workspace_intent(context, bulk? \\ true, task_id \\ "contract.echo") do
    assert {:ok, intent} =
             ExecutionIntent.new(context.scope, %{
               workspace_id: context.workspace.id,
               project_id: nil,
               task_id: task_id,
               input: %{"text" => "bulk owner invariant"},
               bulk?: bulk?
             })

    intent
  end

  defp assert_bulk_owner_rejected(intent, task) do
    assert {:error, :ownership_invariant_violation} =
             Governance.authorize(intent, task, :execute, lane: :managed)

    assert {:error, :ownership_invariant_violation} =
             Repo.transact(fn ->
               Governance.authorize(intent, task, :execute,
                 lane: :managed,
                 lock_policy: true
               )
             end)
  end

  defp assert_owner_only_rejected(intent, task) do
    assert {:error, :ownership_invariant_violation} =
             Governance.authorize(intent, task, :execute, lane: :managed)

    assert {:error, :ownership_invariant_violation} =
             Repo.transact(fn ->
               Governance.authorize(intent, task, :execute,
                 lane: :managed,
                 lock_policy: true
               )
             end)
  end

  defp assert_authorized(intent, task) do
    assert {:ok, %PolicyDecision{}} =
             Governance.authorize(intent, task, :execute, lane: :managed)

    assert {:ok, %PolicyDecision{}} =
             Repo.transact(fn ->
               Governance.authorize(intent, task, :execute,
                 lane: :managed,
                 lock_policy: true
               )
             end)
  end

  defp assert_bulk_permission_rejected(intent, task) do
    assert {:error, :missing_run_bulk_ai} =
             Governance.authorize(intent, task, :execute, lane: :managed)

    assert {:error, :missing_run_bulk_ai} =
             Repo.transact(fn ->
               Governance.authorize(intent, task, :execute,
                 lane: :managed,
                 lock_policy: true
               )
             end)
  end

  defp project_owner_membership(project, owner) do
    Repo.get_by!(ProjectMembership, project_id: project.id, user_id: owner.id)
  end

  defp workspace_owner_membership(workspace, owner) do
    Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: owner.id)
  end
end

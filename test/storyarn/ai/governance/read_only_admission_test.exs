defmodule Storyarn.AI.Governance.ReadOnlyAdmissionTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.CommercialFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.Task, as: AITask
  alias StoryarnTest.AI.ContractTask

  setup do
    original_task_config = Application.get_env(:storyarn, ContractTask, [])
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    assert {:ok, _policy} = Governance.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_task_config)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace, project: project}
  end

  test "a read-only workspace admits no new AI work", context do
    intent = intent(context)
    task = task()
    assert {:ok, _decision} = Governance.authorize(intent, task, :execute, lane: :managed)

    extra = lock_account!(context.owner)

    assert {:error, :read_only} = Governance.authorize(intent, task, :execute, lane: :managed)
    assert {:error, :read_only} = Governance.authorize(intent, task, :apply, lane: :managed)

    unlock_account!(extra)

    assert {:ok, _decision} = Governance.authorize(intent, task, :execute, lane: :managed)
  end

  test "work admitted before the lock keeps its authorization", context do
    intent = intent(context)
    task = task()
    lock_account!(context.owner)

    assert {:ok, _decision} = Governance.authorize(intent, task, :apply, lane: :managed, admitted: true)
  end

  defp task do
    Application.put_env(:storyarn, ContractTask, data_scope: :project, bulk_allowed?: false)

    definition =
      Map.put(ContractTask.definition(), :required_domain_permissions, %{execute: :view, apply: :edit_content})

    assert {:ok, task} = AITask.new(ContractTask, definition)
    task
  end

  defp intent(context) do
    assert {:ok, intent} =
             ExecutionIntent.new(context.scope, %{
               workspace_id: context.workspace.id,
               project_id: context.project.id,
               task_id: "contract.echo",
               input: %{"text" => "read-only admission"},
               bulk?: false
             })

    intent
  end
end

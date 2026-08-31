defmodule Storyarn.AI.Governance.OperationReauthorizationVolatileTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.Repo
  alias StoryarnTest.AI.ContractTask
  alias StoryarnTest.AI.UnsafeContextTask
  alias StoryarnTest.AI.VolatileSubjectTask

  setup do
    original_runtime = Application.get_env(:storyarn, VolatileSubjectTask, [])
    Application.put_env(:storyarn, VolatileSubjectTask, [])

    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: owner)

    %WorkspacePolicy{workspace_id: workspace.id}
    |> WorkspacePolicy.changeset(%{
      allowed_lanes: ["managed"],
      version: 1,
      updated_by_id: owner.id
    })
    |> Repo.insert!()

    on_exit(fn ->
      Application.put_env(:storyarn, VolatileSubjectTask, original_runtime)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace, project: project}
  end

  test "completion rechecks a feature flag changed after preliminary authorization", ctx do
    assert {:ok, task} = AITask.new(ContractTask, ContractTask.definition())
    operation = operation(ctx, task)

    assert {:ok, :verified} =
             Repo.transact(fn ->
               token = preauthorize(operation, task, :execute, lane: :managed)

               assert {:ok, _decision} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :execute,
                          token,
                          lane: :managed
                        )

               FunWithFlags.disable(:ai_integrations, for_actor: ctx.owner)

               assert {:error, :feature_disabled} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :execute,
                          token,
                          lane: :managed
                        )

               {:ok, :verified}
             end)
  end

  test "contextual tasks fail closed without an explicit lock-free callback contract" do
    assert {:error, errors} = AITask.new(UnsafeContextTask, UnsafeContextTask.definition())
    assert :unsafe_post_operation_authorization in errors
  end

  test "completion rechecks lock-free consumer subject authorization", ctx do
    assert {:ok, task} = AITask.new(VolatileSubjectTask, VolatileSubjectTask.definition())
    operation = operation(ctx, task, %{type: "sheet", id: 41, revision: "sheet-v1"})

    assert {:ok, :verified} =
             Repo.transact(fn ->
               token = preauthorize(operation, task, :execute, lane: :managed)

               Application.put_env(:storyarn, VolatileSubjectTask, authorize_subject: {:error, :subject_access_revoked})

               assert {:error, :subject_access_revoked} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :execute,
                          token,
                          lane: :managed
                        )

               {:ok, :verified}
             end)
  end

  test "completion rechecks lock-free consumer subject currentness", ctx do
    assert {:ok, task} = AITask.new(VolatileSubjectTask, VolatileSubjectTask.definition())
    operation = operation(ctx, task, %{type: "sheet", id: 42, revision: "sheet-v1"})

    assert {:ok, :verified} =
             Repo.transact(fn ->
               token = preauthorize(operation, task, :execute, lane: :managed)
               Application.put_env(:storyarn, VolatileSubjectTask, subject_current?: false)

               assert {:error, :policy_or_subject_changed} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :execute,
                          token,
                          lane: :managed
                        )

               {:ok, :verified}
             end)
  end

  test "completion fails closed when phase or lane does not match its opaque token", ctx do
    assert {:ok, task} = AITask.new(ContractTask, ContractTask.definition())
    operation = operation(ctx, task)

    assert {:ok, :verified} =
             Repo.transact(fn ->
               token = preauthorize(operation, task, :execute, lane: :managed)

               assert {:error, :operation_authorization_changed} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :apply,
                          token,
                          lane: :managed
                        )

               assert {:error, :operation_authorization_changed} =
                        Governance.complete_operation_reauthorization(
                          operation,
                          task,
                          :execute,
                          token
                        )

               {:ok, :verified}
             end)
  end

  test "technical completion permits expected FK nilification but pins durable identity", ctx do
    assert {:ok, task} = AITask.new(ContractTask, ContractTask.definition())
    operation = operation(ctx, task)

    assert {:ok, :verified} =
             Repo.transact(fn ->
               preparation = Governance.prepare_operation_reauthorization(operation)

               nilified = %{
                 operation
                 | user_id: nil,
                   workspace_id: nil,
                   project_id: nil,
                   route_option_id: nil
               }

               assert :ok =
                        Governance.complete_operation_lock_preparation(
                          nilified,
                          preparation
                        )

               changed = %{nilified | task_id: "different.task"}

               assert {:error, :operation_authorization_changed} =
                        Governance.complete_operation_lock_preparation(
                          changed,
                          preparation
                        )

               {:ok, :verified}
             end)
  end

  defp preauthorize(operation, task, phase, opts) do
    preparation = Governance.prepare_operation_reauthorization(operation)

    Governance.preauthorize_operation(
      operation,
      task,
      phase,
      Keyword.put(opts, :preparation, preparation)
    )
  end

  defp operation(ctx, task, subject \\ nil) do
    assert {:ok, intent} =
             ExecutionIntent.new(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: task.id,
               input: %{},
               subject: subject
             })

    assert {:ok, decision} = Governance.authorize(intent, task, :execute, lane: :managed)

    %Operation{
      id: System.unique_integer([:positive]),
      user_id: ctx.owner.id,
      actor_id: ctx.owner.id,
      workspace_id: ctx.workspace.id,
      workspace_id_snapshot: ctx.workspace.id,
      project_id: ctx.project.id,
      project_id_snapshot: ctx.project.id,
      route_option_id: System.unique_integer([:positive]),
      task_id: task.id,
      task_contract_hash: AITask.contract_hash(task),
      subject_type: subject && subject.type,
      subject_id: subject && subject.id,
      subject_revision: subject && subject.revision,
      policy_decision: Governance.decision_to_map(decision),
      execution_route: %{"lane" => "managed"}
    }
  end
end

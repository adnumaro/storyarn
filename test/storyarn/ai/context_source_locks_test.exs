defmodule Storyarn.AI.Context.SourceLocksTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.SourceLocks
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task
  alias Storyarn.Flows.FlowNode
  alias StoryarnTest.AI.ContextTask

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user)
    flow = flow_fixture(project)
    first_node = node_fixture(flow, %{data: %{"text" => "First"}})
    second_node = node_fixture(flow, %{data: %{"text" => "Second"}})
    connection = connection_fixture(flow, first_node, second_node)
    sheet = sheet_fixture(project)
    block = block_fixture(sheet, %{value: %{"content" => "Evidence"}})

    evidence = [
      %{"type" => "flow", "id" => flow.id},
      %{"type" => "flow_node", "id" => first_node.id},
      %{"type" => "flow_connection", "id" => connection.id},
      %{"type" => "sheet", "id" => sheet.id},
      %{"type" => "sheet_block", "id" => block.id}
    ]

    {:ok, subject_ref} =
      SubjectRef.structural_finding(
        project.workspace_id,
        project.id,
        "finding-1",
        %{"severity" => "warning"},
        evidence
      )

    {:ok, task} =
      Task.new(
        ContextTask,
        Map.put(ContextTask.definition(), :context_policy, %{
          scope: :structural_finding,
          max_depth: 0,
          max_fan_out: 10,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{}
        })
      )

    {:ok, package} = Context.build_context(scope, task, subject_ref)

    operation = %Operation{
      project_id_snapshot: project.id,
      context_hash: package.hash,
      context_manifest: Package.provenance(package),
      context_subject: nil
    }

    %{
      operation: operation,
      first_node: first_node
    }
  end

  test "locks every supported structural evidence type", %{operation: operation} do
    assert {:ok, :ok} = Repo.transaction(fn -> SourceLocks.acquire(operation) end)
  end

  test "rejects structural evidence changed before the lock", %{
    operation: operation,
    first_node: first_node
  } do
    first_node
    |> FlowNode.update_changeset(%{data: %{"text" => "Changed"}})
    |> Repo.update!()

    assert {:ok, {:error, :stale_context}} =
             Repo.transaction(fn -> SourceLocks.acquire(operation) end)
  end

  test "fails closed for a manifest larger than the context hard limit", %{
    operation: operation
  } do
    included = operation.context_manifest["included"]

    oversized =
      put_in(
        operation.context_manifest["included"],
        List.duplicate(hd(included), 501)
      )

    assert {:ok, {:error, :stale_context}} =
             Repo.transaction(fn ->
               SourceLocks.acquire(%{operation | context_manifest: oversized})
             end)
  end
end

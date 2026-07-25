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
  alias StoryarnTest.AI.ContextTask

  # These locks used to be exercised through the structural-finding scope, which
  # Slice 7.1a.0 removed. They are generic kernel machinery, so the coverage moved
  # to the scopes that remain: `dialogue` reaches flow, flow_node, sheet and
  # sheet_block, and `flow_neighborhood` reaches flow_connection.
  #
  # There is deliberately NO content-staleness test here any more. The evidence
  # re-verification `SourceLocks` performed ran only for the non-persistable
  # structural scope, precisely because that scope could not be rebuilt from a
  # persisted subject. Every surviving scope is checked more strongly one layer up,
  # where `Context.operation_current?/3` rebuilds the package and compares hashes —
  # covered in `context_test.exs`. Asserting staleness here would only prove the
  # test was aspirational; it did, before this comment existed.

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user)

    speaker = sheet_fixture(project, %{name: "Ariadna"})
    _summary = block_fixture(speaker, %{config: %{"label" => "Summary"}, value: %{"content" => "Cartógrafa"}})

    flow = flow_fixture(project)

    dialogue_node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => speaker.id, "text" => "First"}
      })

    second_node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Second"}})
    _connection = connection_fixture(flow, dialogue_node, second_node)

    %{
      scope: scope,
      project: project,
      dialogue_node: dialogue_node,
      second_node: second_node
    }
  end

  defp operation_for(scope, project, policy_scope, subject_ref) do
    {:ok, task} =
      Task.new(
        ContextTask,
        Map.put(ContextTask.definition(), :context_policy, %{
          scope: policy_scope,
          max_depth: if(policy_scope == :flow_neighborhood, do: 1, else: 0),
          max_fan_out: 10,
          max_entities: 10,
          max_bytes: 16_384,
          tokenizer: nil,
          fields: %{speaker_blocks: ["Summary"]}
        })
      )

    {:ok, package} = Context.build_context(scope, task, subject_ref)

    %Operation{
      project_id_snapshot: project.id,
      context_hash: package.hash,
      context_manifest: Package.provenance(package),
      context_subject: nil
    }
  end

  defp dialogue_operation(%{scope: scope, project: project, dialogue_node: node}) do
    {:ok, ref} = SubjectRef.dialogue(project.workspace_id, project.id, node.id)
    operation_for(scope, project, :dialogue, ref)
  end

  defp neighborhood_operation(%{scope: scope, project: project, dialogue_node: node}) do
    {:ok, ref} = SubjectRef.flow_neighborhood(project.workspace_id, project.id, node.id)
    operation_for(scope, project, :flow_neighborhood, ref)
  end

  test "locks the evidence a dialogue package includes", context do
    operation = dialogue_operation(context)

    # Guard: the assertion below is only meaningful if the manifest actually
    # carries persisted evidence for the locker to take.
    assert operation.context_manifest["included"] != []

    assert {:ok, :ok} = Repo.transaction(fn -> SourceLocks.acquire(operation) end)
  end

  test "locks the connection evidence a neighborhood package includes", context do
    operation = neighborhood_operation(context)

    assert Enum.any?(operation.context_manifest["included"], &(&1["type"] == "flow_connection")),
           "expected a flow_connection entry, or this test locks nothing new"

    assert {:ok, :ok} = Repo.transaction(fn -> SourceLocks.acquire(operation) end)
  end

  test "fails closed for a manifest larger than the context hard limit", context do
    operation = dialogue_operation(context)
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

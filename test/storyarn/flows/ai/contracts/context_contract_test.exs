defmodule Storyarn.Flows.AI.ContextContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.Routing.Rules.ModelLimits
  alias Storyarn.AI.Task
  alias Storyarn.Flows.AI.ContextContract
  alias StoryarnTest.Flows.AI.ContextTask

  test "owns its scopes and field groups without accepting another consumer's vocabulary" do
    assert {:ok, _policy} = Policy.new(policy(:dialogue, %{speaker_blocks: ["Summary"]}), ContextContract)
    assert {:ok, _policy} = Policy.new(policy(:flow_neighborhood), ContextContract)

    assert {:error, :invalid_context_policy} =
             Policy.new(policy(:sheet), ContextContract)

    assert {:error, :invalid_context_policy} =
             Policy.new(policy(:dialogue, %{sheet_blocks: ["value"]}), ContextContract)

    assert {:error, :invalid_context_policy} =
             Policy.new(policy(:undeclared_flow_scope), ContextContract)
  end

  test "owns subject kinds and selector rules" do
    assert {:ok, dialogue} = ContextContract.dialogue(1, 2, 3, response_id: "response-a")
    assert {:ok, persisted} = SubjectRef.persisted_map(dialogue)
    assert {:ok, ^dialogue} = ContextContract.from_persisted_subject(persisted)

    assert {:error, :invalid_context_subject} =
             SubjectRef.new(ContextContract, :undeclared_flow_kind, 1, 2, 3)

    assert {:error, :invalid_context_subject} =
             SubjectRef.new(ContextContract, :dialogue, 1, 2, 3, %{response_id: nil, block_ids: [4]})

    assert {:error, :invalid_context_subject} =
             ContextContract.from_persisted_subject(%{persisted | "block_ids" => [4]})

    assert {:ok, dialogue_policy} = Policy.new(policy(:dialogue), ContextContract)
    assert {:ok, neighborhood_policy} = Policy.new(policy(:flow_neighborhood), ContextContract)
    assert ContextContract.subject_matches_policy?(dialogue, dialogue_policy)
    refute ContextContract.subject_matches_policy?(dialogue, neighborhood_policy)
  end

  test "rejects evidence types not declared by Flows before provider execution" do
    task = flow_task()

    assert ModelLimits.contextual_input?(context_input("flow_node"), task)
    refute ModelLimits.contextual_input?(context_input("undeclared_flow_source"), task)
  end

  test "a contextual task fails closed for a scope its consumer contract does not declare" do
    attrs = Map.put(ContextTask.definition(), :context_policy, policy(:dialogue))
    assert {:ok, %Task{context_contract: ContextContract}} = Task.new(ContextTask, attrs)

    undeclared = Map.put(ContextTask.definition(), :context_policy, policy(:undeclared_flow_scope))
    assert {:error, errors} = Task.new(ContextTask, undeclared)
    assert :invalid_context_policy in errors
  end

  defp flow_task do
    attrs = Map.put(ContextTask.definition(), :context_policy, policy(:flow_neighborhood))
    {:ok, task} = Task.new(ContextTask, attrs)
    task
  end

  defp context_input(type) do
    %{
      "request" => %{"text" => "bounded"},
      "context" => %{
        "version" => "storyarn-context-v1",
        "scope" => "flow_neighborhood",
        "entities" => [%{"type" => type, "id" => 3, "content" => %{}}]
      }
    }
  end

  defp policy(scope, fields \\ %{}) do
    %{
      scope: scope,
      max_depth: 1,
      max_fan_out: 10,
      max_entities: 20,
      max_bytes: 16_384,
      tokenizer: nil,
      fields: fields
    }
  end
end

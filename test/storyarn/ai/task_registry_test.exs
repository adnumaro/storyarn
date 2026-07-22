defmodule Storyarn.AI.TaskRegistryTest do
  use ExUnit.Case, async: false

  alias Storyarn.AI.CanonicalJSON
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Telemetry
  alias StoryarnTest.AI.ContractTask

  test "loads only registered validated tasks and derives palette ids" do
    assert {:ok, task} = TaskRegistry.fetch("contract.echo")
    assert task.module == ContractTask
    assert task.allowed_lanes == [:managed]
    assert task.required_domain_permissions == %{execute: :view, apply: :edit_content}
    assert TaskRegistry.command_id?("ai.contract.echo")
    refute TaskRegistry.command_id?("ai.forged.command")
    assert {:error, :unknown_task} = TaskRegistry.fetch("missing.task")
  end

  test "rejects an incomplete or caller-shaped task definition" do
    attrs = ContractTask.definition()

    assert {:error, errors} = Task.new(ContractTask, %{attrs | allowed_lanes: []})
    assert :invalid_lanes in errors

    assert {:error, errors} =
             Task.new(ContractTask, %{
               attrs
               | result_destination: %{type: :route, id: "safe", url: "https://attacker.invalid"}
             })

    assert :invalid_result_destination in errors
  end

  test "canonical structured hashing ignores map insertion order and rejects structs" do
    first = Map.new([{"b", 2}, {"a", [%{"z" => true, "x" => nil}]}])
    second = Map.new([{"a", [%{"x" => nil, "z" => true}]}, {"b", 2}])

    assert {:ok, hash} = CanonicalJSON.hash(first)
    assert {:ok, ^hash} = CanonicalJSON.hash(second)
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode(%{"scope" => %Storyarn.Accounts.Scope{}})
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode(%{:same => 1, "same" => 2})
  end

  test "AI telemetry drops content and credential-shaped metadata" do
    handler_id = "ai-contract-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:ai, :contract],
        fn event, measurements, metadata, test_pid ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Telemetry.emit([:contract], %{count: 1}, %{
      task_id: "contract.echo",
      status: "succeeded",
      input: "private story content",
      credential: "secret-key"
    })

    assert_receive {:telemetry, [:ai, :contract], %{count: 1}, metadata}
    assert metadata == %{task_id: "contract.echo", status: "succeeded"}
  end
end

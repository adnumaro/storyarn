defmodule Storyarn.AI.TaskRegistryTest do
  use ExUnit.Case, async: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.AI.Telemetry
  alias Storyarn.Shared.CanonicalJSON
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

    assert {:error, errors} = Task.new(ContractTask, %{attrs | allowed_lanes: :managed})
    assert :invalid_lanes in errors

    assert {:error, errors} = Task.new(ContractTask, %{attrs | enabled?: fn _context -> true end})
    assert :invalid_enabled in errors

    assert {:error, errors} =
             Task.new(ContractTask, %{
               attrs
               | allowed_lanes: [:personal_byok],
                 managed_price: nil,
                 personal_byok_allowed?: true,
                 personal_cost_class: <<255>>
             })

    assert :invalid_personal_cost_class in errors

    assert {:error, errors} =
             Task.new(ContractTask, %{
               attrs
               | data_scope: :workspace,
                 context_policy: %{
                   scope: :sheet,
                   max_depth: 0,
                   max_fan_out: 1,
                   max_entities: 10,
                   max_bytes: 4_096,
                   tokenizer: nil,
                   fields: %{}
                 }
             })

    assert :invalid_context_data_scope in errors
  end

  test "canonical structured hashing ignores map insertion order and rejects structs" do
    first = Map.new([{"b", 2}, {"a", [%{"z" => true, "x" => nil}]}])
    second = Map.new([{"a", [%{"x" => nil, "z" => true}]}, {"b", 2}])

    assert {:ok, hash} = CanonicalJSON.hash(first)
    assert {:ok, ^hash} = CanonicalJSON.hash(second)
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode(%{"scope" => %Scope{}})
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode(%{:same => 1, "same" => 2})
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode([1 | 2])
    assert {:error, :invalid_structured_input} = CanonicalJSON.encode(<<255>>)
  end

  test "execution intent rejects identifiers outside PostgreSQL bigint" do
    scope = %Scope{user: %User{id: 1}}
    too_large = 9_223_372_036_854_775_808

    assert {:error, :invalid_workspace} =
             ExecutionIntent.new(scope, %{workspace_id: too_large, task_id: "contract.echo", input: %{}})

    assert {:error, :invalid_project} =
             ExecutionIntent.new(scope, %{
               workspace_id: 1,
               project_id: too_large,
               task_id: "contract.echo",
               input: %{}
             })

    assert {:error, :invalid_subject} =
             ExecutionIntent.new(scope, %{
               workspace_id: 1,
               project_id: 1,
               task_id: "contract.echo",
               input: %{},
               subject: %{type: "sheet", id: too_large, revision: "v1"}
             })
  end

  test "task contract hash changes with runtime execution configuration" do
    original = Application.get_env(:storyarn, ContractTask, [])
    on_exit(fn -> Application.put_env(:storyarn, ContractTask, original) end)

    Application.put_env(:storyarn, ContractTask, scenario: :success)
    assert {:ok, first} = TaskRegistry.fetch("contract.echo")

    Application.put_env(:storyarn, ContractTask, scenario: :failure)
    assert {:ok, second} = TaskRegistry.fetch("contract.echo")

    refute Task.contract_hash(first) == Task.contract_hash(second)
  end

  test "inference registry rejects modules without the provider callback" do
    original = Application.get_env(:storyarn, InferenceProviders, [])
    on_exit(fn -> Application.put_env(:storyarn, InferenceProviders, original) end)

    Application.put_env(:storyarn, InferenceProviders, providers: %{"invalid" => String})
    assert {:error, :provider_unavailable} = InferenceProviders.fetch("invalid")
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

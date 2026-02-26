defmodule Storyarn.Flows.Evaluator.NodeEvaluators.InstructionEvaluatorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.NodeEvaluators.InstructionEvaluator
  alias Storyarn.Flows.Evaluator.State

  defp make_state(variables \\ %{}) do
    %State{
      start_node_id: "entry_1",
      current_node_id: "node_1",
      started_at: System.monotonic_time(:millisecond),
      status: :running,
      variables: variables,
      initial_variables: variables,
      previous_variables: %{},
      history: [],
      console: [],
      execution_path: [],
      execution_log: [],
      step_count: 0,
      max_steps: 1000,
      breakpoints: MapSet.new(),
      call_stack: [],
      snapshots: []
    }
  end

  defp make_node(data) do
    %{id: "inst_1", type: "instruction", data: data}
  end

  # =============================================================================
  # evaluate/3 — empty assignments
  # =============================================================================

  describe "evaluate/3 — empty assignments" do
    test "no assignments logs 'no assignments' to console" do
      state = make_state()
      node = make_node(%{"assignments" => []})

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      console_messages = Enum.map(final_state.console, & &1.message)
      assert Enum.any?(console_messages, &String.contains?(&1, "no assignments"))
    end

    test "nil data defaults to empty assignments" do
      state = make_state()
      node = make_node(nil)

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      console_messages = Enum.map(final_state.console, & &1.message)
      assert Enum.any?(console_messages, &String.contains?(&1, "no assignments"))
    end
  end

  # =============================================================================
  # evaluate/3 — with changes
  # =============================================================================

  describe "evaluate/3 — with successful assignments" do
    test "updates variable and logs change to console" do
      variables = %{
        "mc.health" => %{
          value: 100,
          type: "number",
          block_type: "number",
          source: :init,
          previous_value: nil
        }
      }

      state = make_state(variables)

      node =
        make_node(%{
          "assignments" => [
            %{
              "sheet" => "mc",
              "variable" => "health",
              "operator" => "set",
              "value" => "50"
            }
          ]
        })

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      assert final_state.variables["mc.health"].value == 50
      assert length(final_state.console) >= 1
    end

    test "logs boolean set_true change" do
      variables = %{
        "flags.met" => %{
          value: false,
          type: "boolean",
          block_type: "boolean",
          source: :init,
          previous_value: nil
        }
      }

      state = make_state(variables)

      node =
        make_node(%{
          "assignments" => [
            %{
              "sheet" => "flags",
              "variable" => "met",
              "operator" => "set_true"
            }
          ]
        })

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      assert final_state.variables["flags.met"].value == true
    end
  end

  # =============================================================================
  # evaluate/3 — with errors
  # =============================================================================

  describe "evaluate/3 — errors" do
    test "logs error for missing variable" do
      state = make_state(%{})

      node =
        make_node(%{
          "assignments" => [
            %{
              "sheet" => "mc",
              "variable" => "nonexistent",
              "operator" => "set",
              "value" => "1"
            }
          ]
        })

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      error_messages = final_state.console |> Enum.filter(&(&1.level == :error))
      assert length(error_messages) >= 1
    end
  end

  # =============================================================================
  # evaluate/3 — follows output connection
  # =============================================================================

  describe "evaluate/3 — connection following" do
    test "follows default output when connection exists" do
      state = make_state()
      node = make_node(%{"assignments" => []})

      connections = [
        %{source_node_id: "inst_1", source_pin: "default", target_node_id: "next_1"}
      ]

      result = InstructionEvaluator.evaluate(node, state, connections)

      assert {:ok, final_state} = result
      assert final_state.current_node_id == "next_1"
    end

    test "returns :finished when no output connection" do
      state = make_state()
      node = make_node(%{"assignments" => []})

      result = InstructionEvaluator.evaluate(node, state, [])

      assert {:finished, final_state} = result
      assert final_state.status == :finished
    end
  end
end

defmodule Storyarn.Flows.Evaluator.InteractionEvaluatorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine

  # =============================================================================
  # Test helpers (same as engine_test.exs)
  # =============================================================================

  defp var(value, block_type, opts \\ []) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: Keyword.get(opts, :block_id, 1),
      sheet_shortcut: Keyword.get(opts, :sheet, "test"),
      variable_name: Keyword.get(opts, :name, "var"),
      constraints: Keyword.get(opts, :constraints, nil)
    }
  end

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp conn(source_id, source_pin, target_id, target_pin \\ "input") do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: target_pin
    }
  end

  defp console_messages(state) do
    state.console |> Enum.reverse() |> Enum.map(& &1.message)
  end

  # =============================================================================
  # evaluate/3
  # =============================================================================

  describe "evaluate/3" do
    test "with valid map_id returns waiting_input with pending_choices" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "interaction", %{"map_id" => 42}),
        3 => node(3, "dialogue")
      }

      conns = [conn(1, "default", 2), conn(2, "zone_evt_1", 3)]
      state = Engine.init(%{}, 1)

      # Step through entry
      {:ok, state} = Engine.step(state, nodes, conns)
      # Step into interaction — should wait
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      assert state.status == :waiting_input
      assert state.pending_choices.type == :interaction
      assert state.pending_choices.node_id == 2
      assert state.pending_choices.map_id == 42
      assert Enum.any?(console_messages(state), &String.contains?(&1, "waiting for zone input"))
    end

    test "with nil map_id returns error" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "interaction", %{"map_id" => nil})
      }

      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:error, state, :no_map} = Engine.step(state, nodes, conns)

      assert state.status == :finished
      assert Enum.any?(console_messages(state), &String.contains?(&1, "no map configured"))
    end
  end

  # =============================================================================
  # execute_interaction_instruction/3
  # =============================================================================

  describe "execute_interaction_instruction/3" do
    setup do
      variables = %{
        "mc.jaime.health" => var(100, "number"),
        "mc.jaime.strength" => var(10, "number")
      }

      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "interaction", %{"map_id" => 42}),
        3 => node(3, "dialogue")
      }

      conns = [conn(1, "default", 2), conn(2, "zone_evt_1", 3)]
      state = Engine.init(variables, 1)

      # Advance to interaction
      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      {:ok, state: state, nodes: nodes, conns: conns}
    end

    test "executes number add assignment and stays in waiting_input", %{state: state} do
      assignments = [
        %{
          "sheet" => "mc.jaime",
          "variable" => "health",
          "operator" => "subtract",
          "value" => "20",
          "value_type" => "literal"
        }
      ]

      {:ok, new_state} = Engine.execute_interaction_instruction(state, assignments, "Trap Zone")

      assert new_state.status == :waiting_input
      assert new_state.variables["mc.jaime.health"].value == 80.0
      assert new_state.pending_choices.type == :interaction
    end

    test "logs changes to console and history", %{state: state} do
      assignments = [
        %{
          "sheet" => "mc.jaime",
          "variable" => "strength",
          "operator" => "add",
          "value" => "5",
          "value_type" => "literal"
        }
      ]

      {:ok, new_state} = Engine.execute_interaction_instruction(state, assignments, "Buff Zone")

      messages = console_messages(new_state)
      assert Enum.any?(messages, &String.contains?(&1, "[Buff Zone]"))
      assert Enum.any?(messages, &String.contains?(&1, "mc.jaime.strength"))

      assert new_state.history != []
      latest = hd(new_state.history)
      assert latest.variable_ref == "mc.jaime.strength"
      assert latest.source == :instruction
    end

    test "returns error when not in waiting_input" do
      state = Engine.init(%{}, 1)
      {:error, _state, :not_waiting_input} = Engine.execute_interaction_instruction(state, [])
    end
  end

  # =============================================================================
  # choose_interaction_event/3
  # =============================================================================

  describe "choose_interaction_event/3" do
    setup do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "interaction", %{"map_id" => 42}),
        3 => node(3, "dialogue", %{"text" => "Done!"})
      }

      conns = [conn(1, "default", 2), conn(2, "zone_evt_1", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      {:ok, state: state, nodes: nodes, conns: conns}
    end

    test "with matching connection advances to target node", %{state: state, conns: conns} do
      {:ok, new_state} = Engine.choose_interaction_event(state, "zone_evt_1", conns)

      assert new_state.current_node_id == 3
      assert new_state.status == :paused
      assert new_state.pending_choices == nil
    end

    test "with no connection returns finished", %{state: state, conns: conns} do
      {:finished, new_state} = Engine.choose_interaction_event(state, "nonexistent_zone", conns)

      assert new_state.status == :finished
      messages = console_messages(new_state)
      assert Enum.any?(messages, &String.contains?(&1, "No connection from event zone"))
    end

    test "returns error when not in waiting_input" do
      state = Engine.init(%{}, 1)

      {:error, _state, :not_waiting_input} =
        Engine.choose_interaction_event(state, "zone_evt_1", [])
    end
  end
end

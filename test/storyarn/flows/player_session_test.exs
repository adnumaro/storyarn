defmodule Storyarn.Flows.PlayerSessionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Flow

  describe "continue_player_session/1" do
    test "advances a continue-only dialogue to the next interaction" do
      nodes = nodes([node(1, "entry"), node(2, "dialogue"), node(3, "exit")])
      connections = [connection(1, 2), connection(2, 3)]
      session = stopped_session(nodes, connections)

      assert {:ok, continued} = Flows.continue_player_session(session)
      assert continued.state.current_node_id == 3
      assert continued.state.status == :finished
    end

    test "does not bypass a dialogue waiting for an authored choice" do
      responses = [response("one"), response("two")]
      nodes = nodes([node(1, "entry"), node(2, "dialogue", %{"responses" => responses}), node(3, "exit")])
      connections = [connection(1, 2), connection(2, 3, "one"), connection(2, 3, "two")]
      session = stopped_session(nodes, connections)

      assert {:ok, unchanged} = Flows.continue_player_session(session)
      assert unchanged == session
      assert unchanged.state.status == :waiting_input
    end
  end

  describe "choose_player_response/2" do
    test "selects a waiting response and advances" do
      responses = [response("one"), response("two")]
      nodes = nodes([node(1, "entry"), node(2, "dialogue", %{"responses" => responses}), node(3, "exit")])
      connections = [connection(1, 2), connection(2, 3, "one"), connection(2, 3, "two")]
      session = stopped_session(nodes, connections)

      assert {:ok, chosen} = Flows.choose_player_response(session, "two")
      assert chosen.state.current_node_id == 3
      assert chosen.state.status == :finished
      assert Enum.any?(chosen.state.console, &String.starts_with?(&1.message, "Selected:"))
    end

    test "returns a domain error when the session is not waiting" do
      session = session(nodes([node(1, "exit")]), [], Engine.init(%{}, 1))

      assert {:error, :invalid_response, ^session} =
               Flows.choose_player_response(session, "missing")
    end
  end

  describe "numbered response selection" do
    test "player mode numbers only valid responses while analysis mode includes all" do
      responses = [
        %{id: "hidden", valid: false},
        %{id: "first", valid: true},
        %{id: "second", valid: true}
      ]

      assert {:ok, "first"} = Flows.player_response_id_by_number(responses, :player, 1)
      assert {:ok, "hidden"} = Flows.player_response_id_by_number(responses, :analysis, 1)

      assert {:error, :response_not_found} =
               Flows.player_response_id_by_number(responses, :player, 4)
    end

    test "rejects zero and negative shortcut numbers" do
      responses = [%{id: "first", valid: true}, %{id: "second", valid: true}]

      assert {:error, :response_not_found} =
               Flows.player_response_id_by_number(responses, :player, 0)

      assert {:error, :response_not_found} =
               Flows.player_response_id_by_number(responses, :player, -1)
    end
  end

  describe "history and restart" do
    test "go back restores a previous renderable state" do
      nodes = nodes([node(1, "entry"), node(2, "dialogue"), node(3, "exit")])
      connections = [connection(1, 2), connection(2, 3)]
      stopped = stopped_session(nodes, connections)
      {:ok, finished} = Flows.continue_player_session(stopped)

      assert Flows.player_session_can_go_back?(finished)
      assert {:ok, pre_exit} = Flows.go_back_player_session(finished)
      assert {:ok, restored} = Flows.go_back_player_session(pre_exit)
      assert restored.state.current_node_id == 2
      assert restored.state.status == :paused
    end

    test "go back is explicit when no renderable history exists" do
      session = session(nodes([node(1, "entry")]), [], Engine.init(%{}, 1))

      refute Flows.player_session_can_go_back?(session)
      assert {:error, :no_history, ^session} = Flows.go_back_player_session(session)
    end

    test "restart resets the run and returns to its first interaction" do
      nodes = nodes([node(1, "entry"), node(2, "dialogue"), node(3, "exit")])
      connections = [connection(1, 2), connection(2, 3)]
      stopped = stopped_session(nodes, connections)
      {:ok, finished} = Flows.continue_player_session(stopped)

      assert {:ok, restarted} = Flows.restart_player_session(finished)
      assert restarted.state.current_node_id == 2
      assert restarted.state.status == :paused
      assert restarted.state.call_stack == []
      assert restarted.state.step_count == 1
    end
  end

  defp stopped_session(nodes, connections) do
    state = Engine.init(%{}, 1)

    {_status, stopped_state, _skipped} =
      Flows.player_step_until_interactive(state, nodes, connections)

    session(nodes, connections, stopped_state)
  end

  defp session(nodes, connections, state) do
    flow = %Flow{id: 10, project_id: 20, name: "Player test"}
    Flows.restore_player_session(flow, %{state | current_flow_id: flow.id}, nodes, connections, nil)
  end

  defp nodes(nodes), do: Map.new(nodes, &{&1.id, &1})
  defp node(id, type, data \\ %{}), do: %{id: id, type: type, data: data}
  defp response(id), do: %{"id" => id, "text" => id, "condition" => ""}

  defp connection(source_id, target_id, source_pin \\ "output") do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: "input"
    }
  end
end

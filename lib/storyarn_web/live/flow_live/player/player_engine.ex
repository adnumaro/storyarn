defmodule StoryarnWeb.FlowLive.Player.PlayerEngine do
  @moduledoc """
  Thin wrapper around the Flows evaluator that auto-advances through
  non-interactive nodes (entry, hub, condition, instruction, jump)
  until it reaches a dialogue, exit, or error.

  The evaluator is a pure functional state machine — this module simply
  calls `Flows.evaluator_step/3` in a loop.
  """

  alias Storyarn.Flows
  alias Storyarn.Flows.Evaluator.EngineHelpers
  alias Storyarn.Flows.Evaluator.NodeEvaluators.DialogueEvaluator
  alias Storyarn.Flows.Evaluator.State

  @max_auto_steps 100

  @non_interactive_types ~w(entry hub condition instruction jump subflow)

  @doc """
  Step the engine forward until it reaches an interactive node (dialogue, exit)
  or an error/flow-jump condition.

  Returns `{status, state, skipped_nodes}` where:
  - `status` is `:ok | :waiting_input | :finished | :flow_jump | :flow_return | :error`
  - `state` is the updated engine state
  - `skipped_nodes` is a list of `{node_id, node_type}` tuples for non-interactive
    nodes that were traversed (useful for journey tracking)

  Options:
  - `:max_steps` — safety limit (default #{@max_auto_steps})
  """
  @spec step_until_interactive(State.t(), map(), list(), keyword()) ::
          {:ok | :waiting_input | :finished | :error, State.t(), list()}
          | {:flow_jump, State.t(), integer(), list()}
          | {:flow_return, State.t(), list()}
  def step_until_interactive(state, nodes, connections, opts \\ []) do
    max = Keyword.get(opts, :max_steps, @max_auto_steps)
    advance_current_dialogue? = Keyword.get(opts, :advance_current_dialogue, false)
    do_step(state, nodes, connections, max, 0, [], advance_current_dialogue?)
  end

  defp do_step(state, _nodes, _connections, max, count, skipped, _advance_current_dialogue?) when count >= max do
    {:error, state, Enum.reverse(skipped)}
  end

  defp do_step(%State{status: :finished} = state, _nodes, _connections, _max, _count, skipped, _advance_current_dialogue?) do
    {:finished, state, Enum.reverse(skipped)}
  end

  defp do_step(
         %State{status: :waiting_input} = state,
         _nodes,
         _connections,
         _max,
         _count,
         skipped,
         _advance_current_dialogue?
       ) do
    {:waiting_input, state, Enum.reverse(skipped)}
  end

  defp do_step(state, nodes, connections, max, count, skipped, advance_current_dialogue?) do
    current_node = Map.get(nodes, state.current_node_id)

    if stop_at_dialogue?(current_node, state, advance_current_dialogue?) do
      stop_at_dialogue(current_node, state, skipped)
    else
      do_evaluator_step(state, nodes, connections, max, count, skipped, advance_current_dialogue?)
    end
  end

  defp do_evaluator_step(state, nodes, connections, max, count, skipped, advance_current_dialogue?) do
    current_node = Map.get(nodes, state.current_node_id)

    case Flows.evaluator_step(state, nodes, connections) do
      {:ok, new_state} ->
        # Node was processed, check if we should continue auto-advancing
        node_type = if current_node, do: current_node.type
        ctx = %{nodes: nodes, connections: connections, max: max, count: count, skipped: skipped}
        handle_ok_step(node_type, state, new_state, ctx, advance_current_dialogue?)

      {:waiting_input, new_state} ->
        {:waiting_input, new_state, Enum.reverse(skipped)}

      {:finished, new_state} ->
        {:finished, new_state, Enum.reverse(skipped)}

      {:flow_jump, new_state, flow_id} ->
        {:flow_jump, new_state, flow_id, Enum.reverse(skipped)}

      {:flow_return, new_state} ->
        {:flow_return, new_state, Enum.reverse(skipped)}

      {:error, new_state, _reason} ->
        {:error, new_state, Enum.reverse(skipped)}

      {:step_limit, new_state} ->
        {:error, new_state, Enum.reverse(skipped)}
    end
  end

  defp handle_ok_step(node_type, state, new_state, ctx, _advance_current_dialogue?)
       when node_type in @non_interactive_types do
    new_skipped = [{state.current_node_id, node_type} | ctx.skipped]
    do_step(new_state, ctx.nodes, ctx.connections, ctx.max, ctx.count + 1, new_skipped, false)
  end

  defp handle_ok_step("dialogue", _state, new_state, ctx, true) do
    do_step(new_state, ctx.nodes, ctx.connections, ctx.max, ctx.count + 1, ctx.skipped, false)
  end

  defp handle_ok_step(_node_type, _state, new_state, ctx, _advance_current_dialogue?) do
    # Unknown node type that returned :ok — treat as interactive stop.
    {:ok, new_state, Enum.reverse(ctx.skipped)}
  end

  defp stop_at_dialogue?(%{type: "dialogue"}, _state, true), do: false
  defp stop_at_dialogue?(%{type: "dialogue"}, _state, false), do: true
  defp stop_at_dialogue?(_node, _state, _advance_current_dialogue?), do: false

  defp stop_at_dialogue(%{id: node_id, data: data} = node, state, skipped) do
    responses = data["responses"] || []
    evaluated = DialogueEvaluator.evaluate_response_conditions(responses, state.variables)
    valid_responses = Enum.filter(evaluated, & &1.valid)

    if length(valid_responses) > 1 do
      case Flows.evaluator_step(state, %{node.id => node}, []) do
        {:waiting_input, new_state} -> {:waiting_input, new_state, Enum.reverse(skipped)}
        {_status, new_state} -> {:ok, new_state, Enum.reverse(skipped)}
      end
    else
      state =
        EngineHelpers.add_console(
          state,
          :info,
          node_id,
          EngineHelpers.node_label(node),
          "Dialogue — waiting for continue"
        )

      {:ok, state, Enum.reverse(skipped)}
    end
  end
end

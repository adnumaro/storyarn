defmodule StoryarnWeb.FlowLive.Player.PlayerEngine do
  @moduledoc """
  Thin wrapper around the Flows evaluator that auto-advances through
  non-interactive nodes (entry, hub, condition, instruction, jump, scene)
  until it reaches a dialogue, exit, or error.

  The evaluator is a pure functional state machine — this module simply
  calls `Flows.evaluator_step/3` in a loop.
  """

  alias Storyarn.Flows
  alias Storyarn.Flows.Evaluator.State

  @max_auto_steps 100

  @non_interactive_types ~w(entry hub condition instruction jump scene subflow)

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
    do_step(state, nodes, connections, max, 0, [])
  end

  defp do_step(state, _nodes, _connections, max, count, skipped) when count >= max do
    {:error, state, Enum.reverse(skipped)}
  end

  defp do_step(%State{status: :finished} = state, _nodes, _connections, _max, _count, skipped) do
    {:finished, state, Enum.reverse(skipped)}
  end

  defp do_step(
         %State{status: :waiting_input} = state,
         _nodes,
         _connections,
         _max,
         _count,
         skipped
       ) do
    {:waiting_input, state, Enum.reverse(skipped)}
  end

  defp do_step(state, nodes, connections, max, count, skipped) do
    current_node = Map.get(nodes, state.current_node_id)

    case Flows.evaluator_step(state, nodes, connections) do
      {:ok, new_state} ->
        # Node was processed, check if we should continue auto-advancing
        node_type = if current_node, do: current_node.type, else: nil

        if node_type in @non_interactive_types do
          new_skipped = [{state.current_node_id, node_type} | skipped]
          do_step(new_state, nodes, connections, max, count + 1, new_skipped)
        else
          # Unknown node type that returned :ok — treat as interactive stop
          {:ok, new_state, Enum.reverse(skipped)}
        end

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
    end
  end
end

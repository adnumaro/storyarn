defmodule Storyarn.Flows.Evaluator.NodeEvaluators.InteractionEvaluator do
  @moduledoc """
  Handles evaluation of `interaction` nodes in the flow debugger.

  An interaction node references a project map whose zones become interactive
  elements. Event zones produce dynamic output pins; instruction zones execute
  variable assignments; display zones show live values.

  Three entry points:
  - `evaluate/3`              — Sets pending_choices and returns {:waiting_input, state}
  - `execute_instruction/4`   — Runs zone assignments (stays in waiting_input)
  - `choose_event/3`          — Advances flow via the event zone's output pin
  """

  alias Storyarn.Flows.Evaluator.{EngineHelpers, InstructionExec}

  @doc """
  Evaluate an interaction node: pause and wait for zone interaction.

  Returns `{:waiting_input, state}` with pending_choices containing the map
  reference, or `{:error, state, :no_map}` if no map_id is configured.
  """
  def evaluate(node, state, _connections) do
    data = node.data || %{}
    label = EngineHelpers.node_label(node) || "Interaction"
    map_id = data["map_id"]

    if is_nil(map_id) do
      state =
        EngineHelpers.add_console(
          state,
          :error,
          node.id,
          label,
          "Interaction node has no map configured"
        )

      {:error, %{state | status: :finished}, :no_map}
    else
      state =
        EngineHelpers.add_console(
          state,
          :info,
          node.id,
          label,
          "Interaction — waiting for zone input"
        )

      pending = %{
        type: :interaction,
        node_id: node.id,
        map_id: map_id,
        label: label
      }

      {:waiting_input, %{state | status: :waiting_input, pending_choices: pending}}
    end
  end

  @doc """
  Execute an instruction zone's assignments without advancing the flow.

  The interaction node stays in `waiting_input` — the player can click
  multiple instruction zones before choosing an event zone to advance.

  Returns `{:ok, state}`.
  """
  def execute_instruction(state, assignments, node_id, zone_name) do
    label = state.pending_choices[:label] || "Interaction"

    {:ok, new_variables, changes, errors} = InstructionExec.execute(assignments, state.variables)
    state = %{state | variables: new_variables}

    # Log each change
    state =
      Enum.reduce(changes, state, fn change, acc ->
        EngineHelpers.add_console(
          acc,
          :info,
          node_id,
          label,
          "[#{zone_name}] #{change.variable_ref}: #{EngineHelpers.format_value(change.old_value)} -> #{EngineHelpers.format_value(change.new_value)} (#{change.operator})"
        )
      end)

    state = EngineHelpers.add_history_entries(state, node_id, label, changes, :instruction)

    # Log errors
    state =
      Enum.reduce(errors, state, fn error, acc ->
        EngineHelpers.add_console(
          acc,
          :error,
          node_id,
          label,
          "[#{zone_name}] #{error.variable_ref}: #{error.reason}"
        )
      end)

    state =
      if changes == [] and errors == [] do
        EngineHelpers.add_console(
          state,
          :info,
          node_id,
          label,
          "[#{zone_name}] Instruction — no assignments"
        )
      else
        state
      end

    {:ok, state}
  end

  @doc """
  Advance the flow through an event zone's output pin.

  Looks for a connection from the interaction node using the event zone's
  ID as the source pin. Returns `{:ok, state}` if connected, or
  `{:finished, state}` if no connection exists.
  """
  def choose_event(state, event_name, connections) do
    node_id = state.pending_choices[:node_id]
    label = state.pending_choices[:label] || "Interaction"

    state =
      EngineHelpers.add_console(
        state,
        :info,
        node_id,
        label,
        "Event zone selected: #{event_name}"
      )

    conn = EngineHelpers.find_connection(connections, node_id, event_name)

    case conn do
      nil ->
        state =
          EngineHelpers.add_console(
            state,
            :error,
            node_id,
            label,
            "No connection from event zone \"#{event_name}\""
          )

        {:finished, %{state | status: :finished}}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end
end

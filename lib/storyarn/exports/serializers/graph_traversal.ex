defmodule Storyarn.Exports.Serializers.GraphTraversal do
  @moduledoc """
  Linearizes a flow graph for text-based export formats (Ink, Yarn).

  Converts a directed graph of flow nodes and connections into an ordered
  list of rendering instructions that text serializers can iterate over.

  ## Algorithm

  1. Start from the entry node
  2. Walk connections depth-first
  3. Hub nodes → emit `:label` marker, continue children
  4. Jump nodes → emit `:jump` reference
  5. Condition nodes → emit `:condition_start`/`:condition_branch`/`:condition_end`
  6. Dialogue responses → emit `:choices_start`/`:choice`/`:choices_end`
  7. Exit nodes → emit `:exit`
  8. Detect cycles via visited set, emit jump to break
  """

  alias Storyarn.Exports.Serializers.Helpers

  @type instruction ::
          {:label, node :: map(), label :: String.t()}
          | {:dialogue, node :: map()}
          | {:choices_start, node :: map()}
          | {:choice, response :: map(), index :: non_neg_integer()}
          | {:choices_end, node :: map()}
          | {:condition_start, node :: map()}
          | {:condition_branch, pin :: String.t(), label :: String.t(),
             index :: non_neg_integer()}
          | {:condition_end, node :: map()}
          | {:instruction, node :: map()}
          | {:scene, node :: map()}
          | {:subflow, node :: map()}
          | {:jump, node :: map(), target_label :: String.t()}
          | {:divert, target_label :: String.t()}
          | {:exit, node :: map()}
          | {:comment, text :: String.t()}

  @doc """
  Linearizes a flow into an ordered list of rendering instructions.

  Returns `{instructions, hub_sections}` where:
  - `instructions` is the main flow body (from entry node)
  - `hub_sections` is a list of `{hub_label, instructions}` for hub nodes
    that need to be emitted as separate sections (stitches/labels)
  """
  def linearize(flow) do
    nodes = Helpers.node_index(flow)
    conn_graph = Helpers.connection_graph(flow)
    entry = Helpers.find_entry_node(flow)

    if entry do
      # First pass: identify all hub nodes (they become labels)
      hub_labels = collect_hub_labels(flow.nodes)

      # Second pass: traverse from entry, collecting instructions
      state = %{
        nodes: nodes,
        conn_graph: conn_graph,
        hub_labels: hub_labels,
        visited: MapSet.new(),
        hub_queue: [],
        instructions: []
      }

      state = traverse(entry.id, state)

      # Third pass: traverse hub sections that weren't reached inline
      {main_instructions, hub_sections} = process_hub_queue(state)

      {Enum.reverse(main_instructions), hub_sections}
    else
      {[], []}
    end
  end

  # ---------------------------------------------------------------------------
  # Hub label collection
  # ---------------------------------------------------------------------------

  defp collect_hub_labels(nodes) do
    nodes
    |> Enum.filter(&(&1.type == "hub"))
    |> Map.new(fn hub ->
      label = Helpers.shortcut_to_identifier(hub.data["label"] || "hub_#{hub.id}")
      {hub.id, label}
    end)
  end

  # ---------------------------------------------------------------------------
  # Main traversal
  # ---------------------------------------------------------------------------

  defp traverse(node_id, state) do
    if MapSet.member?(state.visited, node_id) do
      # Cycle detected — emit a divert to the node's label if it's a hub
      label = state.hub_labels[node_id]

      if label do
        %{state | instructions: [{:divert, label} | state.instructions]}
      else
        state
      end
    else
      state = %{state | visited: MapSet.put(state.visited, node_id)}

      case Map.get(state.nodes, node_id) do
        nil -> state
        node -> traverse_node(node, state)
      end
    end
  end

  defp traverse_node(%{type: "entry"} = node, state) do
    # Entry is implicit — just follow connections
    targets = outgoing(state, node.id)
    traverse_targets(targets, state)
  end

  defp traverse_node(%{type: "exit"} = node, state) do
    %{state | instructions: [{:exit, node} | state.instructions]}
  end

  defp traverse_node(%{type: "dialogue"} = node, state) do
    responses = Helpers.dialogue_responses(node.data)

    if responses != [] do
      traverse_dialogue_with_choices(node, responses, state)
    else
      # Dialogue without choices — just text, then follow connections
      state = %{state | instructions: [{:dialogue, node} | state.instructions]}
      targets = outgoing(state, node.id)
      traverse_targets(targets, state)
    end
  end

  defp traverse_node(%{type: "condition"} = node, state) do
    state = %{state | instructions: [{:condition_start, node} | state.instructions]}

    # Condition nodes have multiple output pins (one per case)
    cases = node.data["cases"] || []
    targets_by_pin = outgoing_by_pin(state, node.id)

    state =
      cases
      |> Enum.with_index()
      |> Enum.reduce(state, fn {case_data, idx}, acc ->
        pin = case_data["id"] || "case_#{idx}"
        label = case_data["label"] || case_data["value"] || "case_#{idx}"
        acc = %{acc | instructions: [{:condition_branch, pin, label, idx} | acc.instructions]}

        case Map.get(targets_by_pin, pin) do
          nil -> acc
          pin_targets -> traverse_targets(pin_targets, acc)
        end
      end)

    %{state | instructions: [{:condition_end, node} | state.instructions]}
  end

  defp traverse_node(%{type: "instruction"} = node, state) do
    state = %{state | instructions: [{:instruction, node} | state.instructions]}
    targets = outgoing(state, node.id)
    traverse_targets(targets, state)
  end

  defp traverse_node(%{type: "hub"} = node, state) do
    label = state.hub_labels[node.id] || "hub_#{node.id}"

    # Queue hub for separate section emission
    state = %{state | hub_queue: [{node.id, label} | state.hub_queue]}

    # Emit a divert to this hub
    %{state | instructions: [{:divert, label} | state.instructions]}
  end

  defp traverse_node(%{type: "jump"} = node, state) do
    # Jump references a target hub or flow
    {target_label, state} = resolve_jump_target(node, state)
    %{state | instructions: [{:jump, node, target_label} | state.instructions]}
  end

  defp traverse_node(%{type: "subflow"} = node, state) do
    state = %{state | instructions: [{:subflow, node} | state.instructions]}
    targets = outgoing(state, node.id)
    traverse_targets(targets, state)
  end

  defp traverse_node(%{type: "scene"} = node, state) do
    state = %{state | instructions: [{:scene, node} | state.instructions]}
    targets = outgoing(state, node.id)
    traverse_targets(targets, state)
  end

  defp traverse_node(_node, state), do: state

  # -- Dialogue traversal helpers --

  defp traverse_dialogue_with_choices(node, responses, state) do
    # Build pin lookup once (O(R+C) instead of O(R*C))
    targets_by_pin = outgoing_by_pin(state, node.id)
    state = %{state | instructions: [{:dialogue, node} | state.instructions]}
    state = %{state | instructions: [{:choices_start, node} | state.instructions]}

    state =
      responses
      |> Enum.with_index()
      |> Enum.reduce(state, fn {resp, idx}, acc ->
        acc = %{acc | instructions: [{:choice, resp, idx} | acc.instructions]}
        pin = "response_#{resp["id"]}"
        traverse_pin_targets(acc, targets_by_pin, pin)
      end)

    %{state | instructions: [{:choices_end, node} | state.instructions]}
  end

  defp traverse_pin_targets(state, targets_by_pin, pin) do
    case Map.get(targets_by_pin, pin) do
      nil -> state
      pin_targets -> traverse_targets(pin_targets, state)
    end
  end

  # ---------------------------------------------------------------------------
  # Target traversal
  # ---------------------------------------------------------------------------

  defp traverse_targets([], state), do: state

  defp traverse_targets([{target_id, _pin, _conn} | rest], state) do
    state = traverse(target_id, state)

    # Only follow remaining targets if the first didn't end the sequence
    case rest do
      [] -> state
      _ -> traverse_targets(rest, state)
    end
  end

  # ---------------------------------------------------------------------------
  # Hub queue processing
  # ---------------------------------------------------------------------------

  defp process_hub_queue(state) do
    hub_sections =
      state.hub_queue
      |> Enum.reverse()
      |> Enum.uniq_by(fn {id, _} -> id end)
      |> Enum.map(fn {hub_id, label} ->
        hub_state = %{state | instructions: [], visited: state.visited}
        hub_node = Map.get(state.nodes, hub_id)

        hub_state =
          if hub_node do
            targets = outgoing(hub_state, hub_id)
            traverse_targets(targets, hub_state)
          else
            hub_state
          end

        {label, Enum.reverse(hub_state.instructions)}
      end)

    {state.instructions, hub_sections}
  end

  # ---------------------------------------------------------------------------
  # Connection helpers
  # ---------------------------------------------------------------------------

  defp outgoing(state, node_id) do
    Helpers.outgoing_targets(node_id, state.conn_graph)
  end

  defp outgoing_by_pin(state, node_id) do
    state.conn_graph
    |> Map.get(node_id, [])
    |> Enum.group_by(fn {_target, pin, _conn} -> pin end)
  end

  defp resolve_jump_target(node, state) do
    # Jump node data may reference a hub_id or target flow
    data = node.data || %{}

    cond do
      # Jump to a hub within same flow
      hub_id = data["hub_id"] ->
        label = state.hub_labels[hub_id] || Helpers.shortcut_to_identifier("hub_#{hub_id}")
        # Queue the hub for section emission (same as inline hub traversal)
        state = %{state | hub_queue: [{hub_id, label} | state.hub_queue]}
        {label, state}

      # Jump to another flow
      flow_shortcut = data["target_flow_shortcut"] ->
        {Helpers.shortcut_to_identifier(flow_shortcut), state}

      true ->
        # Follow the connection to find the target
        label =
          case outgoing(state, node.id) do
            [{target_id, _, _} | _] ->
              state.hub_labels[target_id] ||
                Helpers.shortcut_to_identifier("node_#{target_id}")

            [] ->
              "unknown"
          end

        {label, state}
    end
  end
end

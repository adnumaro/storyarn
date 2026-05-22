defmodule Storyarn.Exports.Serializers.FlowControlResolver do
  @moduledoc """
  Shared helpers for Storyarn flow-control nodes in export serializers.

  Text exports can use these helpers before linearizing instructions, while
  graph-shaped exports such as Unity can use the same resolution rules without
  flattening the graph.
  """

  alias Storyarn.Exports.Serializers.Helpers

  @doc """
  Builds a lookup from flow shortcut to flow id.
  """
  def flow_id_by_shortcut(flows) do
    flows
    |> Enum.filter(&(present?(&1.shortcut) && present?(&1.id)))
    |> Map.new(&{&1.shortcut, to_string(&1.id)})
  end

  @doc """
  Returns the 1-based Dialogue System entry index for the root `entry` node.
  """
  def root_entry_index(flow, include? \\ fn _node -> true end) do
    flow.nodes
    |> Enum.filter(include?)
    |> Enum.with_index(1)
    |> Enum.find_value(&entry_node_index/1)
    |> Kernel.||(1)
  end

  @doc """
  Builds a reference map for hub nodes.

  Hubs can be referenced by database id, stringified database id, or user-facing
  `hub_id`. The value is `{node_id, label}` where label is export-safe.
  """
  def hub_reference_map(nodes) do
    nodes
    |> Enum.filter(&(&1.type == "hub"))
    |> Enum.flat_map(&hub_references/1)
    |> Map.new()
  end

  @doc """
  Resolves a hub reference from `hub_reference_map/1`.
  """
  def hub_target(hub_refs, ref) do
    Map.get(hub_refs, ref) || Map.get(hub_refs, to_string(ref))
  end

  @doc """
  Finds a hub node in a node list or node map using the user-facing `hub_id`.
  """
  def find_hub_by_hub_id(nodes, hub_id) do
    nodes
    |> enumerable_nodes()
    |> Enum.find(fn node ->
      node.type == "hub" and is_map(node.data) and node.data["hub_id"] == hub_id
    end)
  end

  @doc """
  Returns the target hub id from jump-like node data.
  """
  def target_hub_id(data) do
    case data["target_hub_id"] || data["hub_id"] do
      value when value in [nil, ""] -> nil
      value -> to_string(value)
    end
  end

  @doc """
  Resolves a referenced flow id from node data.

  Direct ids win. Shortcut references are resolved through the provided
  `flow_id_by_shortcut` map.
  """
  def referenced_flow_id(data, flow_id_by_shortcut \\ %{}) do
    direct_ref = data["referenced_flow_id"] || data["target_flow_id"] || data["flow_id"]
    shortcut_ref = referenced_flow_shortcut(data)

    cond do
      present?(direct_ref) -> to_string(direct_ref)
      present?(shortcut_ref) -> flow_id_by_shortcut[shortcut_ref]
      true -> nil
    end
  end

  @doc """
  Returns the target flow shortcut field used by export serializers.
  """
  def referenced_flow_shortcut(data) do
    data["referenced_flow_shortcut"] || data["target_flow_shortcut"] || data["flow_shortcut"]
  end

  @doc """
  Returns condition branch cases with string keys: `id`, `value`, and `label`.
  """
  def condition_cases(%{data: data}, targets_by_pin) when is_map(data) do
    explicit_cases = data["cases"] || []

    cond do
      explicit_cases != [] ->
        explicit_cases

      data["switch_mode"] == true ->
        switch_cases(data)

      true ->
        boolean_cases(targets_by_pin)
    end
  end

  def condition_cases(_node, targets_by_pin), do: boolean_cases(targets_by_pin)

  @doc """
  Extracts switch cases with their original condition block when available.
  """
  def switch_case_defs(raw_condition) do
    case Helpers.extract_condition(raw_condition) do
      %{"blocks" => blocks} when is_list(blocks) ->
        Enum.flat_map(blocks, &switch_block_case_def/1)

      %{"rules" => rules} when is_list(rules) ->
        Enum.flat_map(rules, &switch_rule_case_def/1)

      _ ->
        []
    end
  end

  defp entry_node_index({%{type: "entry"}, index}), do: index
  defp entry_node_index(_node_with_index), do: nil

  defp hub_references(hub) do
    label = Helpers.shortcut_to_identifier(hub.data["label"] || hub.data["hub_id"] || "hub_#{hub.id}")
    refs = [hub.id, to_string(hub.id), hub.data["hub_id"]]

    refs
    |> Enum.reject(&blank?/1)
    |> Enum.map(&{&1, {hub.id, label}})
  end

  defp enumerable_nodes(%{} = nodes), do: Map.values(nodes)
  defp enumerable_nodes(nodes) when is_list(nodes), do: nodes
  defp enumerable_nodes(_nodes), do: []

  defp switch_cases(data) do
    data["condition"]
    |> switch_case_defs()
    |> Enum.map(fn case_def ->
      %{
        "id" => case_def["id"],
        "value" => case_def["value"],
        "label" => case_def["label"]
      }
    end)
  end

  defp switch_block_case_def(%{"type" => "block", "id" => id} = block) when is_binary(id) and id != "" do
    [
      %{
        "id" => id,
        "value" => id,
        "label" => block["label"] || id,
        "condition" => %{"logic" => "all", "blocks" => [block]}
      }
    ]
  end

  defp switch_block_case_def(_block), do: []

  defp switch_rule_case_def(%{"id" => id} = rule) when is_binary(id) and id != "" do
    [
      %{
        "id" => id,
        "value" => id,
        "label" => rule["label"] || id,
        "condition" => %{
          "logic" => "all",
          "blocks" => [%{"type" => "block", "logic" => "all", "rules" => [rule]}]
        }
      }
    ]
  end

  defp switch_rule_case_def(_rule), do: []

  defp boolean_cases(targets_by_pin) do
    ["true", "false"]
    |> Enum.filter(&Map.has_key?(targets_by_pin, &1))
    |> Enum.map(&%{"id" => &1, "value" => &1, "label" => String.capitalize(&1)})
  end

  defp present?(value), do: not blank?(value)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end

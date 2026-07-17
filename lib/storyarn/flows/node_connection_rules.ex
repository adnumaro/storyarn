defmodule Storyarn.Flows.NodeConnectionRules do
  @moduledoc """
  Shared flow graph validation rules.

  These rules separate executable graph nodes from visual/organizational nodes.
  Annotations and sequences can exist without graph edges, so they must not
  pollute flow health, dashboards, or export validation.
  """

  @connection_optional_types ~w(annotation sequence)
  @terminal_output_types ~w(exit jump)
  @output_optional_types @terminal_output_types ++ @connection_optional_types

  @doc "Node types that are allowed to have no graph connections."
  @spec connection_optional_types() :: [String.t()]
  def connection_optional_types, do: @connection_optional_types

  @doc "Node types that are allowed to have no outgoing graph connections."
  @spec outgoing_optional_types() :: [String.t()]
  def outgoing_optional_types, do: @output_optional_types

  @doc "Returns true when a node type should not be reported as connectionless."
  @spec connection_optional_type?(String.t()) :: boolean()
  def connection_optional_type?(type), do: type in @connection_optional_types

  @doc "Returns true when a node type can be reported as unreachable from Entry."
  @spec can_be_unreachable?(String.t()) :: boolean()
  def can_be_unreachable?(type), do: type not in ["entry" | @connection_optional_types]

  @doc "Returns true when a node type is expected to have at least one outgoing connection."
  @spec needs_outgoing_connection?(String.t()) :: boolean()
  def needs_outgoing_connection?(type), do: type not in outgoing_optional_types()

  @doc """
  Returns the output pins that can participate in the executable graph.

  Dynamic node types replace their default output when they expose choices,
  cases, or referenced-flow exits. Keeping this rule on the server prevents
  stale persisted connections from making a node look healthy after its pins
  have changed.
  """
  @spec output_pins(String.t(), map()) :: [String.t()]
  def output_pins(type, data \\ %{})

  def output_pins(type, _data) when type in ~w(entry hub instruction), do: ["output"]
  def output_pins(type, _data) when type in @output_optional_types, do: []

  def output_pins("dialogue", data) do
    case data["responses"] do
      responses when is_list(responses) and responses != [] ->
        responses
        |> Enum.map(& &1["id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)

      _ ->
        ["output"]
    end
  end

  def output_pins("condition", %{"switch_mode" => true} = data) do
    condition = data["condition"] || %{}

    case condition do
      %{"blocks" => blocks} when is_list(blocks) and blocks != [] ->
        dynamic_pin_ids(blocks) ++ ["default"]

      %{"rules" => rules} when is_list(rules) and rules != [] ->
        dynamic_pin_ids(rules) ++ ["default"]

      _ ->
        ["default"]
    end
  end

  def output_pins("condition", _data), do: ["true", "false"]

  def output_pins("subflow", data) do
    pins =
      cond do
        is_list(data["exit_pins"]) and data["exit_pins"] != [] ->
          Enum.map(data["exit_pins"], &normalize_subflow_pin/1)

        is_list(data["exit_labels"]) and data["exit_labels"] != [] ->
          Enum.map(data["exit_labels"], &normalize_subflow_pin/1)

        true ->
          []
      end

    if pins == [], do: ["output"], else: pins
  end

  def output_pins(_type, _data), do: []

  @doc "Returns true when a stored source pin still exists on the node."
  @spec valid_output_pin?(String.t(), map(), String.t()) :: boolean()
  def valid_output_pin?(type, data, source_pin) do
    source_pin in output_pins(type, data)
  end

  @doc "Returns true when a stored target pin exists on the node."
  @spec valid_input_pin?(String.t(), String.t()) :: boolean()
  def valid_input_pin?(type, target_pin) do
    type not in ["entry" | @connection_optional_types] and target_pin == "input"
  end

  defp dynamic_pin_ids(items) do
    items
    |> Enum.map(& &1["id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp normalize_subflow_pin(%{id: id}), do: normalize_subflow_pin(id)
  defp normalize_subflow_pin(%{"id" => id}), do: normalize_subflow_pin(id)

  defp normalize_subflow_pin(pin) do
    pin = to_string(pin)
    if String.starts_with?(pin, "exit_"), do: pin, else: "exit_#{pin}"
  end
end

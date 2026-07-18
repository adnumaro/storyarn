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

  def output_pins("dialogue", data) when is_map(data) do
    case data["responses"] do
      responses when is_list(responses) and responses != [] ->
        dynamic_pin_ids(responses)

      _ ->
        ["output"]
    end
  end

  def output_pins("dialogue", _data), do: []

  def output_pins("condition", %{"switch_mode" => true} = data) do
    condition = normalize_condition(data["condition"])

    case condition do
      %{"blocks" => blocks} when is_list(blocks) ->
        dynamic_pin_ids(blocks) ++ ["default"]

      %{"rules" => rules} when is_list(rules) and rules != [] ->
        dynamic_pin_ids(rules) ++ ["default"]

      _ ->
        ["default"]
    end
  end

  def output_pins("condition", _data), do: ["true", "false"]

  def output_pins("subflow", data) when is_map(data) do
    pins =
      cond do
        is_list(data["exit_pins"]) and data["exit_pins"] != [] ->
          data["exit_pins"]
          |> Enum.map(&normalize_subflow_pin/1)
          |> Enum.reject(&is_nil/1)

        is_list(data["exit_labels"]) and data["exit_labels"] != [] ->
          data["exit_labels"]
          |> Enum.map(&normalize_subflow_pin/1)
          |> Enum.reject(&is_nil/1)

        true ->
          []
      end

    if pins == [], do: ["output"], else: pins
  end

  def output_pins("subflow", _data), do: []

  def output_pins(_type, _data), do: []

  @doc "Returns every source pin accepted for a node, including verified legacy aliases."
  @spec accepted_output_pins(String.t(), map()) :: [String.t()]
  def accepted_output_pins("dialogue", %{"responses" => responses} = data) when is_list(responses) and responses != [] do
    "dialogue"
    |> output_pins(data)
    |> Enum.flat_map(&dialogue_pin_aliases/1)
    |> Enum.uniq()
  end

  def accepted_output_pins(type, data), do: output_pins(type, data)

  @doc "Returns true when a stored source pin still exists on the node."
  @spec valid_output_pin?(String.t(), map(), String.t()) :: boolean()
  def valid_output_pin?(type, data, source_pin) do
    source_pin in accepted_output_pins(type, data)
  end

  @doc "Returns true when a stored target pin exists on the node."
  @spec valid_input_pin?(String.t(), String.t()) :: boolean()
  def valid_input_pin?(type, target_pin) do
    type not in ["entry" | @connection_optional_types] and target_pin == "input"
  end

  defp dynamic_pin_ids(items) do
    items
    |> Enum.filter(&is_map/1)
    |> Enum.map(&Map.get(&1, "id", Map.get(&1, :id)))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_pin_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_condition(condition) when is_map(condition), do: condition

  defp normalize_condition(condition) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _invalid -> %{}
    end
  end

  defp normalize_condition(_condition), do: %{}

  defp normalize_pin_id(id) when is_binary(id) do
    if String.trim(id) == "", do: nil, else: id
  end

  defp normalize_pin_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_pin_id(_id), do: nil

  defp dialogue_pin_aliases(id) do
    aliases = [id, "resp_#{id}"]
    if String.starts_with?(id, "response_"), do: aliases, else: ["response_#{id}" | aliases]
  end

  defp normalize_subflow_pin(%{id: id}), do: normalize_subflow_pin(id)
  defp normalize_subflow_pin(%{"id" => id}), do: normalize_subflow_pin(id)

  defp normalize_subflow_pin(pin) when is_binary(pin) or is_integer(pin) do
    pin = to_string(pin)
    if String.starts_with?(pin, "exit_"), do: pin, else: "exit_#{pin}"
  end

  defp normalize_subflow_pin(_pin), do: nil
end

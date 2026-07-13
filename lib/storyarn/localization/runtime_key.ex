defmodule Storyarn.Localization.RuntimeKey do
  @moduledoc """
  Builds localization keys from runtime-stable entity identifiers.

  Database IDs are deliberately excluded: project recovery and native import
  remap them. Dialogue localization IDs, sheet shortcuts, and fully-qualified
  block variable names survive those operations and are also the identifiers
  exposed to engine runtimes.
  """

  @dialogue_id_format ~r/^[A-Za-z0-9_-]+$/
  @response_id_format ~r/^[A-Za-z0-9_-]+$/

  @spec key(String.t(), String.t(), String.t()) :: String.t()
  def key(source_type, source_ref, source_field)
      when is_binary(source_type) and is_binary(source_ref) and source_ref != "" and is_binary(source_field) do
    "#{source_type}.#{source_ref}.#{source_field}"
  end

  @spec for_flow_node(map(), String.t()) :: String.t()
  def for_flow_node(%{type: "dialogue", data: data}, source_field) do
    key("flow_node", dialogue_id!(data), source_field)
  end

  @spec for_block(map(), String.t(), String.t()) :: String.t()
  def for_block(%{variable_name: variable_name}, sheet_shortcut, source_field) do
    key("block", qualified_block_ref!(sheet_shortcut, variable_name), source_field)
  end

  @spec for_sheet(map(), String.t()) :: String.t()
  def for_sheet(%{shortcut: shortcut}, source_field) do
    key("sheet", required_ref!(shortcut, :sheet_shortcut), source_field)
  end

  @spec dialogue_id!(map()) :: String.t()
  def dialogue_id!(data) when is_map(data) do
    data
    |> Map.get("localization_id")
    |> required_ref!(:dialogue_localization_id)
  end

  @spec qualified_block_ref!(String.t(), String.t()) :: String.t()
  def qualified_block_ref!(sheet_shortcut, variable_name) do
    sheet_ref = sheet_shortcut |> required_ref!(:sheet_shortcut) |> encode_segment()
    variable_ref = variable_name |> required_ref!(:variable_name) |> encode_segment()
    "#{sheet_ref}.#{variable_ref}"
  end

  @spec valid_dialogue_id?(term()) :: boolean()
  def valid_dialogue_id?(value), do: valid_runtime_id?(value, @dialogue_id_format)

  @spec valid_response_id?(term()) :: boolean()
  def valid_response_id?(value), do: valid_runtime_id?(value, @response_id_format)

  @spec new_dialogue_id() :: String.t()
  def new_dialogue_id, do: "dialogue_#{Ecto.UUID.generate()}"

  @spec new_response_id() :: String.t()
  def new_response_id, do: "response_#{Ecto.UUID.generate()}"

  defp valid_runtime_id?(value, format) when is_binary(value) do
    value != "" and byte_size(value) <= 100 and Regex.match?(format, value)
  end

  defp valid_runtime_id?(_value, _format), do: false

  defp required_ref!(value, _name) when is_binary(value) and value != "", do: value

  defp required_ref!(value, name) do
    raise ArgumentError, "missing runtime localization identifier #{inspect(name)}: #{inspect(value)}"
  end

  # A literal dot separates the sheet and variable segments in block keys.
  # Encoding every non identifier-safe byte makes that composition injective,
  # even though sheet shortcuts themselves may contain dots.
  defp encode_segment(value) do
    for <<byte <- value>>, into: "" do
      if identifier_byte?(byte),
        do: <<byte>>,
        else: "%" <> Base.encode16(<<byte>>)
    end
  end

  defp identifier_byte?(byte) do
    byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in [?_, ?-]
  end
end

defmodule Storyarn.Projects.LocalizationRuntimeKey do
  @moduledoc false

  @dialogue_id_format ~r/^[A-Za-z0-9_-]+$/
  @response_id_format ~r/^[A-Za-z0-9_-]+$/

  def key(source_type, source_ref, source_field)
      when is_binary(source_type) and is_binary(source_ref) and source_ref != "" and is_binary(source_field) do
    "#{source_type}.#{source_ref}.#{source_field}"
  end

  def for_flow_node(%{type: "dialogue", data: data}, source_field) do
    key("flow_node", dialogue_id!(data), source_field)
  end

  def for_block(%{variable_name: variable_name}, sheet_shortcut, source_field) do
    key("block", qualified_block_ref!(sheet_shortcut, variable_name), source_field)
  end

  def for_sheet(%{shortcut: shortcut}, source_field) do
    key("sheet", required_ref!(shortcut, :sheet_shortcut), source_field)
  end

  def dialogue_id!(data) when is_map(data) do
    data
    |> Map.get("localization_id")
    |> required_ref!(:dialogue_localization_id)
  end

  def qualified_block_ref!(sheet_shortcut, variable_name) do
    sheet_ref = sheet_shortcut |> required_ref!(:sheet_shortcut) |> encode_segment()
    variable_ref = variable_name |> required_ref!(:variable_name) |> encode_segment()
    "#{sheet_ref}.#{variable_ref}"
  end

  def valid_dialogue_id?(value), do: valid_runtime_id?(value, @dialogue_id_format)
  def valid_response_id?(value), do: valid_runtime_id?(value, @response_id_format)
  def new_dialogue_id, do: "dialogue_#{Ecto.UUID.generate()}"
  def new_response_id, do: "response_#{Ecto.UUID.generate()}"

  defp valid_runtime_id?(value, format) when is_binary(value) do
    value != "" and byte_size(value) <= 100 and Regex.match?(format, value)
  end

  defp valid_runtime_id?(_value, _format), do: false

  defp required_ref!(value, _name) when is_binary(value) and value != "", do: value

  defp required_ref!(value, name) do
    raise ArgumentError, "missing runtime localization identifier #{inspect(name)}: #{inspect(value)}"
  end

  defp encode_segment(value) do
    for <<byte <- value>>, into: "" do
      if identifier_byte?(byte), do: <<byte>>, else: "%" <> Base.encode16(<<byte>>)
    end
  end

  defp identifier_byte?(byte) do
    byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in [?_, ?-]
  end
end

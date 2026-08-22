defmodule Storyarn.Projects.FlowRuntimeKey do
  @moduledoc """
  Owns the runtime-stable identities of dialogue nodes and responses.

  Database IDs are deliberately excluded because project recovery and native
  imports remap them. These identifiers are part of the Flow runtime contract.
  """

  @dialogue_id_format ~r/^[A-Za-z0-9_-]+$/
  @response_id_format ~r/^[A-Za-z0-9_-]+$/

  @spec for_node(map(), String.t()) :: String.t()
  def for_node(%{type: "dialogue", data: data}, source_field) when is_binary(source_field) do
    "flow_node.#{dialogue_id!(data)}.#{source_field}"
  end

  @spec dialogue_id!(map()) :: String.t()
  def dialogue_id!(data) when is_map(data) do
    data
    |> Map.get("localization_id")
    |> required_id!(:dialogue_localization_id)
  end

  @spec valid_dialogue_id?(term()) :: boolean()
  def valid_dialogue_id?(value), do: valid_id?(value, @dialogue_id_format)

  @spec valid_response_id?(term()) :: boolean()
  def valid_response_id?(value), do: valid_id?(value, @response_id_format)

  @spec new_dialogue_id() :: String.t()
  def new_dialogue_id, do: "dialogue_#{Ecto.UUID.generate()}"

  @spec new_response_id() :: String.t()
  def new_response_id, do: "response_#{Ecto.UUID.generate()}"

  defp valid_id?(value, format) when is_binary(value) do
    value != "" and byte_size(value) <= 100 and Regex.match?(format, value)
  end

  defp valid_id?(_value, _format), do: false

  defp required_id!(value, _name) when is_binary(value) and value != "", do: value

  defp required_id!(value, name) do
    raise ArgumentError, "missing Flow runtime identifier #{inspect(name)}: #{inspect(value)}"
  end
end

defmodule Storyarn.Sheets.ContentContract do
  @moduledoc """
  Defines the player-facing Sheet content shipped by the runtime.

  A Sheet contains editor metadata and many block types, but localization only
  owns active, exported text variables plus the active Sheet name used as the
  runtime actor name.
  """

  @localizable_block_types ~w(text rich_text)

  @spec localizable_block_types() :: [String.t()]
  def localizable_block_types, do: @localizable_block_types

  @spec exported_block?(map() | struct()) :: boolean()
  def exported_block?(block) when is_map(block) do
    block_value(block, :is_constant) == false and
      present_variable_name?(block_value(block, :variable_name)) and
      is_nil(block_value(block, :deleted_at))
  end

  def exported_block?(_block), do: false

  @spec localizable_block?(map() | struct()) :: boolean()
  def localizable_block?(block) when is_map(block) do
    block_value(block, :type) in @localizable_block_types and exported_block?(block)
  end

  def localizable_block?(_block), do: false

  defp block_value(block, field) do
    case Map.fetch(block, field) do
      {:ok, value} -> value
      :error -> Map.get(block, Atom.to_string(field))
    end
  end

  defp present_variable_name?(name) when is_binary(name), do: String.trim(name) != ""
  defp present_variable_name?(_name), do: false
end

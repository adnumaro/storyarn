defmodule Storyarn.Localization.SourceContract do
  @moduledoc """
  Defines the runtime content that belongs to the localization inventory.

  Localization is intentionally narrower than the editor data model: a value is
  localizable only when it is player-facing and is part of an engine export
  contract. Editor metadata, scenes, and screenplays are excluded.
  """

  alias Storyarn.Localization.RuntimeKey

  @source_types ~w(flow_node block sheet)
  @content_roles ~w(dialogue stage_direction menu response exit runtime_value speaker_name)
  @localizable_block_types ~w(text rich_text)

  @engine_content_roles %{
    storyarn: @content_roles,
    unity: @content_roles,
    ink: ~w(dialogue response),
    yarn: ~w(dialogue response),
    godot: ~w(dialogue response),
    unreal: ~w(dialogue stage_direction menu response runtime_value speaker_name),
    articy: ~w(dialogue stage_direction menu response runtime_value speaker_name)
  }

  @spec source_types() :: [String.t()]
  def source_types, do: @source_types

  @spec content_roles() :: [String.t()]
  def content_roles, do: @content_roles

  @spec localizable_block_types() :: [String.t()]
  def localizable_block_types, do: @localizable_block_types

  @doc "Returns the localization roles that a serializer can address at runtime."
  @spec export_content_roles(atom()) :: [String.t()]
  def export_content_roles(format), do: Map.get(@engine_content_roles, format, [])

  @spec exported_content_role?(atom(), term()) :: boolean()
  def exported_content_role?(format, content_role), do: content_role in export_content_roles(format)

  @spec source_type?(term()) :: boolean()
  def source_type?(source_type), do: source_type in @source_types

  @spec field_metadata(term(), term()) ::
          %{content_role: String.t(), vo_eligible: boolean()} | nil
  def field_metadata("flow_node", "text"), do: metadata("dialogue", true)
  def field_metadata("flow_node", "stage_directions"), do: metadata("stage_direction", false)
  def field_metadata("flow_node", "menu_text"), do: metadata("menu", false)
  def field_metadata("flow_node", "label"), do: metadata("exit", false)
  def field_metadata("block", "value.content"), do: metadata("runtime_value", false)
  def field_metadata("sheet", "name"), do: metadata("speaker_name", false)

  def field_metadata("flow_node", source_field) do
    case parse_response_field(source_field) do
      {:ok, _response_id} -> metadata("response", true)
      :error -> nil
    end
  end

  def field_metadata(_source_type, _source_field), do: nil

  @spec field?(term(), term()) :: boolean()
  def field?(source_type, source_field), do: not is_nil(field_metadata(source_type, source_field))

  @doc "Returns whether a block is exported as an engine variable."
  @spec exported_block?(map()) :: boolean()
  def exported_block?(%{is_constant: false, variable_name: variable_name} = block) when is_binary(variable_name),
    do: String.trim(variable_name) != "" and is_nil(Map.get(block, :deleted_at))

  def exported_block?(_block), do: false

  @doc "Returns whether an exported block contains player-facing text."
  @spec localizable_block?(map()) :: boolean()
  def localizable_block?(%{type: type} = block) when type in @localizable_block_types, do: exported_block?(block)

  def localizable_block?(_block), do: false

  @doc "Checks that a field belongs to the runtime semantics of its source entity."
  def localizable_source_field?("block", block, "value.content"), do: localizable_block?(block)

  def localizable_source_field?("sheet", %{deleted_at: nil}, "name"), do: true

  def localizable_source_field?("flow_node", %{type: "dialogue", data: data, deleted_at: nil}, source_field) do
    source_field in ["text", "stage_directions", "menu_text"] or response_field?(data, source_field)
  end

  def localizable_source_field?("flow_node", %{type: "exit", deleted_at: nil}, "label"), do: true
  def localizable_source_field?(_source_type, _source, _source_field), do: false

  defp response_field?(data, source_field) when is_map(data) do
    case parse_response_field(source_field) do
      {:ok, response_id} ->
        data
        |> Map.get("responses")
        |> response_list()
        |> Enum.any?(fn
          %{"id" => ^response_id} -> true
          _response -> false
        end)

      :error ->
        false
    end
  end

  defp response_field?(_data, _source_field), do: false

  defp response_list(responses) when is_list(responses), do: responses
  defp response_list(_responses), do: []

  defp parse_response_field("response." <> rest) do
    case String.split(rest, ".") do
      [response_id, "text"] ->
        if RuntimeKey.valid_response_id?(response_id), do: {:ok, response_id}, else: :error

      _parts ->
        :error
    end
  end

  defp parse_response_field(_source_field), do: :error

  defp metadata(content_role, vo_eligible) do
    %{content_role: content_role, vo_eligible: vo_eligible}
  end
end

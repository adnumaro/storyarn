defmodule Storyarn.Projects.LocalizationSourceContract do
  @moduledoc false

  alias Storyarn.Projects.LocalizationRuntimeKey

  @source_types ~w(flow_node block sheet)
  @content_roles ~w(dialogue stage_direction menu response exit runtime_value speaker_name)
  @localizable_flow_node_types ~w(dialogue exit)
  @localizable_block_types ~w(text rich_text)

  @engine_content_roles %{
    unity: @content_roles,
    ink: ~w(dialogue response),
    yarn: ~w(dialogue response),
    godot: ~w(dialogue response),
    unreal: ~w(dialogue stage_direction menu response runtime_value speaker_name),
    articy: ~w(dialogue stage_direction menu response runtime_value speaker_name)
  }

  def source_types, do: @source_types
  def content_roles, do: @content_roles
  def localizable_block_types, do: @localizable_block_types
  def localizable_flow_node_types, do: @localizable_flow_node_types
  def export_content_roles(format), do: Map.get(@engine_content_roles, format, [])
  def exported_content_role?(format, content_role), do: content_role in export_content_roles(format)
  def source_type?(source_type), do: source_type in @source_types

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
  def field?(source_type, source_field), do: not is_nil(field_metadata(source_type, source_field))

  def exported_block?(%{is_constant: false, variable_name: variable_name} = block) when is_binary(variable_name) do
    String.trim(variable_name) != "" and is_nil(Map.get(block, :deleted_at))
  end

  def exported_block?(_block), do: false

  def localizable_block?(%{type: type} = block) when type in @localizable_block_types, do: exported_block?(block)

  def localizable_block?(_block), do: false

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
        if LocalizationRuntimeKey.valid_response_id?(response_id), do: {:ok, response_id}, else: :error

      _parts ->
        :error
    end
  end

  defp parse_response_field(_source_field), do: :error
  defp metadata(content_role, vo_eligible), do: %{content_role: content_role, vo_eligible: vo_eligible}
end

defmodule Storyarn.Flows.Versioning.SourceContract do
  @moduledoc false

  alias Storyarn.Flows.RuntimeKey

  def field_metadata("flow_node", "text"), do: metadata("dialogue", true)
  def field_metadata("flow_node", "stage_directions"), do: metadata("stage_direction", false)
  def field_metadata("flow_node", "menu_text"), do: metadata("menu", false)
  def field_metadata("flow_node", "label"), do: metadata("exit", false)

  def field_metadata("flow_node", source_field) do
    case parse_response_field(source_field) do
      {:ok, _response_id} -> metadata("response", true)
      :error -> nil
    end
  end

  def field_metadata(_source_type, _source_field), do: nil

  def field?(source_type, source_field), do: not is_nil(field_metadata(source_type, source_field))

  def localizable_source_field?("flow_node", %{type: "dialogue", data: data, deleted_at: nil}, source_field) do
    source_field in ["text", "stage_directions", "menu_text"] or
      response_field?(data, source_field)
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

defmodule Storyarn.Flows.NodeTypes do
  @moduledoc """
  Owns the authored data contract for every editor node type.

  The web layer may decide how a node is presented or which panel opens, but
  defaults, form normalization and duplication semantics belong to Flows.
  """

  alias Storyarn.Flows.HubColors
  alias Storyarn.Flows.RuntimeKey

  @editor_types ~w(annotation condition dialogue entry exit hub instruction jump subflow)
  @user_addable_types @editor_types -- ~w(annotation entry)
  @default_exit_color "#22c55e"
  @hex_color_regex ~r/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/

  @dialogue_form_defaults %{
    "speaker_sheet_id" => "",
    "text" => "",
    "stage_directions" => "",
    "menu_text" => "",
    "audio_asset_id" => nil,
    "technical_id" => "",
    "localization_id" => "",
    "avatar_id" => nil,
    "responses" => []
  }

  @spec editor_types() :: [String.t()]
  def editor_types, do: @editor_types

  @spec user_addable_types() :: [String.t()]
  def user_addable_types, do: @user_addable_types

  @spec default_data(String.t()) :: map()
  def default_data("annotation") do
    %{"text" => "", "color" => "#fbbf24", "font_size" => "md"}
  end

  def default_data("condition") do
    %{"condition" => %{"logic" => "all", "rules" => []}, "switch_mode" => false}
  end

  def default_data("dialogue") do
    %{
      "speaker_sheet_id" => nil,
      "text" => "",
      "stage_directions" => "",
      "menu_text" => "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => RuntimeKey.new_dialogue_id(),
      "avatar_id" => nil,
      "responses" => []
    }
  end

  def default_data("entry"), do: %{}

  def default_data("exit") do
    %{
      "label" => "",
      "technical_id" => "",
      "outcome_tags" => [],
      "outcome_color" => @default_exit_color,
      "exit_mode" => "terminal",
      "referenced_flow_id" => nil,
      "target_type" => nil,
      "target_id" => nil
    }
  end

  def default_data("hub") do
    %{"hub_id" => "", "label" => "", "color" => HubColors.default_hex()}
  end

  def default_data("instruction"), do: %{"assignments" => [], "description" => ""}
  def default_data("jump"), do: %{"target_hub_id" => ""}
  def default_data("subflow"), do: %{"referenced_flow_id" => nil}
  def default_data(_type), do: %{}

  @spec form_data(String.t(), map()) :: map()
  def form_data("annotation", data) when is_map(data) do
    Map.take(data, ["text", "color", "font_size"])
  end

  def form_data("condition", data) when is_map(data) do
    %{
      "condition" => data["condition"] || %{"logic" => "all", "rules" => []},
      "switch_mode" => data["switch_mode"] || false
    }
  end

  def form_data("dialogue", data) when is_map(data) do
    Map.merge(@dialogue_form_defaults, Map.take(data, Map.keys(@dialogue_form_defaults)), fn
      _key, default, nil -> default
      _key, _default, value -> value
    end)
  end

  def form_data("entry", _data), do: %{}

  def form_data("exit", data) when is_map(data) do
    %{
      "label" => data["label"] || "",
      "technical_id" => data["technical_id"] || "",
      "outcome_tags" => normalize_outcome_tags(data["outcome_tags"]),
      "outcome_color" => normalize_hex_color(data["outcome_color"], @default_exit_color),
      "exit_mode" => normalize_exit_mode(data["exit_mode"]),
      "referenced_flow_id" => normalize_optional_id(data["referenced_flow_id"]),
      "target_type" => normalize_target_type(data["target_type"]),
      "target_id" => normalize_optional_id(data["target_id"])
    }
  end

  def form_data("hub", data) when is_map(data) do
    %{
      "hub_id" => data["hub_id"] || "",
      "label" => data["label"] || "",
      "color" => HubColors.resolve(data["color"])
    }
  end

  def form_data("instruction", data) when is_map(data) do
    %{
      "assignments" => data["assignments"] || [],
      "description" => data["description"] || ""
    }
  end

  def form_data("jump", data) when is_map(data) do
    %{"target_hub_id" => data["target_hub_id"] || ""}
  end

  def form_data("subflow", data) when is_map(data) do
    %{"referenced_flow_id" => data["referenced_flow_id"]}
  end

  def form_data(_type, _data), do: %{}

  @spec duplicate_data(String.t(), map()) :: map()
  def duplicate_data("dialogue", data) when is_map(data) do
    data
    |> Map.put("technical_id", "")
    |> Map.put("localization_id", RuntimeKey.new_dialogue_id())
  end

  def duplicate_data("exit", data) when is_map(data), do: Map.put(data, "technical_id", "")
  def duplicate_data("hub", data) when is_map(data), do: Map.put(data, "hub_id", "")
  def duplicate_data(_type, data), do: data

  defp normalize_outcome_tags(tags) when is_list(tags), do: tags

  defp normalize_outcome_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&normalize_outcome_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_outcome_tags(_tags), do: []

  defp normalize_outcome_tag(tag) do
    tag
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
  end

  defp normalize_hex_color(color, default) when is_binary(color) do
    if Regex.match?(@hex_color_regex, color), do: color, else: default
  end

  defp normalize_hex_color(_color, default), do: default

  defp normalize_exit_mode(mode) when mode in ~w(terminal flow_reference caller_return), do: mode
  defp normalize_exit_mode(_mode), do: "terminal"

  defp normalize_target_type(type) when type in ~w(scene flow), do: type
  defp normalize_target_type(_type), do: nil

  defp normalize_optional_id(nil), do: nil
  defp normalize_optional_id(""), do: nil
  defp normalize_optional_id(id) when is_integer(id), do: id

  defp normalize_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _invalid -> nil
    end
  end

  defp normalize_optional_id(_id), do: nil
end

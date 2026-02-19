defmodule StoryarnWeb.FlowLive.Player.Slide do
  @moduledoc """
  Pure function that builds a slide map from a node and engine state.

  A slide contains all the render data needed for one player screen:
  dialogue text, speaker info, responses, or outcome data.
  """

  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers
  alias StoryarnWeb.FlowLive.Helpers.HtmlSanitizer

  @doc """
  Build a slide from the current engine state and node.

  Returns a map with `:type` and type-specific fields.
  """
  @spec build(map() | nil, map(), map(), integer()) :: map()
  def build(nil, _state, _sheets_map, _project_id) do
    %{type: :empty}
  end

  def build(%{type: "dialogue"} = node, state, sheets_map, _project_id) do
    data = node.data || %{}
    speaker = resolve_speaker(data["speaker_sheet_id"], sheets_map)
    text = interpolate_variables(HtmlSanitizer.sanitize_html(data["text"] || ""), state.variables)
    stage_directions = data["stage_directions"] || ""
    menu_text = data["menu_text"] || ""

    responses =
      case state.pending_choices do
        %{responses: resps} when is_list(resps) ->
          Enum.with_index(resps, 1)
          |> Enum.map(fn {resp, idx} ->
            %{
              id: resp.id,
              text: resp.text || "",
              valid: resp.valid,
              number: idx,
              has_condition: resp[:rule_details] != nil and resp[:rule_details] != []
            }
          end)

        _ ->
          []
      end

    %{
      type: :dialogue,
      speaker_name: speaker.name,
      speaker_initials: speaker.initials,
      speaker_color: speaker.color,
      text: text,
      stage_directions: stage_directions,
      menu_text: menu_text,
      responses: responses,
      node_id: node.id
    }
  end

  def build(%{type: "exit"} = node, state, _sheets_map, _project_id) do
    data = node.data || %{}

    variables_changed =
      state.variables
      |> Enum.count(fn {_key, %{value: v, initial_value: iv}} -> v != iv end)

    choices_made =
      state.console
      |> Enum.count(fn entry -> String.starts_with?(entry.message, "Selected:") end)

    %{
      type: :outcome,
      label: data["label"] || EvalHelpers.strip_html(data["text"]) || "The End",
      outcome_color: data["outcome_color"],
      outcome_tags: data["outcome_tags"] || [],
      step_count: state.step_count,
      variables_changed: variables_changed,
      choices_made: choices_made,
      node_id: node.id
    }
  end

  def build(%{type: "scene"} = node, state, sheets_map, _project_id) do
    data = node.data || %{}
    location = resolve_speaker(data["location_sheet_id"], sheets_map)
    description = interpolate_variables(HtmlSanitizer.sanitize_html(data["description"] || ""), state.variables)

    %{
      type: :scene,
      setting: data["setting"] || "INT",
      location_name: location.name || data["location_name"] || "",
      sub_location: data["sub_location"] || "",
      time_of_day: data["time_of_day"] || "",
      description: description,
      node_id: node.id
    }
  end

  def build(_node, _state, _sheets_map, _project_id) do
    %{type: :empty}
  end

  # ===========================================================================
  # Speaker resolution
  # ===========================================================================

  defp resolve_speaker(sheet_id, sheets_map) when is_integer(sheet_id) or is_binary(sheet_id) do
    id = parse_sheet_id(sheet_id)

    case Map.get(sheets_map, to_string(id)) do
      nil -> %{name: nil, initials: "?", color: nil}
      info -> %{name: info.name, initials: speaker_initials(info.name), color: info[:color]}
    end
  end

  defp resolve_speaker(_, _sheets_map), do: %{name: nil, initials: "?", color: nil}

  defp parse_sheet_id(id) when is_integer(id), do: id

  defp parse_sheet_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_sheet_id(_), do: nil

  defp speaker_initials(nil), do: "?"

  defp speaker_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "?"
      initials -> initials
    end
  end

  # ===========================================================================
  # Variable interpolation
  # ===========================================================================

  defp interpolate_variables("", _variables), do: ""

  defp interpolate_variables(text, variables) when is_binary(text) do
    Regex.replace(~r/\{([a-zA-Z0-9_.]+)\}/, text, fn _full, ref ->
      case Map.get(variables, ref) do
        %{value: val} ->
          "<span class=\"player-var\">#{format_value(val)}</span>"

        nil ->
          "<span class=\"player-var-unknown\">[#{ref}]</span>"
      end
    end)
  end

  defp format_value(nil), do: "nil"
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(val) when is_list(val), do: Enum.join(val, ", ")
  defp format_value(val) when is_binary(val), do: Phoenix.HTML.html_escape(val) |> Phoenix.HTML.safe_to_string()
  defp format_value(val), do: to_string(val)
end

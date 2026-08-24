defmodule StoryarnWeb.FlowLive.Player.Slide do
  @moduledoc """
  Pure function that builds a slide map from a node and engine state.

  A slide contains all the render data needed for one player screen:
  dialogue text, speaker info, responses, or outcome data.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows
  alias Storyarn.Platform.Shared.HtmlSanitizer

  @doc """
  Build a slide from the current engine state and node.

  Returns a map with `:type` and type-specific fields.
  """
  @spec build(map() | nil, map(), map(), integer()) :: map()
  def build(nil, _state, _speakers_map, _project_id) do
    %{type: :empty}
  end

  def build(%{type: "dialogue"} = node, state, speakers_map, _project_id) do
    data = node.data || %{}
    speaker_info = resolve_speaker_info(data["speaker_sheet_id"], speakers_map)
    speaker = build_speaker(speaker_info)
    avatar_url = resolve_avatar_url(data["avatar_id"], speaker_info, speaker)

    text =
      (data["text"] || "")
      |> HtmlSanitizer.sanitize_html()
      |> Flows.interpolate_player_rich_text(state.variables, &render_variable_resolution/1)

    stage_directions = data["stage_directions"] || ""
    menu_text = data["menu_text"] || ""

    responses =
      case state.pending_choices do
        %{responses: resps} when is_list(resps) ->
          resps
          |> Enum.with_index(1)
          |> Enum.map(fn {resp, idx} ->
            %{
              id: resp.id,
              text: Flows.interpolate_player_response_text(resp.text || "", state.variables),
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
      speaker_avatar_url: avatar_url,
      text: text,
      stage_directions: stage_directions,
      menu_text: menu_text,
      responses: responses,
      node_id: node.id
    }
  end

  def build(%{type: "exit"} = node, state, _speakers_map, _project_id) do
    node
    |> Flows.build_player_outcome(state)
    |> Map.put(:type, :outcome)
    |> Map.update!(:label, &(&1 || dgettext("flows", "The End")))
  end

  def build(_node, _state, _speakers_map, _project_id) do
    %{type: :empty}
  end

  # ===========================================================================
  # Speaker resolution
  # ===========================================================================

  defp resolve_speaker_info(speaker_id, speakers_map) when is_integer(speaker_id) or is_binary(speaker_id) do
    id = parse_speaker_id(speaker_id)
    Map.get(speakers_map, to_string(id))
  end

  defp resolve_speaker_info(_, _), do: nil

  defp build_speaker(nil), do: %{name: nil, initials: "?", color: nil, avatar_url: nil}

  defp build_speaker(info) do
    %{
      name: info.name,
      initials: speaker_initials(info.name),
      color: info[:color],
      avatar_url: info[:avatar_url]
    }
  end

  defp resolve_avatar_url(avatar_id, speaker_info, speaker) when not is_nil(avatar_id) do
    avatars = (speaker_info && speaker_info[:avatars]) || []

    case Enum.find(avatars, &(&1.id == avatar_id)) do
      %{url: url} -> url
      _ -> speaker.avatar_url
    end
  end

  defp resolve_avatar_url(_, _, speaker), do: speaker.avatar_url

  defp parse_speaker_id(id) when is_integer(id), do: id

  defp parse_speaker_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_speaker_id(_), do: nil

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

  defp render_variable_resolution({:value, _ref, value}) do
    "<span class=\"player-var\">#{escape(Flows.format_player_value(value))}</span>"
  end

  defp render_variable_resolution({:missing, ref}) do
    "<span class=\"player-var-unknown\">[#{escape(ref)}]</span>"
  end

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end

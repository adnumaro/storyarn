defmodule StoryarnWeb.FlowLive.Helpers.DialogueLocalization do
  @moduledoc """
  Resolves localized narrative content and dialogue voice for one Flow node.

  Source-language content comes from the node and speaker projection. Target
  content comes from Flow-owned projections of Localization rows and always
  reports explicit fallback and stale state. Voice assets are resolved through
  the Flow facade so deleted, foreign, or non-audio assets never reach the player.
  """

  alias Storyarn.Flows
  alias StoryarnWeb.PrivateMedia

  @playable_voice_statuses ~w(recorded approved)

  @type result :: %{
          content: map(),
          localization: map(),
          voice: map()
        }

  @doc "Resolves one dialogue for the selected project content locale."
  @spec resolve(map(), map(), integer(), String.t() | nil, String.t() | nil) :: result()
  def resolve(%{type: "dialogue"} = node, speakers_map, project_id, source_locale, content_locale)
      when is_map(speakers_map) and is_integer(project_id) do
    data = node.data || %{}
    source_locale = normalize_locale(source_locale)
    content_locale = normalize_locale(content_locale) || source_locale
    speaker = speaker_info(data["speaker_sheet_id"], speakers_map)

    if is_nil(content_locale) or content_locale == source_locale do
      source_result(node.id, data, speaker, project_id, content_locale, source_locale)
    else
      target_result(node.id, data, speaker, project_id, content_locale, source_locale)
    end
  end

  defp source_result(node_id, data, speaker, project_id, locale, source_locale) do
    response_texts = source_response_texts(data)
    fields = source_field_metadata(data, speaker, response_texts)

    %{
      content: %{
        text: string_value(data["text"]),
        stage_directions: string_value(data["stage_directions"]),
        menu_text: string_value(data["menu_text"]),
        response_texts: response_texts,
        speaker_name: value(speaker, :name)
      },
      localization: %{
        locale: locale,
        sourceLocale: source_locale,
        isSource: true,
        status: "source",
        stale: false,
        fallback: false,
        fields: fields
      },
      voice: source_voice(node_id, data, project_id, locale)
    }
  end

  defp target_result(node_id, data, speaker, project_id, locale, source_locale) do
    rows = Flows.get_localized_texts_for_source("flow_node", node_id)
    rows_by_field = rows_by_field(rows, locale)

    {text, text_meta, text_row} = target_field(data["text"], rows_by_field["text"])

    {stage_directions, stage_meta, _stage_row} =
      target_field(data["stage_directions"], rows_by_field["stage_directions"])

    {menu_text, menu_meta, _menu_row} = target_field(data["menu_text"], rows_by_field["menu_text"])

    {response_texts, response_meta} = target_responses(data, rows_by_field)
    {speaker_name, speaker_meta} = target_speaker(data["speaker_sheet_id"], speaker, locale)

    field_metadata = %{
      text: text_meta,
      stageDirections: stage_meta,
      menuText: menu_meta,
      speakerName: speaker_meta,
      responses: response_meta
    }

    flat_metadata = [text_meta, stage_meta, menu_meta, speaker_meta] ++ Map.values(response_meta)

    %{
      content: %{
        text: text,
        stage_directions: stage_directions,
        menu_text: menu_text,
        response_texts: response_texts,
        speaker_name: speaker_name
      },
      localization: %{
        locale: locale,
        sourceLocale: source_locale,
        isSource: false,
        status: text_meta.status,
        stale: Enum.any?(flat_metadata, & &1.stale),
        fallback: Enum.any?(flat_metadata, & &1.fallback),
        fields: field_metadata
      },
      voice: target_voice(node_id, text_row, project_id, locale)
    }
  end

  defp source_field_metadata(data, speaker, response_texts) do
    %{
      text: source_field_meta(data["text"]),
      stageDirections: source_field_meta(data["stage_directions"]),
      menuText: source_field_meta(data["menu_text"]),
      speakerName: source_field_meta(value(speaker, :name)),
      responses: Map.new(response_texts, fn {id, text} -> {id, source_field_meta(text)} end)
    }
  end

  defp source_field_meta(value) do
    %{
      status: if(present?(value), do: "source", else: "empty"),
      stale: false,
      fallback: false
    }
  end

  defp target_field(source_value, row) do
    source_value = string_value(source_value)

    if row && present?(row.translated_text) do
      {row.translated_text, %{status: row.status, stale: row.stale, fallback: false}, row}
    else
      status = target_field_status(row, source_value)
      {source_value, %{status: status, stale: false, fallback: present?(source_value)}, row}
    end
  end

  defp target_field_status(%{} = row, _source_value), do: row.status

  defp target_field_status(_row, source_value) do
    if present?(source_value), do: "missing", else: "empty"
  end

  defp target_responses(data, rows_by_field) do
    data
    |> response_list()
    |> Enum.reduce({%{}, %{}}, fn response, {texts, metadata} ->
      response_id = value(response, :id)

      if is_binary(response_id) do
        field = "response.#{response_id}.text"
        {text, meta, _row} = target_field(value(response, :text), rows_by_field[field])
        {Map.put(texts, response_id, text), Map.put(metadata, response_id, meta)}
      else
        {texts, metadata}
      end
    end)
  end

  defp target_speaker(speaker_id, speaker, locale) do
    source_name = value(speaker, :name)

    case normalize_id(speaker_id) do
      nil ->
        {source_name, %{status: "empty", stale: false, fallback: false}}

      speaker_id ->
        "sheet"
        |> Flows.get_localized_text_by_source(speaker_id, "name", locale)
        |> then(&target_field(source_name, &1))
        |> then(fn {name, metadata, _row} -> {name, metadata} end)
    end
  end

  defp source_voice(node_id, data, project_id, locale) do
    asset_id = normalize_id(data["audio_asset_id"])
    asset = audio_asset(project_id, asset_id)
    status = if asset, do: "recorded", else: "none"
    voice(node_id, locale, status, false, asset_id, asset)
  end

  defp target_voice(node_id, row, project_id, locale) do
    status = if row, do: row.vo_status || "none", else: "none"
    stale = row && row.stale
    asset_id = row && row.vo_asset_id

    asset =
      if status in @playable_voice_statuses and stale != true,
        do: audio_asset(project_id, asset_id)

    voice(node_id, locale, status, stale == true, asset_id, asset)
  end

  defp voice(node_id, locale, status, stale, asset_id, asset) do
    identity = "dialogue-voice:#{node_id}:#{locale || "source"}"

    %{
      id: identity,
      continuityKey: "#{identity}:#{value(asset, :id) || "none"}",
      nodeId: node_id,
      locale: locale,
      localeCode: locale,
      status: status,
      stale: stale,
      available: not is_nil(asset),
      assetId: asset_id,
      url: asset && PrivateMedia.asset_url(asset),
      volume: 1.0,
      contentType: value(asset, :content_type),
      filename: value(asset, :filename)
    }
  end

  defp audio_asset(_project_id, nil), do: nil

  defp audio_asset(project_id, asset_id) do
    project_id
    |> Flows.initial_asset_options("audio", [asset_id])
    |> Enum.find(&(value(&1, :id) == asset_id))
  end

  defp rows_by_field(rows, locale) do
    rows
    |> Enum.filter(&(normalize_locale(&1.locale_code) == locale))
    |> Map.new(&{&1.source_field, &1})
  end

  defp source_response_texts(data) do
    data
    |> response_list()
    |> Enum.reduce(%{}, fn response, texts ->
      case value(response, :id) do
        id when is_binary(id) -> Map.put(texts, id, string_value(value(response, :text)))
        _missing_id -> texts
      end
    end)
  end

  defp response_list(%{} = data), do: response_list(value(data, :responses))
  defp response_list(responses) when is_list(responses), do: responses
  defp response_list(_responses), do: []

  defp speaker_info(speaker_id, speakers_map) do
    case normalize_id(speaker_id) do
      nil -> nil
      id -> Map.get(speakers_map, to_string(id)) || Map.get(speakers_map, id)
    end
  end

  defp normalize_id(id) when is_integer(id) and id > 0, do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> parsed
      _invalid -> nil
    end
  end

  defp normalize_id(_id), do: nil

  defp normalize_locale(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> String.replace("_", "-")
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_locale(_locale), do: nil

  defp string_value(value) when is_binary(value), do: value
  defp string_value(_value), do: ""

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp value(container, key, default \\ nil)
  defp value(nil, _key, default), do: default

  defp value(container, key, default) when is_map(container) do
    Map.get(container, key, Map.get(container, Atom.to_string(key), default))
  end
end

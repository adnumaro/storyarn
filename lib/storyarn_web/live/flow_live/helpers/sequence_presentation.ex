defmodule StoryarnWeb.FlowLive.Helpers.SequencePresentation do
  @moduledoc """
  Serializes one resolved Flow composition for the editor and Player.

  Composition rules stay in `Storyarn.Flows`; this presentation adapter only
  resolves media URLs and shapes the shared Vue contract.
  """

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.DialogueLocalization
  alias StoryarnWeb.FlowLive.Player.Slide
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.PrivateMedia

  @structural_diagnostic_codes ~w(
    composition_cycle
    invalid_composition_source
    missing_composition_source
  )
  @composition_types ~w(sequence dialogue)

  @doc "Returns the empty editor-stage projection."
  @spec empty_stage() :: map()
  def empty_stage, do: %{status: "empty"}

  @doc "Builds the shared Sequence-stage projection for one composition owner."
  @spec stage(integer() | nil, map(), map(), integer(), map() | nil, map() | nil) :: map()
  def stage(node_id, nodes, speakers_map, project_id, state \\ nil, locale_context \\ nil)

  def stage(node_id, nodes, speakers_map, project_id, state, locale_context)
      when is_integer(node_id) and is_map(nodes) and is_map(speakers_map) do
    node = Map.get(nodes, node_id) || Map.get(nodes, to_string(node_id))

    if value(node, :type) in @composition_types,
      do: do_stage(node, nodes, speakers_map, project_id, state, locale_context),
      else: empty_stage()
  end

  def stage(_node_id, _nodes, _speakers_map, _project_id, _state, _locale_context), do: empty_stage()

  @doc "Builds the content-locale state shared by Flow editor and Player."
  @spec locale_state([map()], map() | nil, String.t() | nil) :: map()
  def locale_state(languages, source_language, preferred_locale \\ nil) when is_list(languages) do
    source_locale = normalize_locale(value(source_language, :locale_code))
    available_locales = Enum.map(languages, &normalize_locale(value(&1, :locale_code)))
    preferred_locale = normalize_locale(preferred_locale)

    content_locale =
      if preferred_locale in available_locales,
        do: preferred_locale,
        else: source_locale || List.first(available_locales)

    %{
      languages: languages,
      source_language: source_language,
      source_locale: source_locale,
      content_locale: content_locale,
      language_options:
        Enum.map(languages, fn language ->
          LanguagePickerOption.from_code(value(language, :locale_code), label: value(language, :name))
        end)
    }
  end

  @doc "Validates a requested content locale against the project's active languages."
  @spec select_content_locale(String.t(), [map()]) :: {:ok, String.t()} | :error
  def select_content_locale(locale, languages) when is_binary(locale) and is_list(languages) do
    normalized = normalize_locale(locale)

    if Enum.any?(languages, &(normalize_locale(value(&1, :locale_code)) == normalized)),
      do: {:ok, normalized},
      else: :error
  end

  def select_content_locale(_locale, _languages), do: :error

  @doc "Extracts the localization arguments accepted by `stage/6` and `slide/5`."
  @spec locale_context(map()) :: map()
  def locale_context(assigns) when is_map(assigns) do
    %{
      source_locale: value(assigns, :source_locale),
      content_locale: value(assigns, :content_locale),
      language_options: value(assigns, :language_options, [])
    }
  end

  @doc "Builds one player slide and its localization and voice metadata."
  @spec slide(map() | nil, map(), map(), integer(), map() | nil) :: map()
  def slide(node, state, speakers_map, project_id, locale_context \\ nil)

  def slide(%{type: "dialogue"} = node, state, speakers_map, project_id, locale_context) do
    resolved =
      DialogueLocalization.resolve(
        node,
        speakers_map,
        project_id,
        value(locale_context, :source_locale),
        value(locale_context, :content_locale)
      )

    %{
      slide: Slide.build(node, state, speakers_map, project_id, resolved.content),
      localization: resolved.localization,
      voice: resolved.voice
    }
  end

  def slide(node, state, speakers_map, project_id, _locale_context) do
    %{slide: Slide.build(node, state, speakers_map, project_id), localization: nil, voice: nil}
  end

  @doc "Serializes effective visual layers from a resolved composition."
  @spec visual_layers(map(), integer() | nil) :: [map()]
  def visual_layers(composition, selected_node_id \\ nil) when is_map(composition) do
    composition
    |> value(:visual_layers, [])
    |> Enum.flat_map(&serialize_visual_layer(&1, selected_node_id, false))
  end

  @doc "Serializes effective visual layers for an editor inspector, including missing assets."
  @spec inspectable_visual_layers(map(), integer() | nil) :: [map()]
  def inspectable_visual_layers(composition, selected_node_id \\ nil) when is_map(composition) do
    composition
    |> value(:visual_layers, [])
    |> Enum.flat_map(&serialize_visual_layer(&1, selected_node_id, true))
  end

  @doc "Serializes effective visual tombstones for the editor inspector."
  @spec inspectable_removed_visual_layers(map(), integer() | nil) :: [map()]
  def inspectable_removed_visual_layers(composition, selected_node_id \\ nil) when is_map(composition) do
    composition
    |> value(:removed_visual_layers, [])
    |> Enum.flat_map(&serialize_visual_layer(&1, selected_node_id, true))
  end

  @doc "Serializes effective audio tracks with stable continuity identities."
  @spec audio_tracks(map()) :: [map()]
  def audio_tracks(composition) when is_map(composition) do
    composition
    |> value(:audio_tracks, [])
    |> Enum.flat_map(&serialize_audio_track(&1, false))
  end

  @doc "Serializes effective audio tracks for an editor inspector, including missing assets."
  @spec inspectable_audio_tracks(map()) :: [map()]
  def inspectable_audio_tracks(composition) when is_map(composition) do
    composition
    |> value(:audio_tracks, [])
    |> Enum.flat_map(&serialize_audio_track(&1, true))
  end

  @doc "Serializes effective audio tombstones for the editor inspector."
  @spec inspectable_removed_audio_tracks(map()) :: [map()]
  def inspectable_removed_audio_tracks(composition) when is_map(composition) do
    composition
    |> value(:removed_audio_tracks, [])
    |> Enum.flat_map(&serialize_audio_track(&1, true))
  end

  @doc "Serializes resolver diagnostics for Vue surfaces."
  @spec diagnostics(map()) :: [map()]
  def diagnostics(composition) when is_map(composition) do
    composition
    |> value(:diagnostics, [])
    |> Enum.map(fn diagnostic ->
      code = value(diagnostic, :code, "composition_error")

      %{
        code: code,
        nodeId: value(diagnostic, :node_id),
        severity: if(code in @structural_diagnostic_codes, do: "error", else: "warning")
      }
    end)
  end

  defp do_stage(node, nodes, speakers_map, project_id, state, locale_context) do
    node_id = value(node, :id)
    state = normalize_state(state, node_id)
    presentation = slide(node, state, speakers_map, project_id, locale_context)
    composition = Flows.compose_player_sequences(state, nodes)
    serialized_diagnostics = diagnostics(composition)

    intervention =
      serialize_intervention(
        presentation.slide,
        node_id,
        presentation.localization,
        presentation.voice
      )

    base = %{
      owner: %{
        nodeId: node_id,
        type: value(node, :type),
        compositionSourceId: value(node, :composition_source_id)
      },
      intervention: intervention,
      voice: presentation.voice,
      localizationStatus: presentation.localization,
      composition: %{
        layers: visual_layers(composition, node_id),
        audioTracks: audio_tracks(composition),
        diagnostics: serialized_diagnostics
      }
    }

    base = put_locale_contract(base, locale_context)

    if Enum.any?(serialized_diagnostics, &(&1.severity == "error")) do
      Map.put(base, :status, "error")
    else
      Map.put(base, :status, "ready")
    end
  end

  defp serialize_intervention(%{type: :empty}, _node_id, _localization, _voice), do: nil

  defp serialize_intervention(slide, node_id, localization, voice) do
    %{
      nodeId: node_id,
      speakerName: slide[:speaker_name],
      speakerInitials: slide[:speaker_initials] || "?",
      speakerAvatarUrl: slide[:speaker_avatar_url],
      speakerColor: slide[:speaker_color],
      text: slide[:text] || "",
      stageDirections: slide[:stage_directions] || "",
      localization: localization,
      voice: voice
    }
  end

  defp put_locale_contract(base, locale_context) when is_map(locale_context) do
    base
    |> Map.put(:contentLocale, value(locale_context, :content_locale))
    |> Map.put(:sourceLocale, value(locale_context, :source_locale))
    |> Map.put(:languageOptions, value(locale_context, :language_options, []))
  end

  defp put_locale_contract(base, _locale_context), do: base

  defp normalize_state(%{} = state, node_id) do
    state
    |> Map.put(:current_node_id, node_id)
    |> Map.put_new(:variables, %{})
    |> Map.put_new(:pending_choices, nil)
  end

  defp normalize_state(_state, node_id) do
    %{current_node_id: node_id, variables: %{}, pending_choices: nil}
  end

  defp serialize_visual_layer(composed, selected_node_id, include_missing?) do
    layer = value(composed, :item, %{})
    url = media_url(layer)

    if include_missing? or (is_binary(url) and url != "") do
      definition_owner_id = value(composed, :sequence_id)
      layer_key = value(composed, :layer_key) || value(layer, :layer_key) || value(layer, :id)

      [
        %{
          id: layer_key,
          key: layer_key,
          rowId: value(layer, :id),
          asset_id: value(layer, :asset_id),
          assetId: value(layer, :asset_id),
          sequenceId: definition_owner_id,
          sequenceDepth: value(composed, :depth, 0),
          kind: value(layer, :kind, "prop"),
          label: value(layer, :label),
          url: url || "",
          zIndex: value(layer, :z_index, 0),
          slot: value(layer, :slot),
          x: value(layer, :x, 0.0),
          y: value(layer, :y, 0.0),
          width: value(layer, :width, 1.0),
          height: value(layer, :height, 1.0),
          anchorX: value(layer, :anchor_x, 0.0),
          anchorY: value(layer, :anchor_y, 0.0),
          fit: value(layer, :fit, "contain"),
          opacity: value(layer, :opacity, 1.0),
          visible: value(layer, :visible, true),
          removed: value(composed, :removed, false),
          origin: origin(definition_owner_id, selected_node_id),
          propertyOrigins:
            composed
            |> value(:property_sources, %{})
            |> Map.new(fn {field, owner_id} ->
              {to_string(field), origin(owner_id, selected_node_id)}
            end)
        }
      ]
    else
      []
    end
  end

  defp serialize_audio_track(composed, include_missing?) do
    track = value(composed, :item, %{})
    url = media_url(track)

    if include_missing? or (is_binary(url) and url != "") do
      [audio_track_payload(composed, track, url)]
    else
      []
    end
  end

  defp audio_track_payload(composed, track, url) do
    asset = value(track, :asset)
    track_key = value(composed, :track_key) || value(track, :track_key) || value(track, :id)
    continuity_key = value(composed, :continuity_key) || track_key

    %{
      id: continuity_key,
      continuityKey: continuity_key,
      trackKey: track_key,
      asset_id: value(track, :asset_id),
      assetId: value(track, :asset_id),
      sequenceId: value(composed, :sequence_id),
      isOverride: value(track, :is_override, false),
      kind: value(track, :kind, "ambience"),
      position: value(track, :position, 0),
      url: url || "",
      volume: serialize_volume(value(track, :volume)),
      contentType: value(track, :content_type) || value(asset, :content_type),
      filename: value(track, :filename) || value(asset, :filename),
      depth: value(composed, :depth, 0),
      removed: value(composed, :removed, false),
      propertyOrigins:
        composed
        |> value(:property_sources, %{})
        |> Map.new(fn {field, owner_id} -> {to_string(field), %{nodeId: owner_id}} end)
    }
  end

  defp origin(owner_id, selected_node_id) do
    %{nodeId: owner_id, sequenceId: owner_id, inherited: owner_id != selected_node_id}
  end

  defp media_url(item) do
    value(item, :url) || PrivateMedia.asset_url(value(item, :asset))
  end

  defp serialize_volume(nil), do: 1.0
  defp serialize_volume(%Decimal{} = volume), do: Decimal.to_float(volume)
  defp serialize_volume(volume) when is_number(volume), do: volume
  defp serialize_volume(_volume), do: 1.0

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

  defp value(container, key, default \\ nil)
  defp value(nil, _key, default), do: default

  defp value(container, key, default) when is_map(container) do
    Map.get(container, key, Map.get(container, Atom.to_string(key), default))
  end
end

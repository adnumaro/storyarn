defmodule StoryarnWeb.FlowLive.Helpers.SequencePresentation do
  @moduledoc """
  Serializes one resolved Flow composition for the editor and Player.

  Composition rules stay in `Storyarn.Flows`; this presentation adapter only
  resolves media URLs and shapes the shared Vue contract.
  """

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Player.Slide
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
  @spec stage(integer() | nil, map(), map(), integer(), map() | nil) :: map()
  def stage(node_id, nodes, speakers_map, project_id, state \\ nil)

  def stage(node_id, nodes, speakers_map, project_id, state)
      when is_integer(node_id) and is_map(nodes) and is_map(speakers_map) do
    node = Map.get(nodes, node_id) || Map.get(nodes, to_string(node_id))

    if value(node, :type) in @composition_types,
      do: do_stage(node, nodes, speakers_map, project_id, state),
      else: empty_stage()
  end

  def stage(_node_id, _nodes, _speakers_map, _project_id, _state), do: empty_stage()

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

  defp do_stage(node, nodes, speakers_map, project_id, state) do
    node_id = value(node, :id)
    state = normalize_state(state, node_id)
    slide = Slide.build(node, state, speakers_map, project_id)
    composition = Flows.compose_player_sequences(state, nodes)
    serialized_diagnostics = diagnostics(composition)

    base = %{
      owner: %{
        nodeId: node_id,
        type: value(node, :type),
        compositionSourceId: value(node, :composition_source_id)
      },
      intervention: serialize_intervention(slide, node_id),
      composition: %{
        layers: visual_layers(composition, node_id),
        diagnostics: serialized_diagnostics
      }
    }

    if Enum.any?(serialized_diagnostics, &(&1.severity == "error")) do
      Map.put(base, :status, "error")
    else
      Map.put(base, :status, "ready")
    end
  end

  defp serialize_intervention(%{type: :empty}, _node_id), do: nil

  defp serialize_intervention(slide, node_id) do
    %{
      nodeId: node_id,
      speakerName: slide[:speaker_name],
      speakerInitials: slide[:speaker_initials] || "?",
      speakerAvatarUrl: slide[:speaker_avatar_url],
      speakerColor: slide[:speaker_color],
      text: slide[:text] || "",
      stageDirections: slide[:stage_directions] || ""
    }
  end

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

  defp origin(owner_id, selected_node_id) do
    %{nodeId: owner_id, sequenceId: owner_id, inherited: owner_id != selected_node_id}
  end

  defp media_url(item) do
    value(item, :url) || PrivateMedia.asset_url(value(item, :asset))
  end

  defp value(container, key, default \\ nil)
  defp value(nil, _key, default), do: default

  defp value(container, key, default) when is_map(container) do
    Map.get(container, key, Map.get(container, Atom.to_string(key), default))
  end
end

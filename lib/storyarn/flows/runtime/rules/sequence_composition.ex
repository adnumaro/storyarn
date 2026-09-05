defmodule Storyarn.Flows.SequenceComposition do
  @moduledoc """
  Resolves deterministic static composition through an explicit source chain.

  Maps produced before `composition_source_id` existed retain their structural
  `parent_id` behavior. Persisted nodes always use the explicit field.
  """

  @layer_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)
  @track_fields ~w(position asset_id start_time end_time volume)
  @composition_types ~w(sequence dialogue)

  @type diagnostic :: %{code: String.t(), node_id: integer() | nil}
  @type composed_item :: %{
          optional(:layer_key) => String.t(),
          optional(:track_key) => String.t(),
          optional(:asset_source_row_id) => integer() | nil,
          optional(:continuity_key) => String.t(),
          item: map(),
          sequence_id: integer(),
          owner_node_id: integer(),
          depth: non_neg_integer(),
          property_sources: %{optional(String.t()) => integer()}
        }
  @type t :: %{
          visual_layers: [composed_item()],
          audio_tracks: [composed_item()],
          diagnostics: [diagnostic()]
        }

  @type inspection :: %{
          visual_layers: [composed_item()],
          removed_visual_layers: [composed_item()],
          audio_tracks: [composed_item()],
          removed_audio_tracks: [composed_item()],
          diagnostics: [diagnostic()]
        }

  @doc "Composes the explicit source chain for the current player node."
  @spec compose(map(), map()) :: t()
  def compose(state, nodes) when is_map(state) and is_map(nodes), do: compose_node(value(state, :current_node_id), nodes)

  def compose(_state, _nodes), do: empty()

  @doc "Composes any selected node without constructing evaluator state."
  @spec compose_node(integer() | map() | nil, map()) :: t()
  def compose_node(node_or_id, nodes) when is_map(nodes) do
    node_or_id
    |> compose_node_with_removed(nodes)
    |> Map.take([:visual_layers, :audio_tracks, :diagnostics])
  end

  def compose_node(_node_or_id, _nodes), do: empty()

  @doc "Composes a selected node and retains effective tombstones for editor inspection."
  @spec compose_node_with_removed(integer() | map() | nil, map()) :: inspection()
  def compose_node_with_removed(node_or_id, nodes) when is_map(nodes) do
    case resolve_node(node_or_id, nodes) do
      nil ->
        inspection_empty()

      node ->
        {chain, source_diagnostics} = composition_chain(node, nodes)
        {visual_layers, removed_visual_layers, layer_diagnostics} = compose_visual_layers(chain)
        {audio_tracks, removed_audio_tracks, track_diagnostics} = compose_audio_tracks(chain)

        %{
          visual_layers: visual_layers,
          removed_visual_layers: removed_visual_layers,
          audio_tracks: audio_tracks,
          removed_audio_tracks: removed_audio_tracks,
          diagnostics: source_diagnostics ++ layer_diagnostics ++ track_diagnostics
        }
    end
  end

  def compose_node_with_removed(_node_or_id, _nodes), do: inspection_empty()

  defp empty, do: %{visual_layers: [], audio_tracks: [], diagnostics: []}

  defp inspection_empty do
    %{
      visual_layers: [],
      removed_visual_layers: [],
      audio_tracks: [],
      removed_audio_tracks: [],
      diagnostics: []
    }
  end

  defp resolve_node(%{} = node, _nodes), do: node
  defp resolve_node(node_id, nodes) when is_integer(node_id), do: Map.get(nodes, node_id)
  defp resolve_node(_node_or_id, _nodes), do: nil

  defp composition_chain(node, nodes) do
    result =
      if composition_owner?(node) do
        walk_source(node, nodes, MapSet.new(), [])
      else
        case value(node, :parent_id) do
          nil -> {[], []}
          parent_id -> walk_source_id(parent_id, nodes, MapSet.new(), [])
        end
      end

    case result do
      {_partial_chain, [_ | _] = diagnostics} -> {[], diagnostics}
      {chain, []} -> {chain, []}
    end
  end

  defp walk_source(node, nodes, visited, acc) do
    node_id = value(node, :id)

    cond do
      MapSet.member?(visited, node_id) ->
        {acc, [%{code: "composition_cycle", node_id: node_id}]}

      not composition_owner?(node) ->
        {acc, [%{code: "invalid_composition_source", node_id: node_id}]}

      true ->
        visited = MapSet.put(visited, node_id)
        acc = [node | acc]

        case source_id(node) do
          nil -> {acc, []}
          source_id -> walk_source_id(source_id, nodes, visited, acc)
        end
    end
  end

  defp walk_source_id(source_id, nodes, visited, acc) do
    case Map.get(nodes, source_id) do
      nil -> {acc, [%{code: "missing_composition_source", node_id: source_id}]}
      source -> walk_source(source, nodes, visited, acc)
    end
  end

  defp source_id(node) do
    if has_key?(node, :composition_source_id),
      do: value(node, :composition_source_id),
      else: value(node, :parent_id)
  end

  defp composition_owner?(node), do: value(node, :type) in @composition_types

  defp compose_visual_layers(chain) do
    {by_key, diagnostics} =
      reduce_rows(chain, :sequence_visual_layers, fn row, owner, depth, {items, warnings} ->
        key = logical_key(row, :layer_key, "legacy-layer")
        fields = override_fields(row, @layer_fields)
        existing = Map.get(items, key)

        if missing_inherited_definition?(existing, fields, @layer_fields) do
          warning = %{code: "missing_inherited_layer", node_id: value(owner, :id)}
          {items, [warning | warnings]}
        else
          merged = merge_item(existing, row, owner, depth, key, fields, :layer)
          {Map.put(items, key, merged), warnings}
        end
      end)

    layers =
      by_key
      |> Map.values()
      |> Enum.sort_by(&{&1.depth, value(&1.item, :z_index, 0), &1.sequence_id, &1.layer_key})

    {visible_layers, removed_layers} = Enum.split_with(layers, &(not &1.removed))

    {Enum.map(visible_layers, &Map.delete(&1, :removed)), removed_layers, Enum.reverse(diagnostics)}
  end

  defp compose_audio_tracks(chain) do
    {by_key, diagnostics} =
      reduce_rows(chain, :sequence_tracks, fn row, owner, depth, {items, warnings} ->
        key = logical_key(row, :track_key, "legacy-track")
        fields = override_fields(row, @track_fields)
        existing = Map.get(items, key)

        if missing_inherited_track?(existing, row, fields) do
          warning = %{code: "missing_inherited_track", node_id: value(owner, :id)}
          {items, [warning | warnings]}
        else
          merged = merge_item(existing, row, owner, depth, key, fields, :track)
          {Map.put(items, key, merged), warnings}
        end
      end)

    tracks =
      by_key
      |> Map.values()
      |> Enum.sort_by(&{&1.depth, track_kind_order(&1.item), value(&1.item, :position, 0), &1.sequence_id, &1.track_key})

    {active_tracks, removed_tracks} = Enum.split_with(tracks, &(not &1.removed))

    active_tracks =
      Enum.map(active_tracks, fn track ->
        asset_source_id = Map.get(track, :asset_source_row_id)

        track
        |> Map.put(:continuity_key, "#{track.track_key}:#{asset_source_id || "none"}")
        |> Map.delete(:removed)
      end)

    {active_tracks, removed_tracks, Enum.reverse(diagnostics)}
  end

  defp reduce_rows(chain, association, reducer) do
    chain
    |> Enum.with_index()
    |> Enum.reduce({%{}, []}, fn {owner, depth}, acc ->
      owner
      |> list_value(association)
      |> Enum.sort_by(&value(&1, :id, 0))
      |> Enum.reduce(acc, &reducer.(&1, owner, depth, &2))
    end)
  end

  defp merge_item(nil, row, owner, depth, key, fields, kind) do
    owner_id = value(owner, :id)

    %{
      item: row_map(row),
      sequence_id: owner_id,
      owner_node_id: owner_id,
      depth: depth,
      property_sources: property_sources(fields, owner_id),
      removed: value(row, :removed, false) == true
    }
    |> put_logical_key(kind, key)
    |> maybe_put_asset_source(kind, row, fields)
  end

  defp merge_item(existing, row, owner, depth, key, fields, kind) do
    if redefines_identity?(existing, row, fields, kind) do
      merge_item(nil, row, owner, depth, key, fields, kind)
    else
      merge_inherited_item(existing, row, owner, fields, kind)
    end
  end

  defp merge_inherited_item(existing, row, owner, fields, kind) do
    owner_id = value(owner, :id)

    existing
    |> Map.put(:item, merge_properties(existing.item, row, fields))
    |> Map.put(:owner_node_id, owner_id)
    |> Map.put(:property_sources, Map.merge(existing.property_sources, property_sources(fields, owner_id)))
    |> Map.put(:removed, value(row, :removed, false) == true)
    |> maybe_put_asset_source(kind, row, fields)
  end

  defp redefines_identity?(_existing, _row, fields, :layer), do: definition?(fields, @layer_fields)

  defp redefines_identity?(_existing, row, fields, :track) do
    value(row, :is_override, false) == false or
      definition?(fields, @track_fields)
  end

  defp merge_properties(item, row, fields) do
    Enum.reduce(fields, item, fn field, merged ->
      field = field_atom(field)

      merged = Map.put(merged, field, value(row, field))

      if field == :asset_id,
        do: Map.put(merged, :asset, value(row, :asset)),
        else: merged
    end)
  end

  defp property_sources(fields, owner_id), do: Map.new(fields, &{&1, owner_id})

  defp put_logical_key(item, :layer, key), do: Map.put(item, :layer_key, key)
  defp put_logical_key(item, :track, key), do: Map.put(item, :track_key, key)

  defp maybe_put_asset_source(item, :track, row, fields) do
    if "asset_id" in fields,
      do: Map.put(item, :asset_source_row_id, value(row, :id)),
      else: Map.put_new(item, :asset_source_row_id, nil)
  end

  defp maybe_put_asset_source(item, :layer, _row, _fields), do: item

  defp override_fields(row, all_fields) do
    if has_key?(row, :overridden_fields) do
      row
      |> value(:overridden_fields, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.filter(&(&1 in all_fields))
    else
      all_fields
    end
  end

  defp definition?(fields, all_fields), do: MapSet.new(fields) == MapSet.new(all_fields)

  defp missing_inherited_definition?(existing, fields, all_fields) do
    (is_nil(existing) or existing.removed) and not definition?(fields, all_fields)
  end

  defp missing_inherited_track?(existing, row, fields) do
    (is_nil(existing) or existing.removed) and
      value(row, :is_override, false) == true and
      not definition?(fields, @track_fields)
  end

  defp logical_key(row, field, prefix), do: value(row, field) || "#{prefix}-#{value(row, :id, 0)}"
  defp row_map(%{__struct__: _} = row), do: Map.from_struct(row)
  defp row_map(row), do: row

  defp list_value(container, key) do
    case value(container, key) do
      values when is_list(values) -> values
      _not_loaded -> []
    end
  end

  defp has_key?(container, key), do: Map.has_key?(container, key) or Map.has_key?(container, Atom.to_string(key))

  defp value(container, key, default \\ nil),
    do: Map.get(container, key, Map.get(container, Atom.to_string(key), default))

  defp field_atom(field) do
    Map.fetch!(
      %{
        "asset_id" => :asset_id,
        "kind" => :kind,
        "label" => :label,
        "z_index" => :z_index,
        "slot" => :slot,
        "x" => :x,
        "y" => :y,
        "width" => :width,
        "height" => :height,
        "anchor_x" => :anchor_x,
        "anchor_y" => :anchor_y,
        "fit" => :fit,
        "opacity" => :opacity,
        "visible" => :visible,
        "position" => :position,
        "start_time" => :start_time,
        "end_time" => :end_time,
        "volume" => :volume
      },
      field
    )
  end

  defp track_kind_order(track) do
    case value(track, :kind) do
      "ambience" -> 0
      "music" -> 1
      "sfx" -> 2
      _ -> 3
    end
  end
end

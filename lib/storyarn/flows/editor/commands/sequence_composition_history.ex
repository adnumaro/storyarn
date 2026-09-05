defmodule Storyarn.Flows.SequenceCompositionHistory do
  @moduledoc """
  Captures and restores the local state of a sequence composition owner.

  The editor sends these snapshots through its existing undo/redo history.
  Restores replace only the owner's local source, canvas configuration, visual
  layers, and audio tracks; inherited state is recomputed from the graph.
  """

  import Ecto.Query

  alias Storyarn.Flows.Editor.Projections.AssetRecord
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceCompositionIntegrity
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Repo

  @version 1
  @max_key_length 64
  @int32_min -2_147_483_648
  @int32_max 2_147_483_647
  @max_track_decimal Decimal.new("9999999.999")
  @min_track_decimal Decimal.negate(@max_track_decimal)
  @visual_kinds ~w(backdrop character prop overlay)
  @visual_slots ~w(
    full left center right custom
    top-left top-center top-right
    middle-left middle-center middle-right
    bottom-left bottom-center bottom-right
  )
  @visual_fits ~w(cover contain fill)
  @track_kinds ~w(music ambience sfx)
  @visual_property_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)
  @track_property_fields ~w(position asset_id start_time end_time volume)

  @doc "Returns a JSON-safe snapshot of one active sequence or dialogue owner."
  @spec capture(integer()) :: {:ok, map()} | {:error, atom()}
  def capture(owner_id) when is_integer(owner_id) do
    Repo.transaction(fn ->
      with {:ok, %{node: owner}} <- References.lock_active_node_for_write(owner_id, :share),
           :ok <- ensure_composition_owner(owner) do
        owner
        |> Repo.preload(:sequence_config, force: true)
        |> snapshot()
      else
        {:error, _reason} -> Repo.rollback(:composition_owner_not_found)
      end
    end)
  end

  def capture(_owner_id), do: {:error, :composition_owner_not_found}

  @doc """
  Runs one composition mutation while holding the owner lock and returns the
  local state immediately before and after it.

  The callback must return `{:ok, result}` or `{:error, reason}`. Composition
  commands may open their own `Repo.transaction/1`; Ecto keeps those nested
  calls on this transaction's connection, so the owner lock spans the complete
  history operation.
  """
  @spec transact(integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, %{result: term(), previous: map(), current: map()}} | {:error, term()}
  def transact(owner_id, mutation) when is_integer(owner_id) and is_function(mutation, 0) do
    Repo.transaction(fn -> transact_in_transaction(owner_id, mutation) end)
  end

  def transact(_owner_id, _mutation), do: {:error, :invalid_composition_history_operation}

  @doc "Atomically restores a snapshot previously returned by `capture/1`."
  @spec restore(integer(), map()) :: {:ok, map()} | {:error, term()}
  def restore(owner_id, snapshot) when is_integer(owner_id) and is_map(snapshot) do
    with {:ok, snapshot} <- normalize_snapshot(snapshot) do
      Repo.transaction(fn -> restore_in_transaction(owner_id, snapshot, :skip_conflict_check) end)
    end
  end

  def restore(_owner_id, _snapshot), do: {:error, :invalid_composition_snapshot}

  @doc """
  Restores a history snapshot only when the owner's current local state still
  matches `expected_current`.

  The comparison and replacement run under the same owner lock. This prevents
  an undo or redo from silently overwriting a collaborator's newer edit.
  """
  @spec restore(integer(), map(), map()) :: {:ok, map()} | {:error, term()}
  def restore(owner_id, snapshot, expected_current)
      when is_integer(owner_id) and is_map(snapshot) and is_map(expected_current) do
    with {:ok, snapshot} <- normalize_snapshot(snapshot),
         {:ok, expected_current} <- normalize_snapshot(expected_current) do
      Repo.transaction(fn -> restore_in_transaction(owner_id, snapshot, expected_current) end)
    end
  end

  def restore(_owner_id, _snapshot, _expected_current), do: {:error, :invalid_composition_snapshot}

  defp transact_in_transaction(owner_id, mutation) do
    with {:ok, %{node: owner}} <- References.lock_active_node_for_write(owner_id),
         :ok <- ensure_composition_owner(owner),
         owner = Repo.preload(owner, :sequence_config, force: true),
         previous = snapshot(owner),
         {:ok, result} <- mutation.(),
         %FlowNode{} = current_owner <- get_owner(owner_id) do
      %{
        result: result,
        previous: previous,
        current: snapshot(current_owner)
      }
    else
      nil -> Repo.rollback(:composition_owner_not_found)
      {:error, reason} -> Repo.rollback(reason)
      invalid_result -> Repo.rollback({:invalid_composition_history_result, invalid_result})
    end
  end

  defp restore_in_transaction(owner_id, snapshot, expected_current) do
    with {:ok, %{node: owner, flow: flow, project_id: project_id}} <-
           References.lock_active_node_for_write(owner_id),
         :ok <- ensure_composition_owner(owner),
         :ok <- ensure_owner_type(snapshot, owner.type),
         :ok <- ensure_owner_identity(snapshot, owner, flow.id),
         :ok <- ensure_expected_identity(expected_current, owner, flow.id),
         :ok <- ensure_expected_current(owner, expected_current),
         source_id = snapshot["composition_source_id"],
         {:ok, nodes} <- lock_composition_nodes(flow.id),
         :ok <- validate_composition_source(owner.id, source_id, nodes),
         :ok <- validate_snapshot_composition(owner.id, snapshot, nodes),
         :ok <- validate_snapshot_assets(project_id, snapshot),
         {:ok, owner} <- restore_owner(owner, source_id, snapshot),
         :ok <- replace_visual_layers(owner.id, snapshot["visual_layers"]),
         :ok <- replace_tracks(owner.id, snapshot["tracks"]) do
      owner
      |> Repo.preload(:sequence_config, force: true)
      |> snapshot()
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_expected_current(_owner, :skip_conflict_check), do: :ok

  defp ensure_expected_current(owner, expected_current) do
    owner = Repo.preload(owner, :sequence_config, force: true)

    if snapshot(owner) == expected_current,
      do: :ok,
      else: {:error, :composition_history_conflict}
  end

  defp ensure_expected_identity(:skip_conflict_check, _owner, _flow_id), do: :ok

  defp ensure_expected_identity(expected_current, owner, flow_id) do
    with :ok <- ensure_owner_type(expected_current, owner.type) do
      ensure_owner_identity(expected_current, owner, flow_id)
    end
  end

  defp get_owner(owner_id) do
    Repo.one(
      from(node in FlowNode,
        where:
          node.id == ^owner_id and node.type in ["sequence", "dialogue"] and
            is_nil(node.deleted_at),
        preload: [:sequence_config]
      )
    )
  end

  defp snapshot(owner) do
    %{
      "version" => @version,
      "owner_id" => owner.id,
      "flow_id" => owner.flow_id,
      "owner_type" => owner.type,
      "composition_source_id" => owner.composition_source_id,
      "position_x" => owner.position_x,
      "position_y" => owner.position_y,
      "config" => serialize_config(owner.sequence_config),
      "visual_layers" =>
        owner.id
        |> visual_layers()
        |> Enum.map(&serialize_visual_layer/1),
      "tracks" =>
        owner.id
        |> tracks()
        |> Enum.map(&serialize_track/1)
    }
  end

  defp visual_layers(owner_id) do
    Repo.all(
      from(layer in SequenceVisualLayer,
        where: layer.flow_node_id == ^owner_id,
        order_by: [asc: layer.id]
      )
    )
  end

  defp tracks(owner_id) do
    Repo.all(
      from(track in SequenceTrack,
        where: track.flow_node_id == ^owner_id,
        order_by: [asc: track.id]
      )
    )
  end

  defp serialize_config(%SequenceConfig{} = config) do
    %{"name" => config.name, "width" => config.width, "height" => config.height}
  end

  defp serialize_config(_config), do: nil

  defp serialize_visual_layer(layer) do
    %{
      "asset_id" => layer.asset_id,
      "layer_key" => layer.layer_key,
      "overridden_fields" => layer.overridden_fields,
      "removed" => layer.removed,
      "kind" => layer.kind,
      "label" => layer.label,
      "z_index" => layer.z_index,
      "slot" => layer.slot,
      "x" => layer.x,
      "y" => layer.y,
      "width" => layer.width,
      "height" => layer.height,
      "anchor_x" => layer.anchor_x,
      "anchor_y" => layer.anchor_y,
      "fit" => layer.fit,
      "opacity" => layer.opacity,
      "visible" => layer.visible
    }
  end

  defp serialize_track(track) do
    %{
      "track_key" => track.track_key,
      "is_override" => track.is_override,
      "overridden_fields" => track.overridden_fields,
      "removed" => track.removed,
      "kind" => track.kind,
      "position" => track.position,
      "asset_id" => track.asset_id,
      "start_time" => serialize_decimal(track.start_time),
      "end_time" => serialize_decimal(track.end_time),
      "volume" => serialize_decimal(track.volume)
    }
  end

  defp serialize_decimal(nil), do: nil
  defp serialize_decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp normalize_snapshot(snapshot) do
    snapshot = stringify_keys(snapshot)

    with true <- snapshot["version"] in [@version, Integer.to_string(@version)],
         {:ok, owner_id} <- normalize_required_id(snapshot["owner_id"]),
         {:ok, flow_id} <- normalize_required_id(snapshot["flow_id"]),
         owner_type when owner_type in ["sequence", "dialogue"] <- snapshot["owner_type"],
         {:ok, source_id} <- normalize_optional_id(snapshot["composition_source_id"]),
         {:ok, position_x} <- normalize_number(snapshot, "position_x"),
         {:ok, position_y} <- normalize_number(snapshot, "position_y"),
         {:ok, config} <- normalize_config(owner_type, snapshot),
         visual_layers when is_list(visual_layers) <- snapshot["visual_layers"],
         tracks when is_list(tracks) <- snapshot["tracks"],
         {:ok, visual_layers} <- normalize_visual_layers(visual_layers),
         {:ok, tracks} <- normalize_tracks(tracks) do
      {:ok,
       %{
         "version" => @version,
         "owner_id" => owner_id,
         "flow_id" => flow_id,
         "owner_type" => owner_type,
         "composition_source_id" => source_id,
         "position_x" => position_x,
         "position_y" => position_y,
         "config" => config,
         "visual_layers" => visual_layers,
         "tracks" => tracks
       }}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_config("dialogue", %{"config" => nil}), do: {:ok, nil}

  defp normalize_config("sequence", %{"config" => config}) when is_map(config) do
    config = stringify_keys(config)

    with name when is_binary(name) <- config["name"],
         true <- String.length(name) in 1..200,
         {:ok, width} <- normalize_number(config, "width"),
         {:ok, height} <- normalize_number(config, "height") do
      {:ok, %{"name" => name, "width" => width, "height" => height}}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_config(_owner_type, _snapshot), do: {:error, :invalid_composition_snapshot}

  defp normalize_visual_layers(rows) do
    with {:ok, rows} <- normalize_rows(rows, &normalize_visual_layer/1),
         true <- unique_values?(rows, "layer_key") do
      {:ok, rows}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_visual_layer(row) when is_map(row) do
    row = stringify_keys(row)

    with {:ok, asset_id} <- normalize_optional_id(row["asset_id"]),
         {:ok, layer_key} <- normalize_key(row["layer_key"]),
         {:ok, overridden_fields} <-
           normalize_overridden_fields(row["overridden_fields"], @visual_property_fields),
         removed when is_boolean(removed) <- row["removed"],
         kind when kind in @visual_kinds <- row["kind"],
         {:ok, label} <- normalize_optional_label(row["label"]),
         {:ok, z_index} <- normalize_int32(row["z_index"]),
         slot when slot in @visual_slots <- row["slot"],
         {:ok, x} <- normalize_unit_number(row["x"], false),
         {:ok, y} <- normalize_unit_number(row["y"], false),
         {:ok, width} <- normalize_unit_number(row["width"], true),
         {:ok, height} <- normalize_unit_number(row["height"], true),
         {:ok, anchor_x} <- normalize_unit_number(row["anchor_x"], false),
         {:ok, anchor_y} <- normalize_unit_number(row["anchor_y"], false),
         fit when fit in @visual_fits <- row["fit"],
         {:ok, opacity} <- normalize_unit_number(row["opacity"], false),
         visible when is_boolean(visible) <- row["visible"] do
      {:ok,
       %{
         "asset_id" => asset_id,
         "layer_key" => layer_key,
         "overridden_fields" => overridden_fields,
         "removed" => removed,
         "kind" => kind,
         "label" => label,
         "z_index" => z_index,
         "slot" => slot,
         "x" => x,
         "y" => y,
         "width" => width,
         "height" => height,
         "anchor_x" => anchor_x,
         "anchor_y" => anchor_y,
         "fit" => fit,
         "opacity" => opacity,
         "visible" => visible
       }}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_visual_layer(_row), do: {:error, :invalid_composition_snapshot}

  defp normalize_tracks(rows) do
    with {:ok, rows} <- normalize_rows(rows, &normalize_track/1),
         true <- unique_values?(rows, "track_key"),
         true <- unique_local_track_kinds?(rows) do
      {:ok, rows}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_track(row) when is_map(row) do
    row = stringify_keys(row)

    with {:ok, track_key} <- normalize_key(row["track_key"]),
         is_override when is_boolean(is_override) <- row["is_override"],
         {:ok, overridden_fields} <-
           normalize_overridden_fields(row["overridden_fields"], @track_property_fields),
         removed when is_boolean(removed) <- row["removed"],
         kind when kind in @track_kinds <- row["kind"],
         {:ok, position} <- normalize_int32(row["position"]),
         {:ok, asset_id} <- normalize_optional_id(row["asset_id"]),
         {:ok, start_time} <- normalize_track_decimal(row["start_time"]),
         {:ok, end_time} <- normalize_track_decimal(row["end_time"]),
         {:ok, volume} <- normalize_volume(row["volume"]) do
      {:ok,
       %{
         "track_key" => track_key,
         "is_override" => is_override,
         "overridden_fields" => overridden_fields,
         "removed" => removed,
         "kind" => kind,
         "position" => position,
         "asset_id" => asset_id,
         "start_time" => start_time,
         "end_time" => end_time,
         "volume" => volume
       }}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_track(_row), do: {:error, :invalid_composition_snapshot}

  defp normalize_rows(rows, normalize) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, normalized} ->
      case normalize.(row) do
        {:ok, row} -> {:cont, {:ok, [row | normalized]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_required_id(value) do
    case normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_key(value) when is_binary(value) do
    if String.length(value) in 1..@max_key_length,
      do: {:ok, value},
      else: {:error, :invalid_composition_snapshot}
  end

  defp normalize_key(_value), do: {:error, :invalid_composition_snapshot}

  defp normalize_overridden_fields(fields, allowed) when is_list(fields) do
    if Enum.all?(fields, &is_binary/1) and Enum.uniq(fields) == fields and
         Enum.all?(fields, &(&1 in allowed)) do
      {:ok, fields}
    else
      {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_overridden_fields(_fields, _allowed), do: {:error, :invalid_composition_snapshot}

  defp normalize_optional_label(nil), do: {:ok, nil}

  defp normalize_optional_label(label) when is_binary(label) do
    if String.length(label) <= 120,
      do: {:ok, label},
      else: {:error, :invalid_composition_snapshot}
  end

  defp normalize_optional_label(_label), do: {:error, :invalid_composition_snapshot}

  defp normalize_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) -> {:ok, value}
      _missing_or_invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_unit_number(value, strictly_positive?) when is_number(value) do
    lower_bound_valid? = if strictly_positive?, do: value > 0, else: value >= 0

    if lower_bound_valid? and value <= 1,
      do: {:ok, value},
      else: {:error, :invalid_composition_snapshot}
  end

  defp normalize_unit_number(_value, _strictly_positive?), do: {:error, :invalid_composition_snapshot}

  defp normalize_int32(value) when is_integer(value) and value >= @int32_min and value <= @int32_max, do: {:ok, value}

  defp normalize_int32(_value), do: {:error, :invalid_composition_snapshot}

  defp normalize_track_decimal(nil), do: {:ok, nil}

  defp normalize_track_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} ->
        if Decimal.compare(decimal, @min_track_decimal) in [:gt, :eq] and
             Decimal.compare(decimal, @max_track_decimal) in [:lt, :eq] do
          {:ok, Decimal.to_string(decimal, :normal)}
        else
          {:error, :invalid_composition_snapshot}
        end

      _invalid ->
        {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_track_decimal(_value), do: {:error, :invalid_composition_snapshot}

  defp normalize_volume(nil), do: {:ok, nil}

  defp normalize_volume(value) do
    with {:ok, normalized} <- normalize_track_decimal(value),
         {decimal, ""} <- Decimal.parse(normalized),
         true <- Decimal.compare(decimal, Decimal.new(0)) in [:gt, :eq],
         true <- Decimal.compare(decimal, Decimal.new(1)) in [:lt, :eq] do
      {:ok, normalized}
    else
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp unique_values?(rows, key) do
    values = Enum.map(rows, &Map.fetch!(&1, key))
    length(values) == length(Enum.uniq(values))
  end

  defp unique_local_track_kinds?(rows) do
    kinds = for %{"is_override" => false, "kind" => kind} <- rows, do: kind
    length(kinds) == length(Enum.uniq(kinds))
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp ensure_composition_owner(%FlowNode{type: type, deleted_at: nil}) when type in ["sequence", "dialogue"], do: :ok

  defp ensure_composition_owner(_owner), do: {:error, :composition_owner_not_found}

  defp ensure_owner_type(%{"owner_type" => type}, type), do: :ok
  defp ensure_owner_type(_snapshot, _type), do: {:error, :composition_owner_mismatch}

  defp ensure_owner_identity(%{"owner_id" => owner_id, "flow_id" => flow_id}, %FlowNode{id: owner_id}, flow_id), do: :ok

  defp ensure_owner_identity(_snapshot, _owner, _flow_id), do: {:error, :invalid_composition_snapshot}

  defp normalize_optional_id(value) when value in [nil, ""], do: {:ok, nil}
  defp normalize_optional_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_optional_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> {:error, :invalid_composition_snapshot}
    end
  end

  defp normalize_optional_id(_value), do: {:error, :invalid_composition_snapshot}

  defp lock_composition_nodes(flow_id) do
    nodes =
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"],
        order_by: [asc: node.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Repo.preload([:sequence_tracks, :sequence_visual_layers], force: true)

    {:ok, Map.new(nodes, &{&1.id, &1})}
  end

  defp validate_snapshot_composition(owner_id, snapshot, nodes) do
    integrity_nodes =
      Enum.map(nodes, fn {node_id, node} ->
        if node_id == owner_id do
          integrity_node(
            node,
            snapshot["composition_source_id"],
            snapshot["tracks"],
            snapshot["visual_layers"]
          )
        else
          integrity_node(
            node,
            node.composition_source_id,
            node.sequence_tracks,
            node.sequence_visual_layers
          )
        end
      end)

    case SequenceCompositionIntegrity.validate_affected(integrity_nodes, owner_id) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_composition_snapshot}
    end
  end

  defp integrity_node(node, source_id, tracks, visual_layers) do
    %{
      "original_id" => node.id,
      "type" => node.type,
      "deleted_at" => node.deleted_at,
      "composition_source_original_id" => source_id,
      "sequence_tracks" => Enum.map(tracks, &integrity_track/1),
      "sequence_visual_layers" => Enum.map(visual_layers, &integrity_visual_layer/1)
    }
  end

  defp integrity_track(%SequenceTrack{} = track), do: serialize_track(track)
  defp integrity_track(track) when is_map(track), do: track

  defp integrity_visual_layer(%SequenceVisualLayer{} = layer), do: serialize_visual_layer(layer)

  defp integrity_visual_layer(layer) when is_map(layer), do: layer

  defp validate_composition_source(_owner_id, nil, _nodes), do: :ok

  defp validate_composition_source(owner_id, source_id, nodes) do
    case Map.get(nodes, source_id) do
      %FlowNode{deleted_at: nil} ->
        if composition_cycle?(owner_id, source_id, nodes, MapSet.new()),
          do: {:error, :invalid_composition_snapshot},
          else: :ok

      _missing_or_deleted ->
        {:error, :invalid_composition_snapshot}
    end
  end

  defp composition_cycle?(owner_id, owner_id, _nodes, _visited), do: true
  defp composition_cycle?(_owner_id, nil, _nodes, _visited), do: false

  defp composition_cycle?(owner_id, source_id, nodes, visited) do
    if MapSet.member?(visited, source_id) do
      true
    else
      case Map.get(nodes, source_id) do
        %FlowNode{composition_source_id: next_id} ->
          composition_cycle?(owner_id, next_id, nodes, MapSet.put(visited, source_id))

        nil ->
          true
      end
    end
  end

  defp validate_snapshot_assets(project_id, snapshot) do
    visual_ids = asset_ids(snapshot["visual_layers"])
    audio_ids = asset_ids(snapshot["tracks"])
    ids = Enum.uniq(visual_ids ++ audio_ids)

    assets =
      if ids == [] do
        %{}
      else
        from(asset in AssetRecord,
          where:
            asset.id in ^ids and asset.project_id == ^project_id and
              is_nil(asset.deleted_at),
          select: {asset.id, asset.content_type},
          lock: "FOR KEY SHARE"
        )
        |> Repo.all()
        |> Map.new()
      end

    if Enum.all?(visual_ids, &valid_asset?(assets, &1, "image/")) and
         Enum.all?(audio_ids, &valid_asset?(assets, &1, "audio/")) do
      :ok
    else
      {:error, :invalid_composition_snapshot}
    end
  end

  defp asset_ids(rows) do
    rows
    |> Enum.map(& &1["asset_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp valid_asset?(assets, asset_id, prefix) do
    case Map.get(assets, asset_id) do
      content_type when is_binary(content_type) -> String.starts_with?(content_type, prefix)
      _missing -> false
    end
  end

  defp restore_owner(owner, source_id, snapshot) do
    with {:ok, owner} <-
           owner
           |> FlowNode.composition_source_changeset(%{composition_source_id: source_id})
           |> Repo.update(),
         {:ok, owner} <- restore_position(owner, snapshot),
         :ok <- restore_config(owner, snapshot["config"]) do
      {:ok, owner}
    end
  end

  defp restore_position(owner, %{"position_x" => x, "position_y" => y}) do
    owner
    |> FlowNode.position_changeset(%{position_x: x, position_y: y})
    |> Repo.update()
  end

  defp restore_position(_owner, _snapshot), do: {:error, :invalid_composition_snapshot}

  defp restore_config(%FlowNode{type: "dialogue"}, nil), do: :ok

  defp restore_config(%FlowNode{type: "sequence", id: owner_id}, %{} = attrs) do
    case Repo.get_by(SequenceConfig, flow_node_id: owner_id) do
      %SequenceConfig{} = config ->
        case config |> SequenceConfig.update_changeset(attrs) |> Repo.update() do
          {:ok, _config} -> :ok
          {:error, changeset} -> {:error, changeset}
        end

      nil ->
        {:error, :invalid_composition_snapshot}
    end
  end

  defp restore_config(_owner, _config), do: {:error, :invalid_composition_snapshot}

  defp replace_visual_layers(owner_id, rows) do
    Repo.delete_all(from(layer in SequenceVisualLayer, where: layer.flow_node_id == ^owner_id))

    Enum.reduce_while(rows, :ok, fn attrs, :ok ->
      attrs = Map.put(attrs, "flow_node_id", owner_id)

      case %SequenceVisualLayer{}
           |> SequenceVisualLayer.override_changeset(attrs)
           |> Repo.insert() do
        {:ok, _layer} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp replace_tracks(owner_id, rows) do
    Repo.delete_all(from(track in SequenceTrack, where: track.flow_node_id == ^owner_id))

    Enum.reduce_while(rows, :ok, fn attrs, :ok ->
      attrs = Map.put(attrs, "flow_node_id", owner_id)

      case %SequenceTrack{} |> SequenceTrack.override_changeset(attrs) |> Repo.insert() do
        {:ok, _track} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end

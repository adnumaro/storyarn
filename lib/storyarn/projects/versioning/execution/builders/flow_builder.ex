defmodule Storyarn.Projects.Versioning.Builders.FlowBuilder do
  @moduledoc """
  Project-owned snapshot codec for Flow data.

  It captures, validates, and materializes Flow data as part of whole-project
  snapshots. Entity-version diff and restore behavior belongs to
  `Storyarn.Flows.Versioning.FlowSnapshot`.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Projects.FlowReferenceGraph, as: NodeCreate
  alias Storyarn.Projects.FlowWordCount, as: WordCount
  alias Storyarn.Projects.LocalizationLocaleCode, as: LocaleCode
  alias Storyarn.Projects.LocalizationPlaceholderValidator, as: HtmlHandler
  alias Storyarn.Projects.LocalizationRuntimeKey, as: RuntimeKey
  alias Storyarn.Projects.LocalizationSourceContract, as: SourceContract
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SequenceConfigRecord, as: SequenceConfig
  alias Storyarn.Projects.Persistence.SequenceTrackRecord, as: SequenceTrack
  alias Storyarn.Projects.Persistence.SequenceVisualLayerRecord, as: SequenceVisualLayer
  alias Storyarn.Projects.Persistence.SheetAvatarRecord, as: SheetAvatar
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References
  alias Storyarn.Projects.References.AvatarIntegrity
  alias Storyarn.Projects.SheetReadModel
  alias Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore, as: LocalizationVersionRestore
  alias Storyarn.Projects.Versioning.AssetMaterializationScope
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Projects.Versioning.MaterializationHelpers
  alias Storyarn.Projects.Versioning.SequenceCompositionIntegrity
  alias Storyarn.Repo

  @flow_snapshot_fields ~w(
    original_id name shortcut description is_main settings scene_id nodes connections
    asset_blob_hashes asset_metadata referenced_sheets localization localization_manifest
  )
  @node_snapshot_fields ~w(original_id type position_x position_y data parent_id composition_source_original_id)
  @sequence_config_fields ~w(name width height)
  @sequence_track_fields ~w(
    original_id track_key is_override overridden_fields removed kind position asset_id
    start_time end_time volume
  )
  @sequence_visual_layer_fields ~w(
    original_id layer_key overridden_fields removed asset_id kind label z_index slot x y width
    height anchor_x anchor_y fit opacity visible
  )
  @connection_snapshot_fields ~w(
    original_id source_node_index target_node_index source_pin target_pin label
  )
  @localization_snapshot_fields ~w(
    source_type source_id source_field source_text source_text_hash translated_source_hash
    locale_code translated_text status vo_status vo_asset_id translator_notes reviewer_notes
    speaker_sheet_id word_count machine_translated last_translated_at last_reviewed_at
    translated_by_id reviewed_by_id archived_at archive_reason
  )
  @snapshot_import_tombstone_nodes_fun_key :snapshot_import_tombstone_nodes_fun
  @snapshot_import_external_tombstone_node_map_key :snapshot_import_external_tombstone_node_map
  @composition_owner_types ~w(sequence dialogue)
  @track_override_fields ~w(position asset_id start_time end_time volume)
  @layer_override_fields ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)

  # ========== Build Snapshot ==========

  def build_snapshot(%Flow{} = flow) do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          lock_snapshot_project!(flow.project_id)
          locked_flow = lock_flow_for_snapshot!(flow)
          :ok = LocalizationVersionRestore.lock_inventory!(locked_flow.project_id)
          do_build_snapshot(locked_flow)
        end,
        isolation: :repeatable_read
      )

    snapshot
  end

  def build_snapshot(%{id: flow_id, project_id: project_id}) when is_integer(flow_id) and is_integer(project_id) do
    build_snapshot(%Flow{id: flow_id, project_id: project_id})
  end

  @doc false
  @spec build_capture_snapshot(Flow.t()) :: map()
  def build_capture_snapshot(%Flow{} = flow) do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          lock_snapshot_project!(flow.project_id)
          locked_flow = lock_flow_for_snapshot!(flow)
          :ok = LocalizationVersionRestore.lock_inventory!(locked_flow.project_id)
          do_build_capture_snapshot(locked_flow)
        end,
        isolation: :repeatable_read
      )

    snapshot
  end

  def build_capture_snapshot(%{id: flow_id, project_id: project_id})
      when is_integer(flow_id) and is_integer(project_id) do
    build_capture_snapshot(%Flow{id: flow_id, project_id: project_id})
  end

  defp do_build_snapshot(%Flow{} = flow) do
    flow =
      Repo.preload(
        flow,
        [
          :connections,
          nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
        ],
        force: true
      )

    # Sort nodes deterministically for stable indexes
    sorted_nodes =
      flow.nodes
      |> Enum.filter(&is_nil(&1.deleted_at))
      |> sort_and_normalize_snapshot_nodes(flow.project_id)

    ensure_build_external_references!(flow, sorted_nodes)

    # Build ID → index map for connection references
    id_to_index =
      sorted_nodes |> Enum.with_index() |> Map.new(fn {node, idx} -> {node.id, idx} end)

    node_snapshots = Enum.map(sorted_nodes, &node_to_snapshot/1)
    endpoint_states = snapshot_connection_endpoint_states(flow.connections)

    active_connections =
      Enum.filter(flow.connections, &active_snapshot_connection?(&1, flow.id, id_to_index, endpoint_states))

    ensure_build_dynamic_exit_pins!(active_connections, sorted_nodes)

    connection_snapshots =
      active_connections
      |> Enum.sort_by(&{Map.get(id_to_index, &1.source_node_id), &1.source_pin})
      |> Enum.map(&connection_to_snapshot(&1, id_to_index))

    referenced_sheets = build_referenced_sheets(sorted_nodes, flow.project_id)

    target_locales = LocalizationSnapshotCodec.active_target_locales(flow.project_id)

    localization =
      LocalizationSnapshotCodec.capture(
        flow.project_id,
        %{
          "flow_node" => Enum.map(sorted_nodes, & &1.id)
        },
        target_locales: target_locales
      )

    # Collect every asset reference, including localized voice-overs, and fail
    # closed if any persisted FK crosses the project boundary.
    asset_ids =
      Enum.flat_map(sorted_nodes, fn node ->
        [(node.data || %{})["audio_asset_id"]] ++
          Enum.map(sequence_tracks(node), & &1.asset_id) ++
          Enum.map(sequence_visual_layers(node), & &1.asset_id)
      end) ++ Enum.map(localization, & &1["vo_asset_id"])

    {hash_map, metadata_map} =
      AssetHashResolver.resolve_hashes_for_project!(asset_ids, flow.project_id)

    snapshot = %{
      "original_id" => flow.id,
      "name" => flow.name,
      "shortcut" => flow.shortcut,
      "description" => flow.description,
      "is_main" => flow.is_main,
      "settings" => flow.settings,
      "scene_id" => flow.scene_id,
      "nodes" => node_snapshots,
      "connections" => connection_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map,
      "referenced_sheets" => referenced_sheets,
      "localization" => localization,
      "localization_manifest" => LocalizationSnapshotCodec.manifest(localization, target_locales)
    }

    ensure_valid_built_flow_snapshot!(snapshot, target_locales)
  end

  defp do_build_capture_snapshot(%Flow{} = flow) do
    flow =
      Repo.preload(
        flow,
        [
          :connections,
          nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
        ],
        force: true
      )

    nodes =
      flow.nodes
      |> Enum.filter(&is_nil(&1.deleted_at))
      |> Enum.sort_by(&{&1.position_x, &1.position_y, &1.type, &1.id})

    id_to_index = nodes |> Enum.with_index() |> Map.new(fn {node, idx} -> {node.id, idx} end)
    node_snapshots = Enum.map(nodes, &node_to_capture_snapshot/1)
    connection_snapshots = capture_connection_snapshots(flow, id_to_index)

    target_locales = LocalizationSnapshotCodec.active_target_locales(flow.project_id)

    localization =
      LocalizationSnapshotCodec.capture(
        flow.project_id,
        %{"flow_node" => Enum.map(nodes, & &1.id)},
        target_locales: target_locales
      )

    {asset_blob_hashes, asset_metadata} = capture_asset_metadata(nodes, localization, flow)

    %{
      "original_id" => flow.id,
      "name" => flow.name,
      "shortcut" => flow.shortcut,
      "description" => flow.description,
      "is_main" => flow.is_main,
      "settings" => flow.settings,
      "scene_id" => flow.scene_id,
      "nodes" => node_snapshots,
      "connections" => connection_snapshots,
      "asset_blob_hashes" => asset_blob_hashes,
      "asset_metadata" => asset_metadata,
      "referenced_sheets" => build_capture_referenced_sheets(nodes, flow.project_id),
      "localization" => localization,
      "localization_manifest" => LocalizationSnapshotCodec.manifest(localization, target_locales)
    }
  end

  defp lock_snapshot_project!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Project{deleted_at: nil} ->
        :ok

      %Project{} ->
        raise ArgumentError,
              "cannot build a flow snapshot while project #{project_id} is in trash"

      nil ->
        raise Ecto.NoResultsError, queryable: Project
    end
  end

  defp lock_flow_for_snapshot!(%Flow{id: flow_id, project_id: project_id}) do
    case Repo.one(from(flow in Flow, where: flow.id == ^flow_id, lock: "FOR UPDATE")) do
      %Flow{project_id: ^project_id, deleted_at: nil} = locked_flow ->
        locked_flow

      %Flow{project_id: ^project_id} ->
        raise ArgumentError, "cannot build a snapshot for flow #{flow_id} while it is in trash"

      %Flow{project_id: owner_project_id} ->
        raise ArgumentError,
              "flow #{flow_id} changed project ownership to #{owner_project_id} while building snapshot"

      nil ->
        raise Ecto.NoResultsError, queryable: Flow
    end
  end

  defp ensure_valid_built_flow_snapshot!(snapshot, target_locales) do
    result =
      with {:ok, localization} <-
             complete_missing_snapshot_localization(
               snapshot["localization"],
               snapshot["nodes"],
               target_locales
             ),
           snapshot =
             snapshot
             |> Map.put("localization", localization)
             |> Map.put(
               "localization_manifest",
               LocalizationSnapshotCodec.manifest(localization, target_locales)
             ),
           :ok <- validate_flow_snapshot(snapshot) do
        {:ok, snapshot}
      end

    case result do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        raise ArgumentError,
              "cannot build an internally inconsistent flow snapshot: #{inspect(reason)}"
    end
  end

  defp ensure_build_external_references!(flow, nodes) do
    snapshot = %{
      "original_id" => flow.id,
      "scene_id" => flow.scene_id,
      "nodes" =>
        Enum.map(nodes, fn node ->
          %{
            "original_id" => node.id,
            "type" => node.type,
            "data" => node.data || %{}
          }
        end)
    }

    with {:ok, external_refs} <-
           validate_build_external_references(snapshot, flow.project_id),
         :ok <-
           validate_materialized_flow_reference_cycles(
             flow.id,
             external_refs.nodes
           ) do
      :ok
    else
      {:error, reason} ->
        raise ArgumentError,
              "cannot build a flow snapshot with invalid external references: #{inspect(reason)}"
    end
  end

  defp validate_build_external_references(snapshot, project_id) do
    with {:ok, exit_target_references} <-
           flow_exit_target_reference_specs(snapshot["nodes"]),
         references =
           [
             {Scene, snapshot["scene_id"], {:flow, snapshot["original_id"], "scene_id"}}
           ] ++
             Enum.flat_map(snapshot["nodes"], fn node ->
               data = node["data"] || %{}

               [
                 {Sheet, data["speaker_sheet_id"], {:flow_node, node["original_id"], "speaker_sheet_id"}},
                 {Sheet, data["location_sheet_id"], {:flow_node, node["original_id"], "location_sheet_id"}},
                 {Flow, data["referenced_flow_id"], {:flow_node, node["original_id"], "referenced_flow_id"}}
               ]
             end) ++ exit_target_references,
         {:ok, normalized_references} <-
           normalize_build_external_references(references),
         :ok <-
           validate_build_external_reference_ownership(
             normalized_references,
             project_id
           ),
         :ok <-
           validate_build_avatar_references(
             snapshot["nodes"],
             project_id
           ) do
      {:ok,
       %{
         scene_id: normalize_materialized_reference_id(snapshot["scene_id"]),
         nodes: normalize_build_node_external_references(snapshot["nodes"])
       }}
    end
  end

  defp flow_exit_target_reference_specs(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, references} ->
      case flow_exit_target_reference_spec(node) do
        {:ok, nil} ->
          {:cont, {:ok, references}}

        {:ok, reference} ->
          {:cont, {:ok, [reference | references]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, references} -> {:ok, Enum.reverse(references)}
      {:error, _reason} = error -> error
    end
  end

  defp flow_exit_target_reference_spec(%{"original_id" => node_id, "type" => "exit", "data" => data}) do
    with :ok <- validate_flow_exit_target_contract(node_id, data) do
      case normalized_flow_exit_target(data) do
        nil ->
          {:ok, nil}

        {"scene", target_id} ->
          {:ok, {Scene, target_id, {:flow_node, node_id, "target_id", "scene"}}}

        {"flow", target_id} ->
          {:ok, {Flow, target_id, {:flow_node, node_id, "target_id", "flow"}}}
      end
    end
  end

  defp flow_exit_target_reference_spec(_node), do: {:ok, nil}

  defp normalize_build_external_references(references) do
    Enum.reduce_while(references, {:ok, []}, fn
      {_schema, nil, _context}, {:ok, normalized} ->
        {:cont, {:ok, normalized}}

      {schema, value, context}, {:ok, normalized} ->
        case normalize_materialized_reference_id(value) do
          nil ->
            {:halt, {:error, {:invalid_flow_external_reference, context, value}}}

          id ->
            {:cont, {:ok, [{schema, id, context, value} | normalized]}}
        end
    end)
  end

  defp validate_build_external_reference_ownership(references, project_id) do
    active_ids =
      references
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {schema, ids} ->
        ids = Enum.uniq(ids)

        owned_ids =
          Repo.all(
            from(record in schema,
              where:
                record.id in ^ids and record.project_id == ^project_id and
                  is_nil(field(record, :deleted_at)),
              order_by: [asc: record.id],
              lock: "FOR SHARE",
              select: record.id
            )
          )

        {schema, MapSet.new(owned_ids)}
      end)

    case Enum.find(references, fn {schema, id, _context, _value} ->
           not MapSet.member?(Map.get(active_ids, schema, MapSet.new()), id)
         end) do
      nil ->
        :ok

      {_schema, _id, context, value} ->
        {:error, {:flow_external_reference_not_materializable, context, value}}
    end
  end

  defp validate_build_avatar_references(nodes, project_id) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case AvatarIntegrity.lock_and_normalize_node_avatar_for_project(
             project_id,
             node["type"],
             node["data"] || %{}
           ) do
        {:ok, _normalized_data} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error, {:flow_external_reference_not_materializable, {:flow_node, node["original_id"], "avatar_id"}, reason}}}
      end
    end)
  end

  defp normalize_build_node_external_references(nodes) when is_list(nodes) do
    Enum.map(nodes, &normalize_build_node_external_references/1)
  end

  defp normalize_build_node_external_references(node) when is_map(node) do
    data =
      Enum.reduce(
        ~w(speaker_sheet_id location_sheet_id referenced_flow_id),
        node["data"] || %{},
        &normalize_build_node_external_reference/2
      )

    Map.put(node, "data", data)
  end

  defp normalize_build_node_external_reference(field, data) do
    case Map.fetch(data, field) do
      {:ok, value} -> Map.put(data, field, normalize_materialized_reference_id(value))
      :error -> data
    end
  end

  defp ensure_build_dynamic_exit_pins!(connections, nodes) do
    nodes_by_id = Map.new(nodes, &{&1.id, &1})

    dynamic_pins =
      Enum.flat_map(connections, fn connection ->
        source_node = Map.fetch!(nodes_by_id, connection.source_node_id)

        build_dynamic_exit_pin(connection, source_node)
      end)

    locked_exits =
      dynamic_pins
      |> Enum.map(& &1.exit_id)
      |> Enum.uniq()
      |> then(fn exit_ids ->
        Repo.all(
          from(node in FlowNode,
            where: node.id in ^exit_ids,
            order_by: [asc: node.id],
            lock: "FOR SHARE",
            select: {node.id, node.flow_id, node.type, node.deleted_at}
          )
        )
      end)
      |> Map.new(fn {id, flow_id, type, deleted_at} ->
        {id, %{flow_id: flow_id, type: type, deleted_at: deleted_at}}
      end)

    Enum.each(dynamic_pins, fn pin ->
      case dynamic_exit_pin_state(Map.get(locked_exits, pin.exit_id), pin.referenced_flow_id) do
        :ok ->
          :ok

        reason ->
          raise ArgumentError,
                "cannot build a flow snapshot with an invalid dynamic exit pin: " <>
                  inspect({:dynamic_exit_pin_not_materializable, pin.connection_id, pin.source_pin, reason})
      end
    end)
  end

  defp build_dynamic_exit_pin(%FlowConnection{} = connection, %FlowNode{type: "subflow"} = source_node) do
    case parse_dynamic_exit_pin(connection.source_pin) do
      :not_dynamic ->
        []

      {:ok, exit_id} ->
        referenced_flow_id =
          (source_node.data || %{})
          |> Map.get("referenced_flow_id")
          |> normalize_materialized_reference_id()

        if referenced_flow_id do
          [
            %{
              connection_id: connection.id,
              source_pin: connection.source_pin,
              exit_id: exit_id,
              referenced_flow_id: referenced_flow_id
            }
          ]
        else
          raise ArgumentError,
                "cannot build a flow snapshot with an invalid dynamic exit pin: " <>
                  inspect(
                    {:dynamic_exit_pin_not_materializable, connection.id, connection.source_pin, :missing_referenced_flow}
                  )
        end

      {:error, reason} ->
        raise ArgumentError,
              "cannot build a flow snapshot with an invalid dynamic exit pin: " <>
                inspect({:dynamic_exit_pin_not_materializable, connection.id, connection.source_pin, reason})
    end
  end

  defp build_dynamic_exit_pin(_connection, _source_node), do: []

  defp dynamic_exit_pin_state(nil, _referenced_flow_id), do: :exit_not_found

  defp dynamic_exit_pin_state(%{deleted_at: deleted_at}, _referenced_flow_id) when not is_nil(deleted_at),
    do: :exit_in_trash

  defp dynamic_exit_pin_state(%{type: type}, _referenced_flow_id) when type != "exit", do: :referenced_node_not_exit

  defp dynamic_exit_pin_state(%{flow_id: flow_id}, referenced_flow_id) when flow_id != referenced_flow_id,
    do: :exit_not_in_referenced_flow

  defp dynamic_exit_pin_state(_exit, _referenced_flow_id), do: :ok

  defp node_to_snapshot(%FlowNode{} = node) do
    snapshot = %{
      "original_id" => node.id,
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "data" => node.data,
      "parent_id" => node.parent_id,
      "composition_source_original_id" => node.composition_source_id
    }

    case node.type do
      "sequence" ->
        Map.merge(snapshot, sequence_snapshot_fields(node))

      "dialogue" ->
        Map.merge(snapshot, composition_snapshot_fields(node))

      _other ->
        if residual_sequence_resources?(node),
          do: Map.merge(snapshot, sequence_snapshot_fields(node)),
          else: snapshot
    end
  end

  defp node_to_capture_snapshot(%FlowNode{} = node) do
    snapshot = node_to_snapshot(node)

    if node.type not in @composition_owner_types and residual_sequence_resources?(node),
      do: Map.merge(snapshot, sequence_snapshot_fields(node)),
      else: snapshot
  end

  defp residual_sequence_resources?(node) do
    not is_nil(node.sequence_config) or sequence_tracks(node) != [] or
      sequence_visual_layers(node) != []
  end

  defp sequence_snapshot_fields(node) do
    Map.put(
      composition_snapshot_fields(node),
      "sequence_config",
      sequence_config_to_snapshot(node.sequence_config)
    )
  end

  defp composition_snapshot_fields(node) do
    %{
      "sequence_tracks" =>
        node
        |> sequence_tracks()
        |> Enum.sort_by(&{&1.kind, &1.position, &1.track_key, &1.id})
        |> Enum.map(&sequence_track_to_snapshot/1),
      "sequence_visual_layers" =>
        node
        |> sequence_visual_layers()
        |> Enum.sort_by(&{&1.z_index, &1.layer_key, &1.id})
        |> Enum.map(&sequence_visual_layer_to_snapshot/1)
    }
  end

  defp sequence_config_to_snapshot(%SequenceConfig{} = config) do
    %{
      "name" => config.name,
      "width" => config.width,
      "height" => config.height
    }
  end

  defp sequence_config_to_snapshot(_config), do: nil

  defp sequence_track_to_snapshot(%SequenceTrack{} = track) do
    %{
      "original_id" => track.id,
      "track_key" => track.track_key,
      "is_override" => track.is_override,
      "overridden_fields" => track.overridden_fields,
      "removed" => track.removed,
      "kind" => track.kind,
      "position" => track.position,
      "asset_id" => track.asset_id,
      "start_time" => decimal_to_snapshot(track.start_time),
      "end_time" => decimal_to_snapshot(track.end_time),
      "volume" => decimal_to_snapshot(track.volume)
    }
  end

  defp sequence_visual_layer_to_snapshot(%SequenceVisualLayer{} = layer) do
    %{
      "original_id" => layer.id,
      "layer_key" => layer.layer_key,
      "overridden_fields" => layer.overridden_fields,
      "removed" => layer.removed,
      "asset_id" => layer.asset_id,
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

  defp decimal_to_snapshot(nil), do: nil
  defp decimal_to_snapshot(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp sequence_tracks(%FlowNode{sequence_tracks: tracks}) when is_list(tracks), do: tracks
  defp sequence_tracks(_node), do: []

  defp sequence_visual_layers(%FlowNode{sequence_visual_layers: layers}) when is_list(layers), do: layers
  defp sequence_visual_layers(_node), do: []

  defp connection_to_snapshot(%FlowConnection{} = conn, id_to_index) do
    %{
      "original_id" => conn.id,
      "source_node_index" => Map.fetch!(id_to_index, conn.source_node_id),
      "target_node_index" => Map.fetch!(id_to_index, conn.target_node_id),
      "source_pin" => conn.source_pin,
      "target_pin" => conn.target_pin,
      "label" => conn.label
    }
  end

  defp capture_connection_snapshots(flow, id_to_index) do
    flow.connections
    |> Enum.sort_by(&{&1.source_node_id, &1.source_pin, &1.target_node_id, &1.target_pin, &1.id})
    |> Enum.map(fn connection ->
      source_index = Map.get(id_to_index, connection.source_node_id)
      target_index = Map.get(id_to_index, connection.target_node_id)

      %{
        "original_id" => connection.id,
        "source_node_index" => source_index,
        "target_node_index" => target_index,
        "source_pin" => connection.source_pin,
        "target_pin" => connection.target_pin,
        "label" => connection.label
      }
      |> maybe_put_raw_endpoint("source_node_id", connection.source_node_id, source_index)
      |> maybe_put_raw_endpoint("target_node_id", connection.target_node_id, target_index)
    end)
  end

  defp maybe_put_raw_endpoint(snapshot, _field, _node_id, index) when is_integer(index), do: snapshot
  defp maybe_put_raw_endpoint(snapshot, field, node_id, _index), do: Map.put(snapshot, field, node_id)

  defp snapshot_connection_endpoint_states(connections) do
    endpoint_ids =
      connections
      |> Enum.flat_map(&[&1.source_node_id, &1.target_node_id])
      |> Enum.uniq()

    from(node in FlowNode,
      where: node.id in ^endpoint_ids,
      select: {node.id, %{flow_id: node.flow_id, type: node.type, deleted_at: node.deleted_at}}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp active_snapshot_connection?(connection, flow_id, id_to_index, endpoint_states) do
    source = fetch_snapshot_endpoint!(endpoint_states, connection.source_node_id, connection.id)
    target = fetch_snapshot_endpoint!(endpoint_states, connection.target_node_id, connection.id)

    ensure_snapshot_endpoint_owner!(source, flow_id, connection.id)
    ensure_snapshot_endpoint_owner!(target, flow_id, connection.id)

    snapshot_connection_active_state!(connection, source, target, id_to_index)
  end

  defp fetch_snapshot_endpoint!(endpoint_states, node_id, connection_id) do
    case Map.fetch(endpoint_states, node_id) do
      {:ok, endpoint} ->
        endpoint

      :error ->
        raise ArgumentError,
              "flow connection #{connection_id} references a missing endpoint"
    end
  end

  defp ensure_snapshot_endpoint_owner!(%{flow_id: flow_id}, flow_id, _connection_id), do: :ok

  defp ensure_snapshot_endpoint_owner!(_endpoint, flow_id, connection_id) do
    raise ArgumentError,
          "flow connection #{connection_id} references an endpoint outside flow #{flow_id}"
  end

  defp snapshot_connection_active_state!(connection, %{deleted_at: nil}, %{deleted_at: nil}, id_to_index) do
    if Map.has_key?(id_to_index, connection.source_node_id) and
         Map.has_key?(id_to_index, connection.target_node_id) do
      true
    else
      raise ArgumentError,
            "flow connection #{connection.id} has an active endpoint missing from the snapshot"
    end
  end

  defp snapshot_connection_active_state!(_connection, _source, _target, _id_to_index), do: false

  # Embeds sheet metadata (name, color, avatar, banner) at snapshot time
  # so the version viewer doesn't need to read live DB state.
  defp build_referenced_sheets(nodes, project_id) do
    sheet_ids =
      nodes
      |> Enum.flat_map(fn node ->
        data = node.data || %{}
        [data["speaker_sheet_id"], data["location_sheet_id"]]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if sheet_ids == [] do
      %{}
    else
      sheets = SheetReadModel.list_by_ids(project_id, sheet_ids)

      Map.new(sheets, fn sheet ->
        {to_string(sheet.id),
         %{
           "id" => sheet.id,
           "name" => sheet.name,
           "shortcut" => sheet.shortcut,
           "color" => sheet.color,
           "avatar_url" => extract_default_avatar_url(sheet),
           "banner_url" => extract_asset_url(sheet.banner_asset)
         }}
      end)
    end
  end

  defp build_capture_referenced_sheets(nodes, project_id) do
    nodes
    |> Enum.map(fn node ->
      data = capture_node_data(node)
      [data["speaker_sheet_id"], data["location_sheet_id"]]
    end)
    |> List.flatten()
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      sheet_ids ->
        project_id
        |> SheetReadModel.list_by_ids(sheet_ids)
        |> Map.new(fn sheet ->
          {to_string(sheet.id),
           %{
             "id" => sheet.id,
             "name" => sheet.name,
             "shortcut" => sheet.shortcut,
             "color" => sheet.color,
             "avatar_url" => extract_default_avatar_url(sheet),
             "banner_url" => extract_asset_url(sheet.banner_asset)
           }}
        end)
    end
  end

  defp capture_node_data(%FlowNode{data: data}) when is_map(data), do: data
  defp capture_node_data(%FlowNode{}), do: %{}

  defp capture_asset_metadata(nodes, localization, flow) do
    nodes
    |> capture_asset_reference_specs(localization)
    |> Enum.map(fn spec ->
      context =
        spec
        |> Map.take([:entity_type, :entity_id, :source_field])
        |> Map.merge(%{container_type: :flow, container_id: flow.id})

      {spec.asset_id, context}
    end)
    |> AssetHashResolver.resolve_hashes_for_project_capture(flow.project_id)
  end

  defp capture_asset_reference_specs(nodes, localization) do
    node_specs =
      Enum.flat_map(nodes, fn node ->
        data = capture_node_data(node)

        [
          capture_asset_reference_spec(
            data["audio_asset_id"],
            :flow_node,
            node.id,
            "audio_asset_id"
          )
        ] ++
          Enum.map(sequence_tracks(node), fn track ->
            capture_asset_reference_spec(track.asset_id, :sequence_track, track.id, "asset_id")
          end) ++
          Enum.map(sequence_visual_layers(node), fn layer ->
            capture_asset_reference_spec(
              layer.asset_id,
              :sequence_visual_layer,
              layer.id,
              "asset_id"
            )
          end)
      end)

    localization_specs =
      Enum.map(localization, fn row ->
        capture_asset_reference_spec(
          row["vo_asset_id"],
          :flow_node,
          row["source_id"],
          "vo_asset_id"
        )
      end)

    (node_specs ++ localization_specs)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.entity_type, &1.entity_id, &1.source_field, &1.asset_id})
  end

  defp capture_asset_reference_spec(nil, _entity_type, _entity_id, _source_field), do: nil

  defp capture_asset_reference_spec(asset_id, entity_type, entity_id, source_field) do
    %{
      asset_id: asset_id,
      entity_type: entity_type,
      entity_id: entity_id,
      source_field: source_field
    }
  end

  defp extract_asset_url(%{url: url}) when is_binary(url), do: url
  defp extract_asset_url(_), do: nil

  defp extract_default_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_default_avatar_url(sheet), do: extract_asset_url(Map.get(sheet, :avatar_asset))

  # ========== Project Reconstitution ==========

  @doc false
  @spec validate_portable_snapshot(term()) :: :ok | {:error, term()}
  def validate_portable_snapshot(snapshot), do: snapshot |> normalize_legacy_snapshot() |> validate_flow_snapshot()

  @doc """
  Materializes a captured Flow inside Project reconstitution.

  External reference maps and the returned ID maps are Projects-only import and
  reconstitution contracts; they are intentionally absent from Flow entity
  restore.
  """
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    snapshot = normalize_legacy_snapshot(snapshot)

    with :ok <- validate_instantiation_snapshot(snapshot, opts) do
      with_asset_materialization_scope(opts, fn scoped_opts ->
        instantiate_flow_snapshot_transaction(
          project_id,
          snapshot,
          scoped_opts
        )
      end)
    end
  end

  defp validate_instantiation_snapshot(snapshot, opts) do
    # Exact reconstitution preserves legacy residual sequence rows on authored
    # non-owner node types. Portable snapshots reject that residual shape.
    if MaterializationHelpers.exact_materialization?(opts) and is_map(snapshot),
      do: :ok,
      else: validate_portable_snapshot(snapshot)
  end

  defp materialization_mode(opts), do: Keyword.get(opts, :materialization_mode, :portable)

  defp maybe_validate_materialized_flow_reference_cycles(flow_id, nodes, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: :ok,
      else: validate_materialized_flow_reference_cycles(flow_id, nodes)
  end

  defp instantiate_flow_snapshot_transaction(project_id, snapshot, opts) do
    result =
      MaterializationHelpers.with_project_storage_lock(project_id, fn ->
        instantiate_flow_snapshot(project_id, snapshot, opts)
      end)

    if not MaterializationHelpers.exact_materialization?(opts) and retry_main_constraint?(result, opts) do
      instantiate_flow_snapshot_transaction(
        project_id,
        snapshot,
        Keyword.put(opts, :__force_non_main_on_conflict, true)
      )
    else
      finalize_flow_instantiation(result)
    end
  end

  defp instantiate_flow_snapshot(project_id, snapshot, opts) do
    now = MaterializationHelpers.now()
    nodes = Map.get(snapshot, "nodes", [])
    connections = Map.get(snapshot, "connections", [])

    with {:ok, _project} <- lock_materialization_project(Repo, project_id),
         {:ok, _external_locks} <-
           lock_flow_external_references(Repo, snapshot, project_id, opts),
         {:ok, external_refs} <-
           materialize_flow_external_references(snapshot, project_id, opts, materialization_mode(opts)),
         :ok <- LocalizationVersionRestore.lock_inventory!(project_id),
         is_main = restorable_main_state(Repo, project_id, nil, snapshot["is_main"], opts),
         :ok <- run_before_main_write_hook(opts),
         {:ok, flow_id} <-
           insert_flow_root(
             Repo,
             flow_snapshot_attrs(
               project_id,
               snapshot,
               external_refs.scene_id,
               opts,
               now,
               is_main
             )
           ),
         :ok <- maybe_validate_materialized_flow_reference_cycles(flow_id, external_refs.nodes, opts),
         {:ok, node_data} <-
           insert_flow_nodes(
             Repo,
             flow_id,
             external_refs.nodes,
             snapshot,
             project_id,
             now,
             opts
           ),
         node_id_map = node_data.id_map,
         {:ok, tombstone_node_id_map} <-
           materialize_snapshot_import_tombstone_nodes(
             flow_id,
             snapshot,
             node_id_map,
             now,
             opts
           ),
         {:ok, _linked_parents} <- link_snapshot_node_parents(Repo, nodes, node_id_map, project_id, opts),
         {:ok, _linked_composition_sources} <-
           link_snapshot_node_composition_sources(Repo, nodes, node_id_map),
         {:ok, sequence_resource_data} <-
           insert_sequence_resources(Repo, nodes, node_id_map, snapshot, project_id, opts, now),
         :ok <- restore_exact_authored_node_types(Repo, nodes, node_id_map, opts),
         connection_context = %{
           nodes_data: nodes,
           materialized_nodes_data: external_refs.nodes,
           node_id_map:
             snapshot_import_connection_node_id_map(
               node_id_map,
               tombstone_node_id_map,
               opts
             ),
           project_id: project_id,
           opts: opts
         },
         {:ok, connection_id_map} <-
           insert_flow_connections(
             Repo,
             flow_id,
             connections,
             connection_context,
             now
           ) do
      complete_flow_instantiation(
        project_id,
        snapshot,
        flow_id,
        node_id_map,
        tombstone_node_id_map,
        connection_id_map,
        sequence_resource_data,
        opts
      )
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp flow_snapshot_attrs(project_id, snapshot, scene_id, opts, now, is_main) do
    Map.merge(
      %{
        project_id: project_id,
        name: snapshot["name"],
        shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
        description: snapshot["description"],
        is_main: is_main,
        settings: snapshot["settings"] || %{},
        scene_id: scene_id,
        parent_id: MaterializationHelpers.root_parent_id(opts),
        position: MaterializationHelpers.root_position(opts)
      },
      MaterializationHelpers.timestamps(now)
    )
  end

  defp insert_flow_root(repo, attrs) do
    struct_attrs = Map.take(attrs, [:project_id, :inserted_at, :updated_at])
    changeset_attrs = Map.drop(attrs, [:project_id, :inserted_at, :updated_at])

    Flow
    |> struct(struct_attrs)
    |> Flow.create_changeset(changeset_attrs)
    |> main_flow_unique_constraint()
    |> repo.insert()
    |> case do
      {:ok, flow} -> {:ok, flow.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp lock_materialization_project(repo, project_id) do
    case repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, {:project_deleted, project_id}}
      nil -> {:error, {:project_not_found, project_id}}
    end
  end

  defp restorable_main_state(_repo, _project_id, _flow_id, false, _opts), do: false

  defp restorable_main_state(repo, project_id, flow_id, true, opts) do
    if Keyword.get(opts, :__force_non_main_on_conflict, false) do
      false
    else
      query =
        from(flow in Flow,
          where:
            flow.project_id == ^project_id and flow.is_main == true and
              is_nil(flow.deleted_at)
        )

      query =
        if is_integer(flow_id) do
          where(query, [flow], flow.id != ^flow_id)
        else
          query
        end

      not repo.exists?(query)
    end
  end

  defp main_flow_unique_constraint(changeset) do
    Ecto.Changeset.unique_constraint(changeset, :is_main, name: :flows_project_id_is_main_index)
  end

  defp retry_main_constraint?(result, opts) do
    not Keyword.get(opts, :__force_non_main_on_conflict, false) and
      result_has_main_constraint?(result)
  end

  defp result_has_main_constraint?({:error, %Ecto.Changeset{} = changeset}), do: main_constraint_error?(changeset)

  defp result_has_main_constraint?({:error, :flow, %Ecto.Changeset{} = changeset, _changes}),
    do: main_constraint_error?(changeset)

  defp result_has_main_constraint?(_result), do: false

  defp main_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
      metadata[:constraint] == :unique and
        to_string(metadata[:constraint_name]) == "flows_project_id_is_main_index"
    end)
  end

  defp complete_flow_instantiation(
         project_id,
         snapshot,
         flow_id,
         node_id_map,
         tombstone_node_id_map,
         connection_id_map,
         sequence_resource_data,
         opts
       ) do
    flow =
      Flow
      |> Repo.get!(flow_id)
      |> Repo.preload(
        [:connections, nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]],
        force: true
      )

    id_maps =
      maybe_put_snapshot_import_tombstone_node_map(
        %{
          flow: MaterializationHelpers.root_id_map(snapshot, flow_id),
          node: node_id_map,
          connection: connection_id_map,
          sequence_track: sequence_resource_data.track_id_map,
          sequence_visual_layer: sequence_resource_data.visual_layer_id_map
        },
        tombstone_node_id_map,
        opts
      )

    with :ok <- maybe_restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts),
         :ok <-
           maybe_rebuild_instantiated_flow_references(
             flow.nodes,
             project_id,
             opts
           ) do
      {flow, id_maps}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp materialize_snapshot_import_tombstone_nodes(flow_id, snapshot, node_id_map, now, opts) do
    case Keyword.get(opts, @snapshot_import_tombstone_nodes_fun_key) do
      nil ->
        {:ok, %{}}

      fun when is_function(fun, 4) ->
        with {:ok, tombstone_node_id_map} <- fun.(flow_id, snapshot, node_id_map, now),
             :ok <- validate_snapshot_import_tombstone_node_map(tombstone_node_id_map, node_id_map) do
          {:ok, tombstone_node_id_map}
        end

      _invalid ->
        {:error, :invalid_snapshot_import_tombstone_nodes_materializer}
    end
  end

  defp validate_snapshot_import_tombstone_node_map(tombstone_node_id_map, active_node_id_map)
       when is_map(tombstone_node_id_map) do
    valid? =
      Enum.all?(tombstone_node_id_map, fn {source_id, destination_id} ->
        is_integer(source_id) and source_id > 0 and is_integer(destination_id) and destination_id > 0 and
          not Map.has_key?(active_node_id_map, source_id)
      end)

    if valid?, do: :ok, else: {:error, :invalid_snapshot_import_tombstone_node_map}
  end

  defp validate_snapshot_import_tombstone_node_map(_invalid, _active_node_id_map),
    do: {:error, :invalid_snapshot_import_tombstone_node_map}

  defp maybe_put_snapshot_import_tombstone_node_map(id_maps, tombstone_node_id_map, opts) do
    if Keyword.has_key?(opts, @snapshot_import_tombstone_nodes_fun_key),
      do: Map.put(id_maps, :referenced_tombstone_node, tombstone_node_id_map),
      else: id_maps
  end

  defp snapshot_import_connection_node_id_map(active_node_id_map, tombstone_node_id_map, opts) do
    opts
    |> Keyword.get(@snapshot_import_external_tombstone_node_map_key, %{})
    |> Map.merge(active_node_id_map)
    |> Map.merge(tombstone_node_id_map)
  end

  defp maybe_restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts) do
    if Keyword.get(opts, :restore_localization, true) do
      with :ok <- restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts) do
        LocalizationVersionRestore.extract_flow(id_maps.flow[snapshot["original_id"]])
      end
    else
      :ok
    end
  end

  defp maybe_rebuild_instantiated_flow_references(nodes, project_id, opts) do
    if Keyword.get(opts, :rebuild_references, true) do
      rebuild_instantiated_flow_references(nodes, project_id)
    else
      :ok
    end
  end

  defp restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts) do
    if Keyword.get(opts, :restore_localization, true) do
      localization =
        LocalizationSnapshotCodec.active_target_rows(
          project_id,
          Map.get(snapshot, "localization", [])
        )

      with {:ok, localization} <-
             materialize_localization_asset_references(
               localization,
               snapshot,
               project_id,
               opts
             ),
           {:ok, localization} <-
             materialize_localization_speaker_references(
               localization,
               project_id,
               opts,
               :portable
             ) do
        LocalizationVersionRestore.restore_flow(
          project_id,
          localization,
          id_maps
        )
      end
    else
      :ok
    end
  end

  defp materialize_localization_speaker_references(localization, project_id, opts, mode) do
    localization
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, rows} ->
      case materialize_external_reference(
             row["speaker_sheet_id"],
             Sheet,
             :sheet,
             project_id,
             opts,
             mode,
             {:localization, row["source_id"], "speaker_sheet_id"}
           ) do
        {:ok, speaker_sheet_id} ->
          {:cont, {:ok, [Map.put(row, "speaker_sheet_id", speaker_sheet_id) | rows]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, _reason} = error -> error
    end
  end

  defp materialize_localization_asset_references(localization, snapshot, project_id, opts) do
    {:ok,
     Enum.map(localization, fn row ->
       materialize_localization_asset_reference(
         row,
         snapshot,
         project_id,
         opts
       )
     end)}
  end

  defp materialize_localization_asset_reference(%{"vo_asset_id" => nil} = row, _snapshot, _project_id, _opts), do: row

  defp materialize_localization_asset_reference(%{"vo_asset_id" => asset_id} = row, snapshot, project_id, opts) do
    case flow_asset_mode(opts) do
      :drop ->
        row
        |> Map.put("vo_asset_id", nil)
        |> drop_voice_status()

      _mode ->
        Map.put(
          row,
          "vo_asset_id",
          resolve_flow_asset(
            asset_id,
            snapshot,
            project_id,
            opts,
            "audio/",
            :localization_voiceover
          )
        )
    end
  end

  defp drop_voice_status(%{"vo_status" => status} = row) when status in ~w(recorded approved),
    do: Map.put(row, "vo_status", "needed")

  defp drop_voice_status(row), do: row

  defp finalize_flow_instantiation(result) do
    case result do
      {:ok, {flow, id_maps}} ->
        {:ok, flow, id_maps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp with_asset_materialization_scope(opts, callback) do
    MaterializationHelpers.with_asset_copy_tracker(opts, fn tracked_opts ->
      AssetMaterializationScope.run(tracked_opts, callback)
    end)
  end

  defp run_before_main_write_hook(opts) do
    case Keyword.get(opts, :__before_main_write_hook) do
      hook when is_function(hook, 0) ->
        hook.()
        :ok

      _hook ->
        :ok
    end
  end

  @doc false
  @spec normalize_legacy_snapshot(term()) :: term()
  def normalize_legacy_snapshot(%{"nodes" => nodes} = snapshot) when is_list(nodes) do
    Map.put(snapshot, "nodes", Enum.map(nodes, &normalize_legacy_node_snapshot/1))
  end

  def normalize_legacy_snapshot(snapshot), do: snapshot

  defp normalize_legacy_node_snapshot(%{} = node) do
    type = node["type"]

    node =
      Map.put_new(
        node,
        "composition_source_original_id",
        if(type in @composition_owner_types, do: node["parent_id"])
      )

    node =
      if type in @composition_owner_types do
        node
        |> Map.put_new("sequence_tracks", [])
        |> Map.put_new("sequence_visual_layers", [])
      else
        node
      end

    node
    |> normalize_legacy_resource_collection("sequence_tracks", &normalize_legacy_track_snapshot/1)
    |> normalize_legacy_resource_collection(
      "sequence_visual_layers",
      &normalize_legacy_layer_snapshot/1
    )
  end

  defp normalize_legacy_node_snapshot(node), do: node

  defp normalize_legacy_resource_collection(node, key, normalize) do
    case node[key] do
      resources when is_list(resources) -> Map.put(node, key, Enum.map(resources, normalize))
      _invalid -> node
    end
  end

  defp normalize_legacy_track_snapshot(%{} = track) do
    track
    |> Map.put_new("track_key", legacy_resource_key("track", track["original_id"]))
    |> Map.put_new("is_override", false)
    |> Map.put_new("overridden_fields", @track_override_fields)
    |> Map.put_new("removed", false)
  end

  defp normalize_legacy_track_snapshot(track), do: track

  defp normalize_legacy_layer_snapshot(%{} = layer) do
    layer
    |> Map.put_new("layer_key", legacy_resource_key("layer", layer["original_id"]))
    |> Map.put_new("overridden_fields", @layer_override_fields)
    |> Map.put_new("removed", false)
  end

  defp normalize_legacy_layer_snapshot(layer), do: layer

  defp legacy_resource_key(prefix, id) when is_integer(id) and id > 0, do: "#{prefix}-#{id}"
  defp legacy_resource_key(_prefix, _id), do: nil

  defp validate_flow_snapshot(snapshot) when is_map(snapshot) do
    with :ok <- validate_required_snapshot_keys(snapshot, @flow_snapshot_fields, :flow),
         :ok <- validate_flow_snapshot_payload(snapshot),
         :ok <- validate_snapshot_root_id(snapshot["original_id"], snapshot["original_id"]),
         {:ok, nodes} <- fetch_snapshot_list(snapshot, "nodes"),
         {:ok, connections} <- fetch_snapshot_list(snapshot, "connections"),
         {:ok, localization} <- fetch_snapshot_list(snapshot, "localization"),
         :ok <-
           LocalizationSnapshotCodec.validate_manifest(
             localization,
             snapshot["localization_manifest"]
           ),
         :ok <- validate_snapshot_nodes(nodes),
         :ok <- validate_snapshot_connections(connections, nodes) do
      validate_snapshot_localization(
        localization,
        nodes,
        snapshot["localization_manifest"]["target_locales"]
      )
    end
  end

  defp validate_flow_snapshot(snapshot), do: {:error, {:invalid_flow_snapshot, :expected_map, snapshot}}

  defp validate_flow_snapshot_payload(snapshot) do
    validators = [
      {"name", &nonempty_string?/1},
      {"shortcut", &optional_string?/1},
      {"description", &optional_string?/1},
      {"is_main", &is_boolean/1},
      {"settings", &is_map/1},
      {"scene_id", &optional_positive_integer?/1},
      {"asset_blob_hashes", &is_map/1},
      {"asset_metadata", &is_map/1},
      {"referenced_sheets", &is_map/1},
      {"localization_manifest", &is_map/1}
    ]

    validate_snapshot_fields(snapshot, :flow, validators)
  end

  defp validate_snapshot_fields(payload, kind, validators) do
    case Enum.find(validators, fn {field, validator} ->
           not validator.(payload[field])
         end) do
      nil -> :ok
      {field, _validator} -> invalid_snapshot_field(kind, field, payload[field])
    end
  end

  defp validate_snapshot_root_id(flow_id, flow_id) when is_integer(flow_id) and flow_id > 0, do: :ok

  defp validate_snapshot_root_id(snapshot_id, flow_id), do: {:error, {:snapshot_flow_id_mismatch, snapshot_id, flow_id}}

  defp validate_required_snapshot_keys(map, keys, kind) when is_map(map) do
    missing = Enum.reject(keys, &Map.has_key?(map, &1))

    case missing do
      [] -> :ok
      _missing -> {:error, {:missing_snapshot_fields, kind, missing}}
    end
  end

  defp validate_required_snapshot_keys(value, _keys, kind), do: {:error, {:invalid_snapshot_payload, kind, value}}

  defp invalid_snapshot_field(kind, field, value), do: {:error, {:invalid_snapshot_field, kind, field, value}}

  defp fetch_snapshot_list(snapshot, key, default \\ :missing) do
    value =
      case Map.fetch(snapshot, key) do
        {:ok, value} -> value
        :error -> default
      end

    if is_list(value),
      do: {:ok, value},
      else: {:error, {:invalid_flow_snapshot_collection, key, value}}
  end

  defp validate_snapshot_nodes(nodes) do
    with :ok <- validate_snapshot_entry_ids(nodes, :node),
         :ok <- validate_each_snapshot_node(nodes),
         :ok <- validate_dialogue_runtime_id_uniqueness(nodes),
         :ok <- validate_flow_node_cardinality(nodes),
         :ok <- validate_sequence_resource_ids(nodes, "sequence_tracks", :sequence_track),
         :ok <-
           validate_sequence_resource_ids(
             nodes,
             "sequence_visual_layers",
             :sequence_visual_layer
           ),
         :ok <- validate_snapshot_parents(nodes),
         :ok <- validate_snapshot_composition_sources(nodes) do
      SequenceCompositionIntegrity.validate_nodes(nodes)
    end
  end

  defp validate_flow_node_cardinality(nodes) do
    entry_count = Enum.count(nodes, &(&1["type"] == "entry"))
    exit_count = Enum.count(nodes, &(&1["type"] == "exit"))

    cond do
      entry_count != 1 -> {:error, {:invalid_snapshot_entry_count, entry_count}}
      exit_count < 1 -> {:error, {:invalid_snapshot_exit_count, exit_count}}
      true -> :ok
    end
  end

  defp validate_each_snapshot_node(nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_snapshot_node(node) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_snapshot_node(%{} = node) do
    with :ok <- validate_required_snapshot_keys(node, @node_snapshot_fields, :node),
         :ok <- validate_snapshot_node_fields(node) do
      validate_snapshot_node_type_payload(node)
    end
  end

  defp validate_snapshot_node(node), do: {:error, {:invalid_snapshot_node, node}}

  defp validate_snapshot_node_fields(node) do
    type = node["type"]
    parent_id = node["parent_id"]
    data = node["data"]

    cond do
      type not in FlowNode.node_types() ->
        {:error, {:invalid_snapshot_node_type, node["original_id"], type}}

      not is_number(node["position_x"]) ->
        invalid_snapshot_field(:node, "position_x", node["position_x"])

      not is_number(node["position_y"]) ->
        invalid_snapshot_field(:node, "position_y", node["position_y"])

      not is_map(data) ->
        invalid_snapshot_field(:node, "data", data)

      not optional_positive_integer?(data["audio_asset_id"]) ->
        invalid_snapshot_field(:node, "audio_asset_id", data["audio_asset_id"])

      not optional_positive_integer?(parent_id) ->
        {:error, {:invalid_snapshot_node_parent_id, node["original_id"], parent_id}}

      true ->
        :ok
    end
  end

  defp validate_snapshot_node_type_payload(%{"original_id" => node_id, "type" => "exit", "data" => data}),
    do: validate_flow_exit_target_contract(node_id, data)

  defp validate_snapshot_node_type_payload(%{"original_id" => node_id, "type" => "dialogue", "data" => data} = node) do
    with :ok <- validate_dialogue_runtime_ids(node_id, data),
         do: validate_composition_snapshot(node)
  end

  defp validate_snapshot_node_type_payload(%{"type" => "sequence"} = node), do: validate_sequence_snapshot(node)

  defp validate_snapshot_node_type_payload(_node), do: :ok

  defp validate_dialogue_runtime_ids(node_id, data) when is_map(data) do
    localization_id = data["localization_id"]
    responses = if Map.has_key?(data, "responses"), do: data["responses"], else: []

    cond do
      not RuntimeKey.valid_dialogue_id?(localization_id) ->
        {:error, {:invalid_snapshot_dialogue_localization_id, node_id, localization_id}}

      not is_list(responses) ->
        {:error, {:invalid_snapshot_dialogue_responses, node_id, responses}}

      true ->
        validate_snapshot_response_ids(node_id, responses)
    end
  end

  defp validate_snapshot_response_ids(node_id, responses) do
    response_ids =
      Enum.map(responses, fn
        %{} = response -> response["id"]
        _invalid_response -> nil
      end)

    cond do
      not Enum.all?(response_ids, &RuntimeKey.valid_response_id?/1) ->
        {:error, {:invalid_snapshot_dialogue_response_id, node_id, response_ids}}

      length(response_ids) != length(Enum.uniq(response_ids)) ->
        {:error, {:duplicate_snapshot_dialogue_response_id, node_id}}

      true ->
        :ok
    end
  end

  defp validate_dialogue_runtime_id_uniqueness(nodes) do
    localization_ids =
      for %{"type" => "dialogue", "data" => %{"localization_id" => localization_id}} <- nodes,
          do: localization_id

    if length(localization_ids) == length(Enum.uniq(localization_ids)),
      do: :ok,
      else: {:error, :duplicate_snapshot_dialogue_localization_id}
  end

  defp validate_flow_exit_target_contract(node_id, data) when is_map(data) do
    exit_mode = data["exit_mode"] || "terminal"
    target_type = data["target_type"]
    target_id = data["target_id"]

    cond do
      is_nil(target_type) and is_nil(target_id) ->
        :ok

      exit_mode != "terminal" ->
        {:error,
         {:invalid_flow_exit_target, node_id, :target_not_allowed_for_exit_mode, exit_mode, target_type, target_id}}

      target_type not in ~w(scene flow) ->
        {:error, {:invalid_flow_exit_target, node_id, :invalid_target_type, target_type, target_id}}

      not positive_integer?(target_id) ->
        {:error, {:invalid_flow_exit_target, node_id, :invalid_target_id, target_type, target_id}}

      true ->
        :ok
    end
  end

  defp normalized_flow_exit_target(data) do
    case {data["exit_mode"] || "terminal", data["target_type"], data["target_id"]} do
      {"terminal", target_type, target_id}
      when target_type in ["scene", "flow"] and is_integer(target_id) and
             target_id > 0 ->
        {target_type, target_id}

      _no_target ->
        nil
    end
  end

  defp validate_sequence_snapshot(node) do
    with :ok <- validate_sequence_config_snapshot(node), do: validate_composition_snapshot(node)
  end

  defp validate_composition_snapshot(node) do
    with {:ok, tracks} <- fetch_required_sequence_collection(node, "sequence_tracks"),
         {:ok, layers} <- fetch_required_sequence_collection(node, "sequence_visual_layers"),
         :ok <- validate_snapshot_entry_ids(tracks, :sequence_track),
         :ok <- validate_snapshot_entry_ids(layers, :sequence_visual_layer),
         :ok <- validate_sequence_track_payloads(tracks),
         :ok <- validate_sequence_visual_layer_payloads(layers),
         :ok <- validate_unique_sequence_resource_keys(node["original_id"], tracks, "track_key", :sequence_track),
         :ok <-
           validate_unique_sequence_resource_keys(
             node["original_id"],
             layers,
             "layer_key",
             :sequence_visual_layer
           ) do
      validate_unique_track_kinds(node["original_id"], tracks)
    end
  end

  defp fetch_required_sequence_collection(node, key) do
    case Map.fetch(node, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_sequence_snapshot_collection, node["original_id"], key, value}}
      :error -> {:error, {:missing_sequence_snapshot_collection, node["original_id"], key}}
    end
  end

  defp validate_sequence_config_snapshot(node) do
    case Map.fetch(node, "sequence_config") do
      {:ok, nil} ->
        {:error, {:invalid_sequence_config_snapshot, node["original_id"], nil}}

      {:ok, %{} = config} ->
        with :ok <- validate_required_snapshot_keys(config, @sequence_config_fields, :sequence_config),
             true <- bounded_nonempty_string?(config["name"], 200),
             true <- is_number(config["width"]),
             true <- is_number(config["height"]) do
          :ok
        else
          false -> {:error, {:invalid_sequence_config_snapshot, node["original_id"], config}}
          {:error, _reason} = error -> error
        end

      {:ok, config} ->
        {:error, {:invalid_sequence_config_snapshot, node["original_id"], config}}

      :error ->
        {:error, {:missing_sequence_config_snapshot, node["original_id"]}}
    end
  end

  defp validate_sequence_track_payloads(tracks) do
    Enum.reduce_while(tracks, :ok, fn track, :ok ->
      result =
        with :ok <-
               validate_required_snapshot_keys(
                 track,
                 @sequence_track_fields,
                 :sequence_track
               ),
             true <- valid_snapshot_string?(track["track_key"], 64),
             true <- is_boolean(track["is_override"]),
             true <- valid_override_fields?(track["overridden_fields"], @track_override_fields),
             true <- is_boolean(track["removed"]),
             true <- track["kind"] in SequenceTrack.kinds(),
             true <- is_integer(track["position"]),
             true <- optional_positive_integer?(track["asset_id"]),
             true <- valid_decimal_snapshot?(track["start_time"]),
             true <- valid_decimal_snapshot?(track["end_time"]),
             true <- valid_decimal_range_snapshot?(track["volume"], 0, 1) do
          :ok
        else
          false -> {:error, {:invalid_sequence_track_snapshot, track}}
          {:error, _reason} = error -> error
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_sequence_visual_layer_payloads(layers) do
    Enum.reduce_while(layers, :ok, fn layer, :ok ->
      result =
        with :ok <-
               validate_required_snapshot_keys(
                 layer,
                 @sequence_visual_layer_fields,
                 :sequence_visual_layer
               ),
             true <- valid_snapshot_string?(layer["layer_key"], 64),
             true <- valid_override_fields?(layer["overridden_fields"], @layer_override_fields),
             true <- is_boolean(layer["removed"]),
             true <- optional_positive_integer?(layer["asset_id"]),
             true <- layer["kind"] in SequenceVisualLayer.kinds(),
             true <- optional_bounded_string?(layer["label"], 120),
             true <- is_integer(layer["z_index"]),
             true <- layer["slot"] in SequenceVisualLayer.slots(),
             true <- normalized_snapshot_fields?(layer, ~w(x y anchor_x anchor_y opacity)),
             true <- unit_dimension_snapshot_fields?(layer, ~w(width height)),
             true <- layer["fit"] in SequenceVisualLayer.fits(),
             true <- is_boolean(layer["visible"]) do
          :ok
        else
          false -> {:error, {:invalid_sequence_visual_layer_snapshot, layer}}
          {:error, _reason} = error -> error
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_unique_track_kinds(node_id, tracks) do
    kinds = for track <- tracks, track["is_override"] == false, do: track["kind"]

    if length(kinds) == length(Enum.uniq(kinds)),
      do: :ok,
      else: {:error, {:duplicate_sequence_track_kind, node_id}}
  end

  defp validate_unique_sequence_resource_keys(node_id, resources, key, kind) do
    keys = Enum.map(resources, & &1[key])

    if length(keys) == length(Enum.uniq(keys)),
      do: :ok,
      else: {:error, {:duplicate_sequence_resource_key, kind, node_id}}
  end

  defp validate_sequence_resource_ids(nodes, key, kind) do
    resources =
      Enum.flat_map(nodes, fn
        %{"type" => type} = node when type in @composition_owner_types -> node[key]
        _node -> []
      end)

    validate_snapshot_entry_ids(resources, kind)
  end

  defp validate_snapshot_connections(connections, nodes) do
    with :ok <- validate_snapshot_entry_ids(connections, :connection),
         :ok <- validate_each_snapshot_connection(connections, nodes) do
      validate_unique_connection_tuples(connections)
    end
  end

  defp validate_each_snapshot_connection(connections, nodes) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      case validate_snapshot_connection(connection, nodes) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_snapshot_connection(%{} = connection, nodes) do
    with :ok <-
           validate_required_snapshot_keys(
             connection,
             @connection_snapshot_fields,
             :connection
           ),
         :ok <- validate_snapshot_connection_indexes(connection, length(nodes)),
         :ok <- validate_snapshot_connection_node_types(connection, nodes) do
      validate_snapshot_connection_fields(connection)
    end
  end

  defp validate_snapshot_connection(connection, _nodes), do: {:error, {:invalid_snapshot_connection, connection}}

  defp validate_snapshot_connection_indexes(connection, node_count) do
    source_index = connection["source_node_index"]
    target_index = connection["target_node_index"]
    connection_id = connection["original_id"]

    cond do
      not valid_snapshot_index?(source_index, node_count) ->
        {:error, {:invalid_snapshot_connection_endpoint, connection_id, :source, source_index}}

      not valid_snapshot_index?(target_index, node_count) ->
        {:error, {:invalid_snapshot_connection_endpoint, connection_id, :target, target_index}}

      source_index == target_index ->
        {:error, {:invalid_snapshot_self_connection, connection_id, source_index}}

      true ->
        :ok
    end
  end

  defp validate_snapshot_connection_node_types(connection, nodes) do
    source_type = Enum.at(nodes, connection["source_node_index"])["type"]
    target_type = Enum.at(nodes, connection["target_node_index"])["type"]

    cond do
      source_type == "sequence" ->
        {:error, {:invalid_snapshot_sequence_connection, connection["original_id"], :source}}

      target_type == "sequence" ->
        {:error, {:invalid_snapshot_sequence_connection, connection["original_id"], :target}}

      true ->
        :ok
    end
  end

  defp validate_snapshot_connection_fields(connection) do
    source_pin = connection["source_pin"]
    target_pin = connection["target_pin"]
    label = connection["label"]

    cond do
      not valid_snapshot_string?(source_pin, 100) ->
        {:error, {:invalid_snapshot_connection_pin, connection["original_id"], :source, source_pin}}

      not valid_snapshot_string?(target_pin, 100) ->
        {:error, {:invalid_snapshot_connection_pin, connection["original_id"], :target, target_pin}}

      not optional_bounded_string?(label, 200) ->
        {:error, {:invalid_snapshot_connection_label, connection["original_id"], label}}

      true ->
        :ok
    end
  end

  defp validate_unique_connection_tuples(connections) do
    tuples =
      Enum.map(connections, fn connection ->
        {
          connection["source_node_index"],
          connection["source_pin"],
          connection["target_node_index"],
          connection["target_pin"]
        }
      end)

    if length(tuples) == length(Enum.uniq(tuples)),
      do: :ok,
      else: {:error, :duplicate_snapshot_connection}
  end

  defp validate_snapshot_localization(localization, nodes, target_locales) do
    with {:ok, {sources, target_locales}} <-
           validate_snapshot_localization_inventory(
             localization,
             nodes,
             target_locales
           ) do
      validate_complete_snapshot_localization(localization, sources, target_locales)
    end
  end

  defp complete_missing_snapshot_localization(localization, nodes, target_locales) do
    with {:ok, {sources, target_locales}} <-
           validate_snapshot_localization_inventory(
             localization,
             nodes,
             target_locales
           ) do
      {:ok,
       LocalizationSnapshotCodec.complete_pending_rows(
         localization,
         pending_localization_sources(sources),
         target_locales
       )}
    end
  end

  defp validate_snapshot_localization_inventory(localization, nodes, target_locales) do
    with :ok <- validate_snapshot_localization_node_shapes(nodes),
         nodes_by_id = Map.new(nodes, &{&1["original_id"], &1}),
         sources = snapshot_localization_sources(nodes),
         :ok <-
           validate_snapshot_localization_rows(
             localization,
             nodes_by_id,
             sources
           ),
         :ok <- validate_unique_snapshot_localization_rows(localization),
         {:ok, target_locales} <-
           validate_snapshot_localization_locales(localization, target_locales) do
      {:ok, {sources, target_locales}}
    end
  end

  defp validate_snapshot_localization_node_shapes(nodes) when is_list(nodes) do
    case Enum.find(nodes, fn
           %{"type" => type} = node when type in ~w(dialogue exit) ->
             not is_map(node["data"])

           node ->
             not is_map(node)
         end) do
      nil -> :ok
      node -> {:error, {:invalid_flow_localization_source_node, node}}
    end
  end

  defp validate_snapshot_localization_node_shapes(nodes), do: {:error, {:invalid_flow_localization_source_nodes, nodes}}

  defp validate_snapshot_localization_rows(localization, nodes_by_id, sources) do
    Enum.reduce_while(localization, :ok, fn row, :ok ->
      continue_snapshot_localization_validation(validate_snapshot_localization_row(row, nodes_by_id, sources))
    end)
  end

  defp continue_snapshot_localization_validation(:ok), do: {:cont, :ok}

  defp continue_snapshot_localization_validation({:error, _reason} = error), do: {:halt, error}

  defp validate_unique_snapshot_localization_rows(localization) do
    keys =
      Enum.map(localization, fn row ->
        {row["source_id"], row["source_field"], row["locale_code"]}
      end)

    if length(keys) == length(Enum.uniq(keys)),
      do: :ok,
      else: {:error, :duplicate_flow_localization_snapshot}
  end

  defp validate_snapshot_localization_row(%{} = row, nodes_by_id, sources) do
    source_node = Map.get(nodes_by_id, row["source_id"])
    source = Map.get(sources, {row["source_id"], row["source_field"]})

    with :ok <-
           validate_exact_snapshot_keys(
             row,
             @localization_snapshot_fields,
             :localization
           ),
         true <- row["source_type"] == "flow_node",
         true <- positive_integer?(row["source_id"]),
         true <- is_map(source_node),
         true <- is_map(source),
         true <- SourceContract.field?(row["source_type"], row["source_field"]),
         true <-
           SourceContract.localizable_source_field?(
             "flow_node",
             %{type: source_node["type"], data: source_node["data"], deleted_at: nil},
             row["source_field"]
           ),
         true <- is_binary(row["source_text"]),
         true <- is_binary(row["source_text_hash"]),
         true <- optional_sha256?(row["translated_source_hash"]),
         true <- LocaleCode.valid?(row["locale_code"]),
         true <- row["locale_code"] == LocaleCode.normalize(row["locale_code"]),
         true <- optional_string?(row["translated_text"]),
         true <- row["status"] in ~w(pending draft in_progress review final),
         true <- row["vo_status"] in ~w(none needed recorded approved),
         true <- optional_positive_integer?(row["vo_asset_id"]),
         true <- optional_string?(row["translator_notes"]),
         true <- optional_string?(row["reviewer_notes"]),
         true <- optional_positive_integer?(row["speaker_sheet_id"]),
         true <-
           is_nil(row["word_count"]) or
             (is_integer(row["word_count"]) and row["word_count"] >= 0),
         true <- is_boolean(row["machine_translated"]),
         true <- valid_snapshot_datetime?(row["last_translated_at"]),
         true <- valid_snapshot_datetime?(row["last_reviewed_at"]),
         true <- optional_positive_integer?(row["translated_by_id"]),
         true <- optional_positive_integer?(row["reviewed_by_id"]),
         true <- valid_snapshot_datetime?(row["archived_at"]),
         true <- optional_string?(row["archive_reason"]) do
      validate_snapshot_localization_semantics(row, source)
    else
      false ->
        if positive_integer?(row["source_id"]) and
             not Map.has_key?(nodes_by_id, row["source_id"]) do
          {:error, {:localization_source_outside_snapshot, row["source_id"]}}
        else
          {:error, {:invalid_flow_localization_snapshot, row}}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_snapshot_localization_row(row, _nodes_by_id, _sources),
    do: {:error, {:invalid_flow_localization_snapshot, row}}

  defp validate_exact_snapshot_keys(map, expected_keys, kind) do
    expected = MapSet.new(expected_keys)
    actual = MapSet.new(Map.keys(map))

    if actual == expected do
      :ok
    else
      {:error,
       {:invalid_snapshot_fields, kind,
        %{
          missing:
            expected
            |> MapSet.difference(actual)
            |> MapSet.to_list()
            |> Enum.sort(),
          unexpected:
            actual
            |> MapSet.difference(expected)
            |> MapSet.to_list()
            |> Enum.sort()
        }}}
    end
  end

  defp validate_snapshot_localization_semantics(row, source) do
    expected_hash = source_text_hash(source.text)

    with :ok <- validate_localization_source_text(row, source.text),
         :ok <- validate_localization_source_hash(row, expected_hash),
         :ok <- validate_localization_word_count(row, source.text),
         :ok <- validate_localization_speaker(row, source.speaker_sheet_id),
         :ok <- validate_active_localization_state(row),
         :ok <- validate_localization_translation_state(row),
         :ok <- validate_localization_placeholders(row) do
      validate_localization_voiceover_state(row, source.metadata)
    end
  end

  defp validate_localization_source_text(row, expected) do
    if row["source_text"] == expected,
      do: :ok,
      else: {:error, {:localization_source_text_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_source_hash(row, expected) do
    if row["source_text_hash"] == expected,
      do: :ok,
      else: {:error, {:localization_source_text_hash_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_word_count(row, source_text) do
    if row["word_count"] == HtmlUtils.word_count(source_text),
      do: :ok,
      else: {:error, {:localization_word_count_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_localization_speaker(row, expected) do
    if row["speaker_sheet_id"] == expected,
      do: :ok,
      else: {:error, {:localization_speaker_mismatch, row["source_id"], row["source_field"]}}
  end

  defp validate_active_localization_state(row) do
    if is_nil(row["archived_at"]) and is_nil(row["archive_reason"]) do
      :ok
    else
      {:error, {:invalid_active_localization_archive_state, row["source_id"], row["source_field"], row["locale_code"]}}
    end
  end

  defp validate_localization_translation_state(row) do
    if coherent_translation_state?(row),
      do: :ok,
      else: {:error, {:invalid_localization_translation_state, row["source_id"], row["source_field"], row["locale_code"]}}
  end

  defp validate_localization_placeholders(%{"translated_text" => translated_text} = row)
       when is_binary(translated_text) do
    case HtmlHandler.validate_placeholders(row["source_text"], translated_text) do
      :ok ->
        :ok

      {:error, details} ->
        {:error, {:invalid_localization_placeholders, row["source_id"], row["source_field"], row["locale_code"], details}}
    end
  end

  defp validate_localization_placeholders(_row), do: :ok

  defp validate_localization_voiceover_state(row, metadata) do
    if coherent_voiceover_state?(row, metadata),
      do: :ok,
      else: {:error, {:invalid_localization_voiceover_state, row["source_id"], row["source_field"], row["locale_code"]}}
  end

  defp coherent_translation_state?(row) do
    translated? = present_string?(row["translated_text"])
    translated_hash = row["translated_source_hash"]

    coherent_translation_text?(row["translated_text"]) and
      coherent_translation_hash?(translated?, translated_hash) and
      coherent_machine_translation?(row["machine_translated"], translated?) and
      coherent_final_translation?(
        row["status"],
        translated?,
        translated_hash,
        row["source_text_hash"]
      )
  end

  defp coherent_translation_text?(nil), do: true
  defp coherent_translation_text?(text), do: present_string?(text)

  defp coherent_translation_hash?(false, nil), do: true
  defp coherent_translation_hash?(false, _translated_hash), do: false
  defp coherent_translation_hash?(true, translated_hash), do: sha256?(translated_hash)

  defp coherent_machine_translation?(false, _translated?), do: true
  defp coherent_machine_translation?(true, translated?), do: translated?

  defp coherent_final_translation?("final", true, translated_hash, source_hash), do: translated_hash == source_hash

  defp coherent_final_translation?("final", false, _translated_hash, _source_hash), do: false

  defp coherent_final_translation?(_status, _translated?, _translated_hash, _source_hash), do: true

  defp coherent_voiceover_state?(row, %{vo_eligible: false}) do
    row["vo_status"] == "none" and is_nil(row["vo_asset_id"])
  end

  defp coherent_voiceover_state?(row, %{vo_eligible: true}) do
    row["vo_status"] not in ~w(recorded approved) or positive_integer?(row["vo_asset_id"])
  end

  defp validate_snapshot_localization_locales(localization, target_locales) when is_list(target_locales) do
    target_locales = MapSet.new(target_locales)

    case Enum.find(localization, fn row ->
           not MapSet.member?(target_locales, row["locale_code"])
         end) do
      nil ->
        {:ok, target_locales}

      row ->
        {:error, {:localization_locale_outside_snapshot, row["source_id"], row["source_field"], row["locale_code"]}}
    end
  end

  defp validate_snapshot_localization_locales(_localization, target_locales),
    do: {:error, {:invalid_localization_target_locales, target_locales}}

  defp validate_complete_snapshot_localization(localization, sources, target_locales) do
    expected_keys =
      for {source_key, _source} <- sources,
          locale <- target_locales,
          into: MapSet.new() do
        {source_key, locale}
      end

    actual_keys =
      MapSet.new(localization, fn row ->
        {{row["source_id"], row["source_field"]}, row["locale_code"]}
      end)

    if actual_keys == expected_keys do
      :ok
    else
      {:error,
       {:incomplete_flow_localization_snapshot,
        %{
          missing:
            expected_keys
            |> MapSet.difference(actual_keys)
            |> MapSet.to_list()
            |> Enum.sort(),
          unexpected:
            actual_keys
            |> MapSet.difference(expected_keys)
            |> MapSet.to_list()
            |> Enum.sort()
        }}}
    end
  end

  defp snapshot_localization_sources(nodes) do
    Enum.reduce(nodes, %{}, fn node, sources ->
      Enum.reduce(node_localization_sources(node), sources, fn {key, source}, acc ->
        Map.put(acc, key, source)
      end)
    end)
  end

  defp pending_localization_sources(sources) do
    Enum.map(sources, fn {{source_id, source_field}, source} ->
      %{
        "source_type" => "flow_node",
        "source_id" => source_id,
        "source_field" => source_field,
        "source_text" => source.text,
        "speaker_sheet_id" => source.speaker_sheet_id
      }
    end)
  end

  defp node_localization_sources(%{"original_id" => node_id, "type" => "dialogue", "data" => data}) when is_map(data) do
    speaker_sheet_id = data["speaker_sheet_id"]

    []
    |> maybe_add_localization_source(node_id, "text", data["text"], speaker_sheet_id)
    |> maybe_add_localization_source(
      node_id,
      "stage_directions",
      data["stage_directions"],
      nil
    )
    |> maybe_add_localization_source(node_id, "menu_text", data["menu_text"], nil)
    |> add_response_localization_sources(node_id, data["responses"], speaker_sheet_id)
  end

  defp node_localization_sources(%{"original_id" => node_id, "type" => "exit", "data" => data}) when is_map(data) do
    maybe_add_localization_source([], node_id, "label", data["label"], nil)
  end

  defp node_localization_sources(_node), do: []

  defp add_response_localization_sources(sources, node_id, responses, speaker_sheet_id) when is_list(responses) do
    Enum.reduce(responses, sources, fn
      %{"id" => response_id, "text" => text}, acc when is_binary(response_id) ->
        maybe_add_localization_source(
          acc,
          node_id,
          "response.#{response_id}.text",
          text,
          speaker_sheet_id
        )

      _response, acc ->
        acc
    end)
  end

  defp add_response_localization_sources(sources, _node_id, _responses, _speaker_sheet_id), do: sources

  defp maybe_add_localization_source(sources, node_id, field, text, speaker_sheet_id) when is_binary(text) do
    if HtmlUtils.strip_html(text) == "" do
      sources
    else
      metadata = SourceContract.field_metadata("flow_node", field)

      [
        {{node_id, field},
         %{
           text: text,
           speaker_sheet_id: speaker_sheet_id,
           metadata: metadata
         }}
        | sources
      ]
    end
  end

  defp maybe_add_localization_source(sources, _node_id, _field, _text, _speaker_sheet_id), do: sources

  defp source_text_hash(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp optional_sha256?(nil), do: true
  defp optional_sha256?(value), do: sha256?(value)

  defp sha256?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp sha256?(_value), do: false

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp validate_snapshot_entry_ids(entries, kind) do
    case Enum.find(entries, fn entry ->
           not is_map(entry) or not positive_integer?(entry["original_id"])
         end) do
      nil ->
        ids = Enum.map(entries, & &1["original_id"])

        if length(ids) == length(Enum.uniq(ids)),
          do: :ok,
          else: {:error, {:duplicate_snapshot_original_id, kind}}

      invalid ->
        {:error, {:invalid_snapshot_original_id, kind, invalid}}
    end
  end

  defp validate_snapshot_parents(nodes) do
    nodes_by_id = Map.new(nodes, &{&1["original_id"], &1})

    with :ok <- validate_parent_targets(nodes, nodes_by_id),
         false <- snapshot_parent_cycle?(nodes, nodes_by_id) do
      :ok
    else
      true -> {:error, :snapshot_node_parent_cycle}
      {:error, _reason} = error -> error
    end
  end

  defp validate_parent_targets(nodes, nodes_by_id) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      continue_parent_target_validation(validate_parent_target(node, nodes_by_id))
    end)
  end

  defp continue_parent_target_validation(:ok), do: {:cont, :ok}
  defp continue_parent_target_validation({:error, _reason} = error), do: {:halt, error}

  defp validate_parent_target(%{"parent_id" => nil}, _nodes_by_id), do: :ok

  defp validate_parent_target(node, nodes_by_id) do
    parent_id = node["parent_id"]
    node_id = node["original_id"]

    case Map.get(nodes_by_id, parent_id) do
      %{"type" => "sequence"} when parent_id != node_id ->
        :ok

      %{"type" => "sequence"} ->
        {:error, {:invalid_snapshot_node_parent, node_id, parent_id, :self}}

      parent ->
        {:error, {:invalid_snapshot_node_parent, node_id, parent_id, parent}}
    end
  end

  defp snapshot_parent_cycle?(nodes, nodes_by_id) do
    Enum.any?(nodes, fn node ->
      walk_snapshot_parents(node["original_id"], nodes_by_id, MapSet.new())
    end)
  end

  defp validate_snapshot_composition_sources(nodes) do
    nodes_by_id = Map.new(nodes, &{&1["original_id"], &1})

    with :ok <- validate_composition_source_targets(nodes, nodes_by_id),
         false <- snapshot_composition_source_cycle?(nodes, nodes_by_id) do
      :ok
    else
      true -> {:error, :snapshot_composition_source_cycle}
      {:error, _reason} = error -> error
    end
  end

  defp validate_composition_source_targets(nodes, nodes_by_id) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case validate_composition_source_target(node, nodes_by_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_composition_source_target(%{"composition_source_original_id" => nil}, _nodes_by_id), do: :ok

  defp validate_composition_source_target(node, nodes_by_id) do
    node_id = node["original_id"]
    source_id = node["composition_source_original_id"]
    source = Map.get(nodes_by_id, source_id)

    cond do
      node["type"] not in @composition_owner_types ->
        {:error, {:invalid_snapshot_composition_source, node_id, source_id, :invalid_owner_type}}

      node_id == source_id ->
        {:error, {:invalid_snapshot_composition_source, node_id, source_id, :self}}

      not positive_integer?(source_id) ->
        {:error, {:invalid_snapshot_composition_source, node_id, source_id, :invalid_id}}

      not is_map(source) or source["type"] not in @composition_owner_types ->
        {:error, {:invalid_snapshot_composition_source, node_id, source_id, source}}

      true ->
        :ok
    end
  end

  defp snapshot_composition_source_cycle?(nodes, nodes_by_id) do
    Enum.any?(nodes, fn node ->
      walk_snapshot_composition_sources(node["original_id"], nodes_by_id, MapSet.new())
    end)
  end

  defp walk_snapshot_composition_sources(node_id, nodes_by_id, seen) do
    case get_in(nodes_by_id, [node_id, "composition_source_original_id"]) do
      nil ->
        false

      source_id ->
        if MapSet.member?(seen, source_id) do
          true
        else
          walk_snapshot_composition_sources(
            source_id,
            nodes_by_id,
            MapSet.put(seen, node_id)
          )
        end
    end
  end

  defp walk_snapshot_parents(node_id, nodes_by_id, seen) do
    case get_in(nodes_by_id, [node_id, "parent_id"]) do
      nil ->
        false

      parent_id ->
        if MapSet.member?(seen, parent_id) do
          true
        else
          walk_snapshot_parents(parent_id, nodes_by_id, MapSet.put(seen, node_id))
        end
    end
  end

  defp rebuild_instantiated_flow_references(nodes, project_id) do
    case Enum.reduce_while(nodes, :ok, fn node, result ->
           continue_node_reference_rebuild(
             node,
             result,
             project_id
           )
         end) do
      :ok -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp continue_node_reference_rebuild(node, :ok, project_id) do
    case rebuild_node_references(node, project_id) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp rebuild_node_references(node, project_id) do
    with :ok <-
           normalize_reference_write_result(
             References.update_flow_node_entity_references(
               node,
               project_id: project_id
             )
           ) do
      normalize_reference_write_result(References.update_flow_node_variable_references(node))
    end
  end

  defp normalize_reference_write_result(:ok), do: :ok
  defp normalize_reference_write_result({:error, reason}), do: {:error, reason}

  defp normalize_reference_write_result(other), do: {:error, {:unexpected_reference_write_result, other}}

  defp nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp optional_string?(value), do: is_nil(value) or is_binary(value)

  defp optional_bounded_string?(nil, _max_length), do: true

  defp optional_bounded_string?(value, max_length), do: is_binary(value) and String.length(value) <= max_length

  defp bounded_nonempty_string?(value, max_length) do
    is_binary(value) and String.trim(value) != "" and String.length(value) <= max_length
  end

  defp optional_positive_integer?(value), do: is_nil(value) or positive_integer?(value)

  defp normalized_snapshot_fields?(payload, fields) do
    Enum.all?(fields, fn field ->
      value = payload[field]
      is_number(value) and value >= 0 and value <= 1
    end)
  end

  defp unit_dimension_snapshot_fields?(payload, fields) do
    Enum.all?(fields, fn field ->
      value = payload[field]
      is_number(value) and value > 0 and value <= 1
    end)
  end

  defp valid_decimal_snapshot?(nil), do: true

  defp valid_decimal_snapshot?(value) when is_binary(value) do
    case Decimal.parse(value) do
      {_decimal, ""} -> true
      _invalid -> false
    end
  end

  defp valid_decimal_snapshot?(_value), do: false

  defp valid_decimal_range_snapshot?(nil, _minimum, _maximum), do: true

  defp valid_decimal_range_snapshot?(value, minimum, maximum) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        try do
          Decimal.compare(decimal, minimum) in [:eq, :gt] and
            Decimal.compare(decimal, maximum) in [:eq, :lt]
        rescue
          Decimal.Error -> false
        end

      _invalid ->
        false
    end
  end

  defp valid_decimal_range_snapshot?(_value, _minimum, _maximum), do: false

  defp valid_snapshot_datetime?(nil), do: true
  defp valid_snapshot_datetime?(%DateTime{}), do: true

  defp valid_snapshot_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_snapshot_datetime?(_value), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_snapshot_index?(value, length), do: is_integer(value) and value >= 0 and value < length

  defp valid_snapshot_string?(value, max_length),
    do: is_binary(value) and value != "" and String.length(value) <= max_length

  defp valid_override_fields?(fields, allowed) when is_list(fields) do
    Enum.all?(fields, &is_binary/1) and length(fields) == length(Enum.uniq(fields)) and
      Enum.all?(fields, &(&1 in allowed))
  end

  defp valid_override_fields?(_fields, _allowed), do: false

  defp link_snapshot_node_parents(repo, nodes_data, node_id_map, project_id, opts) do
    nodes_by_original_id =
      nodes_data
      |> Enum.reject(&is_nil(&1["original_id"]))
      |> Map.new(&{&1["original_id"], &1})

    Enum.reduce_while(nodes_data, {:ok, 0}, fn node_data, acc ->
      link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map, project_id, opts)
    end)
  end

  defp link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map, project_id, opts) do
    link_snapshot_node_parent(
      repo,
      node_data,
      acc,
      nodes_by_original_id,
      node_id_map,
      project_id,
      opts,
      node_data["parent_id"]
    )
  end

  defp link_snapshot_node_parent(
         _repo,
         _node_data,
         {:ok, count},
         _nodes_by_original_id,
         _node_id_map,
         _project_id,
         _opts,
         nil
       ) do
    {:cont, {:ok, count}}
  end

  defp link_snapshot_node_parent(
         repo,
         node_data,
         {:ok, count},
         nodes_by_original_id,
         node_id_map,
         project_id,
         opts,
         parent_original_id
       ) do
    if MaterializationHelpers.exact_materialization?(opts) do
      link_exact_snapshot_node_parent(repo, node_data, count, node_id_map, parent_original_id, project_id)
    else
      link_portable_snapshot_node_parent(
        repo,
        node_data,
        count,
        nodes_by_original_id,
        node_id_map,
        parent_original_id
      )
    end
  end

  defp link_exact_snapshot_node_parent(repo, node_data, count, node_id_map, parent_original_id, project_id) do
    child_id = Map.get(node_id_map, node_data["original_id"])

    with child_id when is_integer(child_id) <- child_id,
         {:ok, parent_id} <- exact_snapshot_node_parent_id(repo, node_id_map, parent_original_id, project_id),
         %FlowNode{} = child <- repo.get(FlowNode, child_id),
         {:ok, _updated_child} <-
           child
           |> FlowNode.reparent_changeset(%{parent_id: parent_id})
           |> repo.update() do
      {:cont, {:ok, count + 1}}
    else
      reason ->
        {:halt, {:error, {:invalid_snapshot_node_parent, node_data["original_id"], parent_original_id, reason}}}
    end
  end

  defp exact_snapshot_node_parent_id(repo, node_id_map, parent_original_id, project_id) do
    case Map.fetch(node_id_map, parent_original_id) do
      {:ok, parent_id} when is_integer(parent_id) ->
        {:ok, parent_id}

      _missing ->
        if is_integer(parent_original_id) and
             repo.exists?(
               from(node in FlowNode,
                 join: flow in Flow,
                 on: flow.id == node.flow_id,
                 where: node.id == ^parent_original_id and flow.project_id == ^project_id
               )
             ),
           do: {:ok, parent_original_id},
           else: {:error, {:exact_snapshot_fk_not_materializable, :flow_node, :parent_id, parent_original_id}}
    end
  end

  defp link_portable_snapshot_node_parent(repo, node_data, count, nodes_by_original_id, node_id_map, parent_original_id) do
    with %{"type" => "sequence"} <- Map.get(nodes_by_original_id, parent_original_id),
         child_id when is_integer(child_id) <- Map.get(node_id_map, node_data["original_id"]),
         parent_id when is_integer(parent_id) <- Map.get(node_id_map, parent_original_id),
         false <- child_id == parent_id,
         %FlowNode{} = child <- repo.get(FlowNode, child_id),
         {:ok, _updated_child} <-
           child
           |> FlowNode.reparent_changeset(%{parent_id: parent_id})
           |> repo.update() do
      {:cont, {:ok, count + 1}}
    else
      reason ->
        {:halt, {:error, {:invalid_snapshot_node_parent, node_data["original_id"], parent_original_id, reason}}}
    end
  end

  defp link_snapshot_node_composition_sources(repo, nodes_data, node_id_map) do
    Enum.reduce_while(nodes_data, {:ok, 0}, fn node_data, result ->
      link_snapshot_node_composition_source(repo, node_data, node_id_map, result)
    end)
  end

  defp link_snapshot_node_composition_source(
         _repo,
         %{"composition_source_original_id" => nil},
         _node_id_map,
         {:ok, count}
       ), do: {:cont, {:ok, count}}

  defp link_snapshot_node_composition_source(repo, node_data, node_id_map, {:ok, count}) do
    source_original_id = node_data["composition_source_original_id"]
    node_id = Map.get(node_id_map, node_data["original_id"])
    source_id = Map.get(node_id_map, source_original_id)

    with node_id when is_integer(node_id) <- node_id,
         source_id when is_integer(source_id) <- source_id,
         %FlowNode{} = node <- repo.get(FlowNode, node_id),
         {:ok, _node} <-
           node
           |> FlowNode.composition_source_changeset(%{composition_source_id: source_id})
           |> repo.update() do
      {:cont, {:ok, count + 1}}
    else
      reason ->
        {:halt, {:error, {:invalid_snapshot_composition_source, node_data["original_id"], source_original_id, reason}}}
    end
  end

  defp insert_sequence_resources(repo, nodes_data, node_id_map, snapshot, project_id, opts, now) do
    Enum.reduce_while(
      nodes_data,
      {:ok, %{configs: 0, track_id_map: %{}, visual_layer_id_map: %{}}},
      &insert_sequence_resources_for_node(&1, &2, repo, node_id_map, snapshot, project_id, opts, now)
    )
  end

  defp insert_sequence_resources_for_node(node_data, {:ok, result}, repo, node_id_map, snapshot, project_id, opts, now) do
    if materialize_sequence_resources?(node_data, opts) do
      node_id = Map.fetch!(node_id_map, node_data["original_id"])

      with {:ok, config_count} <-
             insert_composition_config(
               repo,
               node_id,
               node_data,
               opts,
               now
             ),
           {:ok, track_id_map} <-
             insert_sequence_tracks(
               repo,
               node_id,
               node_data["sequence_tracks"] || [],
               snapshot,
               project_id,
               opts,
               now
             ),
           {:ok, visual_layer_id_map} <-
             insert_sequence_visual_layers(
               repo,
               node_id,
               node_data["sequence_visual_layers"] || [],
               snapshot,
               project_id,
               opts,
               now
             ) do
        {:cont,
         {:ok,
          %{
            configs: result.configs + config_count,
            track_id_map: Map.merge(result.track_id_map, track_id_map),
            visual_layer_id_map: Map.merge(result.visual_layer_id_map, visual_layer_id_map)
          }}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    else
      {:cont, {:ok, result}}
    end
  end

  defp materialize_sequence_resources?(%{"type" => "sequence"}, _opts), do: true
  defp materialize_sequence_resources?(%{"type" => "dialogue"}, _opts), do: true

  defp materialize_sequence_resources?(node_data, opts) when is_map(node_data) do
    MaterializationHelpers.exact_materialization?(opts) and
      residual_sequence_snapshot_resources?(node_data)
  end

  defp materialize_sequence_resources?(_node_data, _opts), do: false

  defp insert_composition_config(repo, node_id, %{"type" => "sequence"} = node_data, opts, now),
    do: insert_sequence_config_for_mode(repo, node_id, node_data["sequence_config"], opts, now)

  defp insert_composition_config(_repo, _node_id, %{"type" => "dialogue"}, _opts, _now), do: {:ok, 0}

  defp insert_composition_config(repo, node_id, node_data, opts, now),
    do: insert_sequence_config_for_mode(repo, node_id, node_data["sequence_config"], opts, now)

  defp residual_sequence_snapshot_resources?(node_data) do
    not is_nil(node_data["sequence_config"]) or
      match?([_ | _], node_data["sequence_tracks"]) or
      match?([_ | _], node_data["sequence_visual_layers"])
  end

  defp restore_exact_authored_node_types(repo, nodes_data, node_id_map, opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      do_restore_exact_authored_node_types(repo, nodes_data, node_id_map, opts)
    else
      :ok
    end
  end

  defp do_restore_exact_authored_node_types(repo, nodes_data, node_id_map, opts) do
    nodes_data
    |> Enum.filter(&temporary_sequence_node?(&1, opts))
    |> Enum.reduce_while(:ok, fn node_data, :ok ->
      node_id = Map.fetch!(node_id_map, node_data["original_id"])

      case repo.update_all(
             from(node in FlowNode, where: node.id == ^node_id),
             set: [type: node_data["type"]]
           ) do
        {1, _rows} -> {:cont, :ok}
        {count, _rows} -> {:halt, {:error, {:materialized_row_count_mismatch, :flow_node, node_id, count}}}
      end
    end)
  end

  defp insert_sequence_config_for_mode(repo, node_id, nil, opts, now) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: {:ok, 0},
      else: insert_sequence_config(repo, node_id, nil, now)
  end

  defp insert_sequence_config_for_mode(repo, node_id, config_data, _opts, now) do
    insert_sequence_config(repo, node_id, config_data, now)
  end

  defp insert_sequence_config(_repo, node_id, nil, _now), do: {:error, {:invalid_sequence_config_snapshot, node_id, nil}}

  defp insert_sequence_config(repo, node_id, config_data, now) when is_map(config_data) do
    attrs =
      config_data
      |> Map.take(["name", "width", "height"])
      |> Map.put("flow_node_id", node_id)

    %SequenceConfig{inserted_at: now, updated_at: now}
    |> SequenceConfig.create_changeset(attrs)
    |> repo.insert()
    |> inserted_resource_count()
  end

  defp insert_sequence_config(_repo, _node_id, config_data, _now) do
    {:error, {:invalid_sequence_config_snapshot, config_data}}
  end

  defp insert_sequence_tracks(repo, node_id, tracks, snapshot, project_id, opts, now) when is_list(tracks) do
    insert_sequence_items(
      tracks,
      :sequence_track,
      fn track_data ->
        asset_id =
          resolve_flow_asset(
            track_data["asset_id"],
            snapshot,
            project_id,
            opts,
            "audio/",
            :sequence_track
          )

        attrs =
          track_data
          |> Map.take([
            "kind",
            "track_key",
            "is_override",
            "overridden_fields",
            "removed",
            "position",
            "start_time",
            "end_time",
            "volume"
          ])
          |> Map.put("flow_node_id", node_id)
          |> Map.put("asset_id", asset_id)

        %SequenceTrack{inserted_at: now, updated_at: now}
        |> SequenceTrack.override_changeset(attrs)
        |> repo.insert()
      end
    )
  end

  defp insert_sequence_tracks(_repo, _node_id, tracks, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_tracks_snapshot, tracks}}
  end

  defp insert_sequence_visual_layers(repo, node_id, layers, snapshot, project_id, opts, now) when is_list(layers) do
    insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now)
  end

  defp insert_sequence_visual_layers(_repo, _node_id, layers, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_visual_layers_snapshot, layers}}
  end

  defp insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now) do
    insert_sequence_items(
      layers,
      :sequence_visual_layer,
      fn layer_data ->
        asset_id =
          resolve_flow_asset(
            layer_data["asset_id"],
            snapshot,
            project_id,
            opts,
            "image/",
            :sequence_visual_layer
          )

        insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now)
      end
    )
  end

  defp insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now) do
    attrs =
      layer_data
      |> Map.take([
        "kind",
        "layer_key",
        "overridden_fields",
        "removed",
        "label",
        "z_index",
        "slot",
        "x",
        "y",
        "width",
        "height",
        "anchor_x",
        "anchor_y",
        "fit",
        "opacity",
        "visible"
      ])
      |> Map.put("flow_node_id", node_id)
      |> Map.put("asset_id", asset_id)

    %SequenceVisualLayer{inserted_at: now, updated_at: now}
    |> SequenceVisualLayer.override_changeset(attrs)
    |> repo.insert()
  end

  defp insert_sequence_items(items, kind, insert_fun) do
    items
    |> Enum.reduce_while({:ok, %{}}, fn item, {:ok, id_map} ->
      result =
        if is_map(item) do
          insert_fun.(item)
        else
          {:error, {:invalid_sequence_resource_snapshot, item}}
        end

      case result do
        {:ok, resource} ->
          {:cont, {:ok, Map.put(id_map, item["original_id"], resource.id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, id_map} when map_size(id_map) == length(items) ->
        {:ok, id_map}

      {:ok, _id_map} ->
        {:error, {:sequence_resource_materialization_missing_identity, kind}}

      {:error, _reason} = error ->
        error
    end
  end

  defp inserted_resource_count({:ok, _resource}), do: {:ok, 1}
  defp inserted_resource_count({:error, reason}), do: {:error, reason}

  defp resolve_node_asset_refs(data, snapshot, project_id, opts) do
    case data["audio_asset_id"] do
      nil ->
        data

      audio_id ->
        resolved =
          resolve_flow_asset(
            audio_id,
            snapshot,
            project_id,
            opts,
            "audio/",
            :node_audio
          )

        Map.put(data, "audio_asset_id", resolved)
    end
  end

  defp insert_flow_nodes(_repo, _flow_id, [], _snapshot, _project_id, _now, _opts), do: {:ok, %{nodes: [], id_map: %{}}}

  defp insert_flow_nodes(repo, flow_id, nodes_data, snapshot, project_id, now, opts) do
    prepared_nodes =
      Enum.map(nodes_data, fn node_data ->
        data = resolve_node_asset_refs(node_data["data"] || %{}, snapshot, project_id, opts)
        {node_data, data}
      end)

    result =
      Enum.reduce_while(
        prepared_nodes,
        {:ok, %{nodes: [], id_map: %{}}},
        fn {node_data, data}, {:ok, result} ->
          case repo.insert(materialized_node_changeset(flow_id, node_data, data, now, opts)) do
            {:ok, node} ->
              {:cont,
               {:ok,
                %{
                  nodes: [node | result.nodes],
                  id_map: Map.put(result.id_map, node_data["original_id"], node.id)
                }}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )

    case result do
      {:ok, result} -> {:ok, %{result | nodes: Enum.reverse(result.nodes)}}
      {:error, _reason} = error -> error
    end
  end

  defp materialized_node_changeset(flow_id, node_data, data, now, opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      Ecto.Changeset.change(
        %FlowNode{flow_id: flow_id, inserted_at: now, updated_at: now},
        type: exact_materialization_node_type(node_data, opts),
        position_x: node_data["position_x"],
        position_y: node_data["position_y"],
        data: data,
        word_count: WordCount.for_node_data(node_data["type"], data)
      )
    else
      portable_materialized_node_changeset(flow_id, node_data, data, now)
    end
  end

  defp exact_materialization_node_type(node_data, opts) do
    if temporary_sequence_node?(node_data, opts), do: "sequence", else: node_data["type"]
  end

  defp temporary_sequence_node?(%{"type" => type} = node_data, opts) when type != "sequence" do
    materialize_sequence_resources?(node_data, opts)
  end

  defp temporary_sequence_node?(_node_data, _opts), do: false

  defp portable_materialized_node_changeset(flow_id, node_data, data, now) do
    FlowNode.materialize_changeset(%FlowNode{flow_id: flow_id, inserted_at: now, updated_at: now}, %{
      type: node_data["type"],
      position_x: node_data["position_x"] || 0.0,
      position_y: node_data["position_y"] || 0.0,
      data: data,
      word_count: WordCount.for_node_data(node_data["type"], data)
    })
  end

  defp insert_flow_connections(_repo, _flow_id, [], _context, _now), do: {:ok, %{}}

  defp insert_flow_connections(repo, flow_id, connections_data, context, now) do
    Enum.reduce_while(connections_data, {:ok, %{}}, fn connection_data, {:ok, id_map} ->
      with {:ok, {source_node_id, source_node, materialized_source_node}} <-
             materialize_connection_endpoint(
               repo,
               connection_data,
               :source,
               context
             ),
           {:ok, {target_node_id, _target_node, _materialized_target_node}} <-
             materialize_connection_endpoint(
               repo,
               connection_data,
               :target,
               context
             ),
           {:ok, source_pin} <-
             materialize_dynamic_pin(
               repo,
               connection_data,
               source_node,
               materialized_source_node,
               context.opts
             ),
           {:ok, connection} <-
             flow_id
             |> flow_connection_changeset(
               source_node_id,
               target_node_id,
               source_pin,
               connection_data,
               now,
               context.opts
             )
             |> repo.insert() do
        {:cont,
         {:ok,
          Map.put(
            id_map,
            connection_data["original_id"],
            connection.id
          )}}
      else
        {:error, {:dynamic_exit_pin_not_materializable, _connection_id, _pin, _reason} = reason} ->
          {:halt, {:error, reason}}

        reason ->
          {:halt, {:error, {:connection_materialization_failed, connection_data["original_id"], reason}}}
      end
    end)
  end

  defp materialize_connection_endpoint(repo, connection, endpoint, context) do
    keys = connection_endpoint_keys(endpoint)
    indexed_endpoint = indexed_connection_endpoint(connection[elem(keys, 0)], context)

    resolve_connection_endpoint(repo, connection, endpoint, keys, indexed_endpoint, context)
  end

  defp connection_endpoint_keys(:source), do: {"source_node_index", "source_node_id"}
  defp connection_endpoint_keys(:target), do: {"target_node_index", "target_node_id"}

  defp indexed_connection_endpoint(index, context) when is_integer(index) do
    snapshot_node = Enum.at(context.nodes_data, index)
    materialized_node = Enum.at(context.materialized_nodes_data, index)

    {mapped_snapshot_node_id(snapshot_node, context.node_id_map), snapshot_node, materialized_node}
  end

  defp indexed_connection_endpoint(_index, _context), do: {nil, nil, nil}

  defp mapped_snapshot_node_id(%{"original_id" => original_id}, node_id_map), do: Map.get(node_id_map, original_id)
  defp mapped_snapshot_node_id(_snapshot_node, _node_id_map), do: nil

  defp resolve_connection_endpoint(
         _repo,
         _connection,
         _endpoint,
         _keys,
         {mapped_id, snapshot_node, materialized_node},
         _context
       )
       when is_integer(mapped_id) do
    {:ok, {mapped_id, snapshot_node, materialized_node}}
  end

  defp resolve_connection_endpoint(repo, connection, endpoint, {index_key, id_key}, _indexed_endpoint, context) do
    if MaterializationHelpers.exact_materialization?(context.opts) do
      materialize_exact_connection_endpoint(
        repo,
        connection,
        endpoint,
        id_key,
        context.node_id_map,
        context.project_id
      )
    else
      {:error, {:missing_flow_connection_endpoint_mapping, endpoint, connection[index_key]}}
    end
  end

  defp materialize_exact_connection_endpoint(repo, connection, endpoint, id_key, node_id_map, project_id) do
    source_id = normalize_materialized_reference_id(connection[id_key])
    remapped_id = if is_integer(source_id), do: Map.get(node_id_map, source_id)

    cond do
      is_integer(remapped_id) ->
        {:ok, {remapped_id, nil, nil}}

      is_integer(source_id) and
          repo.exists?(
            from(node in FlowNode,
              join: flow in Flow,
              on: flow.id == node.flow_id,
              where: node.id == ^source_id and flow.project_id == ^project_id
            )
          ) ->
        {:ok, {source_id, nil, nil}}

      true ->
        {:error,
         {:exact_snapshot_fk_not_materializable, :flow_connection, connection["original_id"], endpoint, source_id}}
    end
  end

  defp flow_connection_changeset(flow_id, source_node_id, target_node_id, source_pin, connection_data, now, opts) do
    connection = %FlowConnection{flow_id: flow_id, inserted_at: now, updated_at: now}

    attrs = %{
      source_node_id: source_node_id,
      target_node_id: target_node_id,
      source_pin: source_pin,
      target_pin: connection_data["target_pin"],
      label: connection_data["label"]
    }

    if MaterializationHelpers.exact_materialization?(opts),
      do: Ecto.Changeset.change(connection, attrs),
      else: FlowConnection.create_changeset(connection, attrs)
  end

  defp materialize_flow_external_references(snapshot, project_id, opts, mode) do
    with {:ok, scene_id} <-
           materialize_flow_scene_reference(
             snapshot["scene_id"],
             project_id,
             opts,
             mode,
             {:flow, snapshot["original_id"], "scene_id"}
           ),
         {:ok, nodes} <-
           materialize_node_external_references(
             Map.get(snapshot, "nodes", []),
             project_id,
             opts,
             mode
           ) do
      {:ok, %{scene_id: scene_id, nodes: nodes}}
    end
  end

  defp materialize_flow_scene_reference(nil, _project_id, _opts, _mode, _context), do: {:ok, nil}

  defp materialize_flow_scene_reference(value, project_id, opts, :exact, context) do
    source_id = normalize_materialized_reference_id(value)

    resolved_id =
      MaterializationHelpers.resolve_project_external_ref(
        source_id,
        Scene,
        :scene,
        project_id,
        opts
      )

    cond do
      is_integer(resolved_id) ->
        {:ok, resolved_id}

      is_integer(source_id) and
          Repo.exists?(
            from(scene in Scene,
              where: scene.id == ^source_id and scene.project_id == ^project_id
            )
          ) ->
        {:ok, source_id}

      true ->
        {:error, {:exact_snapshot_fk_not_materializable, :flow, :scene_id, value, context}}
    end
  end

  defp materialize_flow_scene_reference(value, project_id, opts, mode, context) do
    materialize_external_reference(
      value,
      Scene,
      :scene,
      project_id,
      opts,
      mode,
      context
    )
  end

  defp lock_flow_external_references(repo, snapshot, project_id, opts) do
    reference_specs =
      [{Scene, :scene, snapshot["scene_id"]}] ++
        Enum.flat_map(Map.get(snapshot, "nodes", []), fn node ->
          data = node["data"] || %{}

          [
            {Sheet, :sheet, data["speaker_sheet_id"]},
            {Sheet, :sheet, data["location_sheet_id"]},
            {Flow, :flow, data["referenced_flow_id"]}
          ] ++ flow_exit_target_lock_spec(node)
        end) ++
        Enum.map(Map.get(snapshot, "localization", []), fn row ->
          {Sheet, :sheet, row["speaker_sheet_id"]}
        end)

    candidates_by_schema =
      Enum.reduce(reference_specs, %{}, fn {schema, map_key, value}, candidates ->
        case materialization_reference_candidate(value, map_key, opts) do
          nil ->
            candidates

          id ->
            Map.update(
              candidates,
              schema,
              MapSet.new([id]),
              &MapSet.put(&1, id)
            )
        end
      end)

    locked_refs =
      Enum.flat_map([Flow, Scene, Sheet], fn schema ->
        ids =
          candidates_by_schema
          |> Map.get(schema, MapSet.new())
          |> MapSet.to_list()
          |> Enum.sort()

        if ids == [] do
          []
        else
          from(record in schema,
            where:
              record.id in ^ids and record.project_id == ^project_id and
                is_nil(field(record, :deleted_at)),
            order_by: [asc: record.id],
            lock: "FOR UPDATE",
            select: record.id
          )
          |> repo.all()
          |> Enum.map(&{schema, &1})
        end
      end)

    {:ok, locked_refs}
  end

  defp flow_exit_target_lock_spec(%{"type" => "exit", "data" => data}) do
    case normalized_flow_exit_target(data) do
      {"scene", target_id} -> [{Scene, :scene, target_id}]
      {"flow", target_id} -> [{Flow, :flow, target_id}]
      nil -> []
    end
  end

  defp flow_exit_target_lock_spec(_node), do: []

  defp materialization_reference_candidate(nil, _map_key, _opts), do: nil

  defp materialization_reference_candidate(value, map_key, opts) do
    source_id = normalize_materialized_reference_id(value)

    mapped_id =
      opts
      |> Keyword.get(:external_id_maps, %{})
      |> Map.get(map_key, %{})
      |> Map.get(source_id)

    cond do
      mapped_id -> normalize_materialized_reference_id(mapped_id)
      not MaterializationHelpers.preserve_external_refs?(opts) -> nil
      true -> source_id
    end
  end

  defp materialize_node_external_references(nodes, project_id, opts, mode) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, materialized_nodes} ->
      case materialize_node_external_references(node, project_id, opts, mode) do
        {:ok, materialized_node} ->
          {:cont, {:ok, [materialized_node | materialized_nodes]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, materialized_nodes} -> {:ok, Enum.reverse(materialized_nodes)}
      {:error, _reason} = error -> error
    end
  end

  defp materialize_node_external_references(node, project_id, opts, mode) when is_map(node) do
    references = [
      {"speaker_sheet_id", Sheet, :sheet},
      {"location_sheet_id", Sheet, :sheet},
      {"avatar_id", SheetAvatar, :avatar},
      {"referenced_flow_id", Flow, :flow}
    ]

    with {:ok, data} <-
           Enum.reduce_while(
             references,
             {:ok, node["data"] || %{}},
             fn {field, schema, map_key}, {:ok, data} ->
               continue_node_external_reference_materialization(
                 data,
                 field,
                 schema,
                 map_key,
                 project_id,
                 opts,
                 mode,
                 node["original_id"]
               )
             end
           ),
         {:ok, data} <-
           materialize_flow_exit_target(
             node["type"],
             node["original_id"],
             data,
             project_id,
             opts,
             mode
           ),
         {:ok, data} <- maybe_normalize_materialized_node_avatar(project_id, node["type"], data, opts) do
      {:ok, Map.put(node, "data", data)}
    end
  end

  defp maybe_normalize_materialized_node_avatar(project_id, node_type, data, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: {:ok, data},
      else: AvatarIntegrity.lock_and_normalize_node_avatar_for_project(project_id, node_type, data)
  end

  defp continue_node_external_reference_materialization(data, field, schema, map_key, project_id, opts, mode, node_id) do
    with {:ok, value} <- Map.fetch(data, field),
         {:ok, resolved_id} <-
           materialize_external_reference(
             value,
             schema,
             map_key,
             project_id,
             opts,
             mode,
             {:flow_node, node_id, field}
           ) do
      {:cont, {:ok, Map.put(data, field, resolved_id)}}
    else
      :error -> {:cont, {:ok, data}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp materialize_flow_exit_target("exit", node_id, data, project_id, opts, mode) do
    with :ok <- maybe_validate_flow_exit_target_contract(node_id, data, opts) do
      materialize_normalized_flow_exit_target(
        normalized_flow_exit_target(data),
        node_id,
        data,
        project_id,
        opts,
        mode
      )
    end
  end

  defp materialize_flow_exit_target(_node_type, _node_id, data, _project_id, _opts, _mode), do: {:ok, data}

  defp maybe_validate_flow_exit_target_contract(node_id, data, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: :ok,
      else: validate_flow_exit_target_contract(node_id, data)
  end

  defp materialize_normalized_flow_exit_target(nil, _node_id, data, _project_id, _opts, _mode), do: {:ok, data}

  defp materialize_normalized_flow_exit_target({target_type, target_id}, node_id, data, project_id, opts, mode) do
    {schema, map_key} = flow_exit_target_schema_and_map(target_type)

    with {:ok, resolved_id} <-
           materialize_external_reference(
             target_id,
             schema,
             map_key,
             project_id,
             opts,
             mode,
             {:flow_node, node_id, "target_id", target_type}
           ) do
      {:ok, put_materialized_flow_exit_target(data, target_type, resolved_id)}
    end
  end

  defp flow_exit_target_schema_and_map("scene"), do: {Scene, :scene}
  defp flow_exit_target_schema_and_map("flow"), do: {Flow, :flow}

  defp put_materialized_flow_exit_target(data, _target_type, nil) do
    data
    |> Map.put("target_type", nil)
    |> Map.put("target_id", nil)
  end

  defp put_materialized_flow_exit_target(data, target_type, target_id) do
    data
    |> Map.put("target_type", target_type)
    |> Map.put("target_id", target_id)
  end

  defp materialize_external_reference(nil, _schema, _map_key, _project_id, _opts, _mode, _context), do: {:ok, nil}

  defp materialize_external_reference(value, schema, map_key, project_id, opts, mode, context) do
    source_id = normalize_materialized_reference_id(value)

    resolved_id =
      MaterializationHelpers.resolve_project_external_ref(
        source_id,
        schema,
        map_key,
        project_id,
        opts
      )

    case mode do
      :portable ->
        {:ok, resolved_id}

      :exact ->
        {:ok, if(is_nil(resolved_id), do: value, else: resolved_id)}

      :strict when is_nil(source_id) ->
        {:error, {:invalid_flow_external_reference, context, value}}

      :strict when is_nil(resolved_id) ->
        {:error, {:flow_external_reference_not_materializable, context, value}}

      :strict ->
        {:ok, resolved_id}
    end
  end

  @doc """
  Revalidates the materialized flow-reference graph for one active flow.

  Project recovery uses this after all cross-flow IDs have been remapped and
  persisted. The validation reads the final database graph, rather than the
  pre-remap snapshot graph.
  """
  @spec validate_materialized_reference_cycles(pos_integer()) ::
          :ok | {:error, term()}
  def validate_materialized_reference_cycles(flow_id) when is_integer(flow_id) and flow_id > 0 do
    case Repo.get(Flow, flow_id) do
      %Flow{deleted_at: nil} ->
        nodes =
          Repo.all(
            from(node in FlowNode,
              where: node.flow_id == ^flow_id and is_nil(node.deleted_at),
              order_by: [asc: node.id],
              select: %{
                "original_id" => node.id,
                "type" => node.type,
                "data" => node.data
              }
            )
          )

        validate_materialized_flow_reference_cycles(flow_id, nodes)

      %Flow{} ->
        {:error, {:flow_deleted, flow_id}}

      nil ->
        {:error, {:flow_not_found, flow_id}}
    end
  end

  def validate_materialized_reference_cycles(flow_id), do: {:error, {:invalid_flow_id, flow_id}}

  defp validate_materialized_flow_reference_cycles(flow_id, nodes) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      continue_materialized_flow_reference_cycle_validation(
        flow_id,
        node["original_id"],
        node
        |> materialized_flow_reference_target()
        |> normalize_materialized_reference_id()
      )
    end)
  end

  defp continue_materialized_flow_reference_cycle_validation(_flow_id, _node_id, nil), do: {:cont, :ok}

  defp continue_materialized_flow_reference_cycle_validation(flow_id, node_id, target_flow_id) do
    if NodeCreate.has_circular_reference?(flow_id, target_flow_id) do
      {:halt, {:error, {:circular_flow_reference, flow_id, node_id, target_flow_id}}}
    else
      {:cont, :ok}
    end
  end

  defp materialized_flow_reference_target(%{"type" => "subflow", "data" => %{"referenced_flow_id" => target_flow_id}}),
    do: target_flow_id

  defp materialized_flow_reference_target(%{
         "type" => "exit",
         "data" => %{"exit_mode" => "flow_reference", "referenced_flow_id" => target_flow_id}
       }), do: target_flow_id

  defp materialized_flow_reference_target(_node), do: nil

  defp normalize_materialized_reference_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_materialized_reference_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _invalid -> nil
    end
  end

  defp normalize_materialized_reference_id(_value), do: nil

  defp parse_dynamic_exit_pin("exit_" <> exit_id_text) do
    case Integer.parse(exit_id_text) do
      {exit_id, ""} when exit_id > 0 -> {:ok, exit_id}
      _invalid -> {:error, :invalid_exit_node_id}
    end
  end

  defp parse_dynamic_exit_pin(_pin), do: :not_dynamic

  defp resolve_flow_asset(asset_id, snapshot, project_id, opts, expected_content_type_prefix, asset_context) do
    case flow_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        resolution_opts =
          opts
          |> MaterializationHelpers.asset_resolution_opts(asset_mode, project_id)
          |> Keyword.put(:expected_content_type_prefix, expected_content_type_prefix)
          |> Keyword.put(:asset_context, asset_context)

        AssetHashResolver.resolve_asset_fk(
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          resolution_opts
        )
    end
  end

  defp flow_asset_mode(opts) do
    case Keyword.get(opts, :asset_mode, :reuse) do
      :drop -> :drop
      :copy -> :copy
      _mode -> :reuse
    end
  end

  defp materialize_dynamic_pin(
         repo,
         %{"original_id" => connection_id, "source_pin" => "exit_" <> old_id_text = pin},
         %{"type" => "subflow"} = source_node,
         %{} = materialized_source_node,
         opts
       ) do
    case Integer.parse(old_id_text) do
      {old_id, ""} ->
        old_referenced_flow_id =
          source_node
          |> get_in(["data", "referenced_flow_id"])
          |> normalize_materialized_reference_id()

        new_referenced_flow_id =
          materialized_source_node
          |> get_in(["data", "referenced_flow_id"])
          |> normalize_materialized_reference_id()

        materialize_dynamic_exit_pin(
          repo,
          connection_id,
          pin,
          old_id,
          old_referenced_flow_id,
          new_referenced_flow_id,
          opts
        )

      _ ->
        {:ok, pin}
    end
  end

  defp materialize_dynamic_pin(_repo, %{"source_pin" => pin}, _source_node, _materialized_source_node, _opts),
    do: {:ok, pin}

  defp materialize_dynamic_exit_pin(
         _repo,
         _connection_id,
         pin,
         _old_exit_id,
         old_referenced_flow_id,
         new_referenced_flow_id,
         _opts
       )
       when is_nil(old_referenced_flow_id) or is_nil(new_referenced_flow_id) or
              old_referenced_flow_id == new_referenced_flow_id, do: {:ok, pin}

  defp materialize_dynamic_exit_pin(
         repo,
         connection_id,
         pin,
         old_exit_id,
         _old_referenced_flow_id,
         new_referenced_flow_id,
         opts
       ) do
    mapped_exit_id =
      opts
      |> Keyword.get(:external_id_maps, %{})
      |> Map.get(:node, %{})
      |> Map.get(old_exit_id)
      |> normalize_materialized_reference_id()

    cond do
      MaterializationHelpers.exact_materialization?(opts) and not is_nil(mapped_exit_id) and
          materialized_exit_node?(repo, mapped_exit_id, new_referenced_flow_id) ->
        {:ok, "exit_#{mapped_exit_id}"}

      MaterializationHelpers.exact_materialization?(opts) ->
        {:ok, pin}

      is_nil(mapped_exit_id) ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :missing_exit_node_mapping}}

      materialized_exit_node?(repo, mapped_exit_id, new_referenced_flow_id) ->
        {:ok, "exit_#{mapped_exit_id}"}

      true ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :mapped_exit_not_in_referenced_flow}}
    end
  end

  defp materialized_exit_node?(repo, node_id, flow_id) do
    repo.exists?(
      from(node in FlowNode,
        where:
          node.id == ^node_id and node.flow_id == ^flow_id and node.type == "exit" and
            is_nil(node.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp sort_and_normalize_snapshot_nodes(nodes, project_id) do
    nodes
    |> Enum.sort_by(&{&1.position_x, &1.position_y, &1.type, &1.id})
    |> Enum.map(fn node ->
      data = node.data || %{}

      case AvatarIntegrity.lock_and_normalize_node_avatar_for_project(
             project_id,
             node.type,
             data
           ) do
        {:ok, normalized_data} ->
          %{node | data: normalized_data}

        {:error, {:invalid_avatar_reference, avatar_id}}
        when is_integer(avatar_id) and avatar_id > 0 ->
          %{node | data: Map.put(data, "avatar_id", nil)}

        {:error, _reason} ->
          node
      end
    end)
  end
end

defmodule Storyarn.Versioning.Builders.FlowBuilder do
  @moduledoc """
  Snapshot builder for flows.

  Captures flow metadata, nodes (sorted deterministically), and connections
  (referenced by node index rather than ID for portability).
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.NodeCreate
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization
  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Versioning.MaterializationHelpers
  alias Storyarn.Versioning.RestorePolicy

  @flow_snapshot_fields ~w(
    original_id name shortcut description is_main settings scene_id nodes connections
    asset_blob_hashes asset_metadata referenced_sheets localization localization_manifest
  )
  @node_snapshot_fields ~w(original_id type position_x position_y data source parent_id)
  @sequence_config_fields ~w(name width height)
  @sequence_track_fields ~w(original_id kind position asset_id start_time end_time volume)
  @sequence_visual_layer_fields ~w(
    original_id asset_id kind label z_index slot x y width height anchor_x anchor_y fit
    opacity visible
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

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Flow{} = flow) do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          lock_snapshot_project!(flow.project_id)
          locked_flow = lock_flow_for_snapshot!(flow)
          :ok = LocalizableWords.lock_inventory!(locked_flow.project_id)
          do_build_snapshot(locked_flow)
        end,
        isolation: :repeatable_read
      )

    snapshot
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
      |> Enum.sort_by(&{&1.position_x, &1.position_y, &1.type, &1.id})

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

    ensure_valid_built_flow_snapshot!(snapshot)
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

  defp ensure_valid_built_flow_snapshot!(snapshot) do
    case validate_flow_snapshot(snapshot) do
      :ok ->
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
      "source" => node.source,
      "parent_id" => node.parent_id
    }

    if node.type == "sequence" do
      Map.merge(snapshot, %{
        "sequence_config" => sequence_config_to_snapshot(node.sequence_config),
        "sequence_tracks" =>
          node
          |> sequence_tracks()
          |> Enum.sort_by(&{&1.kind, &1.position, &1.id})
          |> Enum.map(&sequence_track_to_snapshot/1),
        "sequence_visual_layers" =>
          node
          |> sequence_visual_layers()
          |> Enum.sort_by(&{&1.z_index, &1.id})
          |> Enum.map(&sequence_visual_layer_to_snapshot/1)
      })
    else
      snapshot
    end
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

  defp snapshot_connection_endpoint_states(connections) do
    endpoint_ids =
      connections
      |> Enum.flat_map(&[&1.source_node_id, &1.target_node_id])
      |> Enum.uniq()

    from(node in FlowNode,
      where: node.id in ^endpoint_ids,
      select: {node.id, %{flow_id: node.flow_id, deleted_at: node.deleted_at}}
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
      sheets = Sheets.list_sheets_by_ids(project_id, sheet_ids)

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

  defp extract_asset_url(%{url: url}) when is_binary(url), do: url
  defp extract_asset_url(_), do: nil

  defp extract_default_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_default_avatar_url(sheet), do: extract_asset_url(Map.get(sheet, :avatar_asset))

  # ========== Restore Snapshot ==========

  @impl true
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    snapshot = FlowSnapshotNormalizer.normalize_entity_ids(snapshot)

    with :ok <- validate_flow_snapshot(snapshot) do
      with_asset_materialization_scope(opts, fn scoped_opts ->
        instantiate_flow_snapshot_transaction(
          project_id,
          snapshot,
          scoped_opts
        )
      end)
    end
  end

  defp instantiate_flow_snapshot_transaction(project_id, snapshot, opts) do
    result =
      Repo.transaction(
        fn -> instantiate_flow_snapshot(project_id, snapshot, opts) end,
        timeout: :infinity
      )

    if retry_main_constraint?(result, opts) do
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
           materialize_flow_external_references(snapshot, project_id, opts, :portable),
         :ok <- LocalizableWords.lock_inventory!(project_id),
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
         :ok <- validate_materialized_flow_reference_cycles(flow_id, external_refs.nodes),
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
         {:ok, _linked_parents} <- link_snapshot_node_parents(Repo, nodes, node_id_map),
         {:ok, sequence_resource_data} <-
           insert_sequence_resources(Repo, nodes, node_id_map, snapshot, project_id, opts, now),
         {:ok, connection_id_map} <-
           insert_flow_connections(
             Repo,
             flow_id,
             connections,
             nodes,
             external_refs.nodes,
             node_id_map,
             opts,
             now
           ) do
      complete_flow_instantiation(
        project_id,
        snapshot,
        flow_id,
        node_id_map,
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
          where: flow.project_id == ^project_id and flow.is_main == true
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

    id_maps = %{
      flow: MaterializationHelpers.root_id_map(snapshot, flow_id),
      node: node_id_map,
      connection: connection_id_map,
      sequence_track: sequence_resource_data.track_id_map,
      sequence_visual_layer: sequence_resource_data.visual_layer_id_map
    }

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

  defp maybe_restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts) do
    if Keyword.get(opts, :restore_localization, true) do
      with :ok <- restore_instantiated_flow_localization(project_id, snapshot, id_maps, opts) do
        Localization.extract_flow_nodes(id_maps.flow[snapshot["original_id"]])
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
        LocalizationSnapshotCodec.restore(
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
          resolve_flow_asset(asset_id, snapshot, project_id, opts)
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

  @impl true
  def restore_snapshot(%Flow{} = flow, snapshot, opts \\ []) do
    with :ok <-
           RestorePolicy.ensure_builder_enabled(
             "flow",
             Keyword.get(opts, :restore_action)
           ) do
      scoped_result =
        with_asset_materialization_scope(opts, fn scoped_opts ->
          do_restore_snapshot(flow, snapshot, scoped_opts)
        end)

      finalize_in_place_flow_restore(scoped_result, snapshot, opts)
    end
  end

  defp with_asset_materialization_scope(opts, callback) do
    MaterializationHelpers.with_asset_copy_tracker(opts, fn tracked_opts ->
      AssetMaterializationScope.run(tracked_opts, callback)
    end)
  end

  defp do_restore_snapshot(flow, snapshot, opts) do
    normalized_snapshot = FlowSnapshotNormalizer.normalize(snapshot)

    if normalized_snapshot == snapshot do
      case validate_restore_snapshot(flow, normalized_snapshot) do
        :ok -> execute_restore_snapshot(flow, normalized_snapshot, opts)
        {:error, _reason} = error -> error
      end
    else
      {:error, :legacy_flow_snapshot_requires_identity_normalization}
    end
  end

  defp execute_restore_snapshot(flow, snapshot, opts) do
    nodes_data = snapshot["nodes"]
    connections_data = snapshot["connections"]

    target_node_ids = Enum.map(nodes_data, & &1["original_id"])

    Multi.new()
    |> Multi.run(:lock_project, fn repo, _changes ->
      lock_materialization_project(repo, flow.project_id)
    end)
    |> Multi.run(:lock_flow, fn repo, %{lock_project: _project} ->
      lock_restore_flow(repo, flow)
    end)
    |> Multi.run(:lock_external_refs, fn repo,
                                         %{
                                           lock_project: _project,
                                           lock_flow: locked_flow
                                         } ->
      lock_flow_external_references(
        repo,
        snapshot,
        locked_flow.project_id,
        opts
      )
    end)
    |> Multi.run(:resolve_external_refs, fn repo,
                                            %{
                                              lock_external_refs: _external_locks,
                                              lock_flow: locked_flow
                                            } ->
      with {:ok, external_refs} <-
             materialize_flow_external_references(
               snapshot,
               locked_flow.project_id,
               opts,
               :strict
             ),
           :ok <-
             validate_materialized_flow_reference_cycles(
               locked_flow.id,
               external_refs.nodes
             ),
           :ok <-
             validate_materialized_dynamic_exit_pins(
               repo,
               connections_data,
               external_refs.nodes
             ) do
        {:ok, external_refs}
      end
    end)
    |> Multi.run(:validate_incoming_dynamic_pins, fn repo,
                                                     %{
                                                       lock_project: locked_project,
                                                       lock_flow: locked_flow,
                                                       resolve_external_refs: _external_refs
                                                     } ->
      lock_and_validate_incoming_dynamic_pins(
        repo,
        locked_project.id,
        locked_flow.id,
        nodes_data,
        opts
      )
    end)
    |> Multi.run(:lock_restore_scope, fn repo,
                                         %{
                                           lock_flow: locked_flow,
                                           resolve_external_refs: _external_refs,
                                           validate_incoming_dynamic_pins: _incoming_pins
                                         } ->
      lock_restore_scope(repo, locked_flow.id)
    end)
    |> Multi.run(:reconcile_sequence_transition_connections, fn repo,
                                                                %{
                                                                  lock_restore_scope: _scope
                                                                } ->
      reconcile_full_project_sequence_transition_connections(
        repo,
        flow.id,
        nodes_data,
        opts
      )
    end)
    |> Multi.run(:reconcile_cross_boundary_connections, fn repo,
                                                           %{
                                                             lock_flow: locked_flow,
                                                             lock_restore_scope: _scope,
                                                             resolve_external_refs: external_refs,
                                                             reconcile_sequence_transition_connections:
                                                               _reconciled_connections
                                                           } ->
      reconcile_full_project_cross_boundary_connections(
        repo,
        locked_flow.project_id,
        locked_flow.id,
        external_refs.nodes,
        opts
      )
    end)
    |> Multi.run(:reconcile_sequence_transition_children, fn repo,
                                                             %{
                                                               lock_restore_scope: _scope,
                                                               reconcile_cross_boundary_connections:
                                                                 _reconciled_connections
                                                             } ->
      reconcile_full_project_sequence_transition_children(
        repo,
        flow.id,
        nodes_data,
        opts
      )
    end)
    |> Multi.run(:lock_localization_inventory, fn _repo,
                                                  %{
                                                    lock_flow: locked_flow,
                                                    lock_restore_scope: _scope,
                                                    reconcile_sequence_transition_connections: _reconciled_connections,
                                                    reconcile_cross_boundary_connections:
                                                      _reconciled_cross_boundary_connections,
                                                    reconcile_sequence_transition_children: _reconciled_children,
                                                    lock_project: _project
                                                  } ->
      :ok = LocalizableWords.lock_inventory!(locked_flow.project_id)
      {:ok, locked_flow.project_id}
    end)
    |> Multi.run(:validate_ownership, fn repo, _changes ->
      validate_restore_ownership(repo, flow.id, nodes_data, connections_data)
    end)
    |> Multi.run(:resolve_main_state, fn repo, %{lock_flow: locked_flow} ->
      is_main =
        restorable_main_state(
          repo,
          locked_flow.project_id,
          locked_flow.id,
          snapshot["is_main"],
          opts
        )

      :ok = run_before_main_write_hook(opts)
      {:ok, is_main}
    end)
    |> Multi.update(:flow, fn %{
                                lock_flow: locked_flow,
                                resolve_external_refs: external_refs,
                                resolve_main_state: is_main
                              } ->
      locked_flow
      |> Flow.update_changeset(%{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        description: snapshot["description"],
        is_main: is_main,
        settings: snapshot["settings"],
        scene_id: external_refs.scene_id
      })
      |> main_flow_unique_constraint()
    end)
    |> Multi.run(:soft_delete_absent_nodes, fn repo, _changes ->
      soft_delete_absent_active_nodes(repo, flow.id, target_node_ids)
    end)
    |> Multi.run(:clear_target_state, fn repo, _changes ->
      clear_target_node_state(repo, flow.id, target_node_ids)
    end)
    |> Multi.run(:prepare_dialogue_id_swaps, fn repo, _changes ->
      prepare_target_dialogue_id_swaps(repo, flow.id, target_node_ids)
    end)
    |> Multi.run(:restore_nodes, fn repo, %{resolve_external_refs: external_refs} ->
      reconcile_snapshot_nodes(
        repo,
        flow.id,
        external_refs.nodes,
        snapshot,
        flow.project_id,
        opts
      )
    end)
    |> Multi.run(:restore_sequence_resources, fn repo, %{restore_nodes: node_data} ->
      reconcile_sequence_resources(
        repo,
        nodes_data,
        node_data.nodes,
        snapshot,
        flow.project_id,
        opts
      )
    end)
    |> Multi.run(:restore_parents, fn repo, %{restore_nodes: node_data} ->
      link_snapshot_node_parents(repo, nodes_data, node_data.node_id_map)
    end)
    |> Multi.run(:restore_connections, fn repo, _changes ->
      reconcile_snapshot_connections(repo, flow.id, connections_data, nodes_data, target_node_ids)
    end)
    |> Multi.run(:archive_localization, fn _repo, %{soft_delete_absent_nodes: deleted_node_ids} ->
      TextCrud.archive_texts_for_sources("flow_node", deleted_node_ids, "source_deleted")

      TextCrud.archive_texts_for_active_target_locales(
        flow.project_id,
        "flow_node",
        target_node_ids,
        "version_replaced"
      )

      {:ok, length(target_node_ids)}
    end)
    |> Multi.run(:restore_localization, fn _repo, %{restore_nodes: node_data} ->
      localization_rows =
        LocalizationSnapshotCodec.active_target_rows(
          flow.project_id,
          Map.get(snapshot, "localization", [])
        )

      with {:ok, localization_rows} <-
             materialize_localization_asset_references(
               localization_rows,
               snapshot,
               flow.project_id,
               opts
             ),
           {:ok, localization_rows} <-
             materialize_localization_speaker_references(
               localization_rows,
               flow.project_id,
               opts,
               :strict
             ),
           :ok <-
             LocalizationSnapshotCodec.restore(
               flow.project_id,
               localization_rows,
               %{node: node_data.node_id_map}
             ) do
        {:ok, length(localization_rows)}
      end
    end)
    |> Multi.run(:extract_localization, fn _repo, %{restore_nodes: node_data} ->
      extract_restored_node_localization(node_data.nodes)
    end)
    |> Multi.run(:rebuild_references, fn _repo,
                                         %{
                                           restore_nodes: node_data,
                                           soft_delete_absent_nodes: deleted_node_ids
                                         } ->
      rebuild_restored_node_references(
        node_data.nodes,
        deleted_node_ids,
        flow.project_id
      )
    end)
    |> Repo.transaction(timeout: :infinity)
    |> then(fn result ->
      if retry_main_constraint?(result, opts) do
        execute_restore_snapshot(
          flow,
          snapshot,
          Keyword.put(opts, :__force_non_main_on_conflict, true)
        )
      else
        result
      end
    end)
  end

  defp finalize_in_place_flow_restore(
         {:ok,
          %{
            flow: updated_flow,
            restore_nodes: node_data,
            restore_connections: connection_data,
            restore_sequence_resources: resource_data
          }},
         snapshot,
         opts
       ) do
    run_post_commit_restore_hook(opts)

    active_nodes_query =
      from(node in FlowNode,
        where: is_nil(node.deleted_at)
      )

    restored_flow =
      Repo.preload(
        updated_flow,
        [
          :connections,
          nodes: {active_nodes_query, [:sequence_config, :sequence_tracks, :sequence_visual_layers]}
        ],
        force: true
      )

    if Keyword.get(opts, :return_id_maps, false) do
      id_maps = %{
        flow: MaterializationHelpers.root_id_map(snapshot, updated_flow.id),
        node: node_data.node_id_map,
        connection: connection_data.connection_id_map,
        sequence_track: resource_data.track_id_map,
        sequence_visual_layer: resource_data.visual_layer_id_map
      }

      {:ok, restored_flow, id_maps}
    else
      {:ok, restored_flow}
    end
  end

  defp finalize_in_place_flow_restore({:error, _op, reason, _changes}, _snapshot, _opts), do: {:error, reason}
  defp finalize_in_place_flow_restore({:error, _reason} = error, _snapshot, _opts), do: error

  defp run_post_commit_restore_hook(opts) do
    case Keyword.get(opts, :__post_commit_restore_hook) do
      hook when is_function(hook, 0) -> hook.()
      _hook -> :ok
    end
  end

  # Retry safety depends on the unique main-flow write happening before any
  # asset is resolved. The cache and storage tracker belong to the surrounding
  # materialization scope and are intentionally shared by the retry.
  defp run_before_main_write_hook(opts) do
    case Keyword.get(opts, :__before_main_write_hook) do
      hook when is_function(hook, 0) ->
        hook.()
        :ok

      _hook ->
        :ok
    end
  end

  defp validate_restore_snapshot(%Flow{id: flow_id}, snapshot) do
    with :ok <- validate_flow_snapshot(snapshot) do
      validate_snapshot_root_id(snapshot["original_id"], flow_id)
    end
  end

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
           ) do
      validate_snapshot_parents(nodes)
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

      node["source"] not in ~w(manual screenplay_sync) ->
        invalid_snapshot_field(:node, "source", node["source"])

      not optional_positive_integer?(parent_id) ->
        {:error, {:invalid_snapshot_node_parent_id, node["original_id"], parent_id}}

      true ->
        :ok
    end
  end

  defp validate_snapshot_node_type_payload(%{"original_id" => node_id, "type" => "exit", "data" => data}),
    do: validate_flow_exit_target_contract(node_id, data)

  defp validate_snapshot_node_type_payload(%{"original_id" => node_id, "type" => "dialogue", "data" => data}),
    do: validate_dialogue_runtime_ids(node_id, data)

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
    with {:ok, tracks} <- fetch_required_sequence_collection(node, "sequence_tracks"),
         {:ok, layers} <- fetch_required_sequence_collection(node, "sequence_visual_layers"),
         :ok <- validate_sequence_config_snapshot(node),
         :ok <- validate_snapshot_entry_ids(tracks, :sequence_track),
         :ok <- validate_snapshot_entry_ids(layers, :sequence_visual_layer),
         :ok <- validate_sequence_track_payloads(tracks),
         :ok <- validate_sequence_visual_layer_payloads(layers) do
      validate_unique_track_kinds(node["original_id"], tracks)
    end
  end

  defp fetch_required_sequence_collection(node, key) do
    case Map.fetch(node, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_sequence_snapshot_collection, node["original_id"], key, value}}
      :error -> {:error, {:legacy_sequence_snapshot_missing_ids, node["original_id"], key}}
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
        {:error, {:legacy_sequence_snapshot_missing_config, node["original_id"]}}
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
             true <- positive_integer?(layer["asset_id"]),
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
    kinds = Enum.map(tracks, & &1["kind"])

    if length(kinds) == length(Enum.uniq(kinds)),
      do: :ok,
      else: {:error, {:duplicate_sequence_track_kind, node_id}}
  end

  defp validate_sequence_resource_ids(nodes, key, kind) do
    resources =
      Enum.flat_map(nodes, fn
        %{"type" => "sequence"} = node -> node[key]
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
      validate_complete_snapshot_localization(localization, sources, target_locales)
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

  defp node_localization_sources(%{"original_id" => node_id, "type" => "dialogue", "data" => data}) do
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

  defp node_localization_sources(%{"original_id" => node_id, "type" => "exit", "data" => data}) do
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

  defp lock_restore_flow(repo, %Flow{id: flow_id, project_id: project_id}) do
    case repo.one(from(flow in Flow, where: flow.id == ^flow_id, lock: "FOR UPDATE")) do
      %Flow{project_id: ^project_id, deleted_at: nil} = locked_flow ->
        {:ok, locked_flow}

      %Flow{project_id: ^project_id} ->
        {:error, {:flow_deleted, flow_id}}

      %Flow{project_id: owner_project_id} ->
        {:error, {:flow_project_ownership_changed, flow_id, owner_project_id}}

      nil ->
        {:error, {:flow_not_found, flow_id}}
    end
  end

  defp lock_and_validate_incoming_dynamic_pins(repo, project_id, restored_flow_id, snapshot_nodes, opts) do
    project_flow_ids =
      repo.all(
        from(flow in Flow,
          where: flow.project_id == ^project_id,
          order_by: [asc: flow.id],
          select: flow.id
        )
      )

    locked_nodes =
      repo.all(
        from(node in FlowNode,
          where: node.flow_id in ^project_flow_ids,
          order_by: [asc: node.id],
          lock: "FOR UPDATE",
          select: %{
            id: node.id,
            type: node.type,
            flow_id: node.flow_id,
            data: node.data
          }
        )
      )

    source_nodes = Enum.filter(locked_nodes, &(&1.type == "subflow"))
    source_node_ids = Enum.map(source_nodes, & &1.id)

    connections =
      repo.all(
        from(connection in FlowConnection,
          where: connection.source_node_id in ^source_node_ids,
          order_by: [asc: connection.id],
          lock: "FOR UPDATE"
        )
      )

    nodes_by_id = Map.new(locked_nodes, &{&1.id, &1})
    source_nodes_by_id = Map.take(nodes_by_id, source_node_ids)

    target_exit_ids =
      snapshot_nodes
      |> Enum.filter(&(&1["type"] == "exit"))
      |> MapSet.new(& &1["original_id"])

    recoverable_connection_sources =
      recoverable_full_project_connection_sources(opts)

    with :ok <-
           validate_project_connection_ownership(
             connections,
             nodes_by_id,
             MapSet.new(project_flow_ids)
           ),
         {:ok, invalid_connections} <-
           invalid_incoming_dynamic_pin_connections(
             connections,
             source_nodes_by_id,
             restored_flow_id,
             target_exit_ids
           ),
         :ok <-
           validate_recoverable_incoming_dynamic_connections(
             invalid_connections,
             recoverable_connection_sources
           ),
         {:ok, removed_connection_ids} <-
           delete_incoming_dynamic_connections(
             repo,
             invalid_connections,
             project_flow_ids,
             source_node_ids
           ) do
      {:ok,
       %{
         source_nodes: source_node_ids,
         connections: Enum.map(connections, & &1.id),
         removed_connections: removed_connection_ids
       }}
    end
  end

  defp validate_project_connection_ownership(connections, nodes_by_id, project_flow_ids) do
    case Enum.find(
           connections,
           &project_connection_ownership_conflict?(&1, nodes_by_id, project_flow_ids)
         ) do
      nil ->
        :ok

      connection ->
        {:error,
         {:incoming_dynamic_connection_ownership_conflict,
          {connection.id, connection.flow_id, connection.source_node_id, connection.target_node_id}}}
    end
  end

  defp project_connection_ownership_conflict?(connection, nodes_by_id, project_flow_ids) do
    source_node = Map.get(nodes_by_id, connection.source_node_id)
    target_node = Map.get(nodes_by_id, connection.target_node_id)

    is_nil(source_node) or is_nil(target_node) or
      not MapSet.member?(project_flow_ids, connection.flow_id) or
      source_node.flow_id != connection.flow_id or
      target_node.flow_id != connection.flow_id
  end

  defp invalid_incoming_dynamic_pin_connections(connections, source_nodes, restored_flow_id, target_exit_ids) do
    connections
    |> Enum.reduce_while({:ok, []}, fn connection, {:ok, invalid} ->
      source_node = Map.fetch!(source_nodes, connection.source_node_id)

      case validate_incoming_dynamic_pin_for_connection(
             connection,
             source_node,
             restored_flow_id,
             target_exit_ids
           ) do
        :ok ->
          {:cont, {:ok, invalid}}

        {:error, reason} ->
          {:cont,
           {:ok,
            [
              %{
                connection: connection,
                source_node: source_node,
                reason: reason
              }
              | invalid
            ]}}
      end
    end)
    |> case do
      {:ok, invalid} -> {:ok, Enum.reverse(invalid)}
      {:error, _reason} = error -> error
    end
  end

  defp validate_recoverable_incoming_dynamic_connections([], _captured), do: :ok

  defp validate_recoverable_incoming_dynamic_connections(invalid_connections, %MapSet{} = captured) do
    case Enum.find(invalid_connections, fn %{connection: connection, source_node: source_node} ->
           not MapSet.member?(
             captured,
             {connection.flow_id, connection.id, source_node.id}
           )
         end) do
      nil -> :ok
      %{reason: reason} -> {:error, reason}
    end
  end

  defp validate_recoverable_incoming_dynamic_connections([%{reason: reason} | _invalid_connections], _captured),
    do: {:error, reason}

  defp delete_incoming_dynamic_connections(_repo, [], _project_flow_ids, _source_node_ids), do: {:ok, []}

  defp delete_incoming_dynamic_connections(repo, invalid_connections, project_flow_ids, source_node_ids) do
    connection_ids =
      invalid_connections
      |> Enum.map(& &1.connection.id)
      |> Enum.uniq()
      |> Enum.sort()

    case repo.delete_all(
           from(connection in FlowConnection,
             where:
               connection.id in ^connection_ids and
                 connection.flow_id in ^project_flow_ids and
                 connection.source_node_id in ^source_node_ids
           )
         ) do
      {count, _rows} when count == length(connection_ids) ->
        {:ok, connection_ids}

      {count, _rows} ->
        {:error, {:incoming_dynamic_connection_delete_count_mismatch, length(connection_ids), count}}
    end
  end

  defp recoverable_full_project_connection_sources(opts) do
    if Keyword.get(opts, :full_project_restore, false) do
      case Keyword.get(opts, :pre_restore_snapshot) do
        %{"flows" => flow_entries} when is_list(flow_entries) ->
          collect_pre_restore_connection_sources(flow_entries)

        _missing_or_invalid ->
          MapSet.new()
      end
    end
  end

  defp collect_pre_restore_connection_sources(flow_entries) do
    Enum.reduce_while(flow_entries, MapSet.new(), fn
      %{
        "id" => flow_id,
        "snapshot" => %{"nodes" => nodes, "connections" => connections}
      },
      captured
      when is_integer(flow_id) and flow_id > 0 and is_list(nodes) and is_list(connections) ->
        with {:ok, _node_ids} <- collect_positive_snapshot_ids(nodes),
             {:ok, connection_sources} <-
               collect_snapshot_connection_sources(
                 flow_id,
                 connections,
                 nodes
               ) do
          {:cont, Enum.reduce(connection_sources, captured, &MapSet.put(&2, &1))}
        else
          {:error, _reason} -> {:halt, MapSet.new()}
        end

      _invalid_entry, _captured ->
        {:halt, MapSet.new()}
    end)
  end

  defp collect_snapshot_connection_sources(flow_id, connections, nodes) do
    Enum.reduce_while(connections, {:ok, []}, fn
      %{"original_id" => connection_id, "source_node_index" => source_node_index}, {:ok, captured}
      when is_integer(connection_id) and connection_id > 0 and
             is_integer(source_node_index) and source_node_index >= 0 ->
        case Enum.at(nodes, source_node_index) do
          %{"original_id" => source_node_id}
          when is_integer(source_node_id) and source_node_id > 0 ->
            {:cont, {:ok, [{flow_id, connection_id, source_node_id} | captured]}}

          _missing_or_invalid_source ->
            {:halt, {:error, :invalid_snapshot_connection_source}}
        end

      _invalid_connection, {:ok, _captured} ->
        {:halt, {:error, :invalid_snapshot_connection_source}}
    end)
  end

  defp validate_incoming_dynamic_pin_for_connection(connection, source_node, restored_flow_id, target_exit_ids) do
    referenced_flow_id =
      normalize_materialized_reference_id(source_node.data["referenced_flow_id"])

    if referenced_flow_id == restored_flow_id do
      case validate_incoming_dynamic_pin(
             connection.source_pin,
             target_exit_ids
           ) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error,
           {:incoming_dynamic_exit_pin_would_break, connection.id, connection.source_pin, restored_flow_id, reason}}
      end
    else
      :ok
    end
  end

  defp validate_incoming_dynamic_pin(pin, target_exit_ids) do
    case parse_dynamic_exit_pin(pin) do
      {:ok, exit_id} ->
        if MapSet.member?(target_exit_ids, exit_id),
          do: :ok,
          else: {:error, :exit_missing_from_snapshot}

      {:error, reason} ->
        {:error, reason}

      :not_dynamic ->
        :ok
    end
  end

  defp lock_restore_scope(repo, flow_id) do
    node_ids =
      repo.all(
        from(node in FlowNode,
          where: node.flow_id == ^flow_id,
          order_by: [asc: node.id],
          lock: "FOR UPDATE",
          select: node.id
        )
      )

    connection_ids =
      repo.all(
        from(connection in FlowConnection,
          where: connection.flow_id == ^flow_id,
          order_by: [asc: connection.id],
          lock: "FOR UPDATE",
          select: connection.id
        )
      )

    config_ids =
      repo.all(
        from(config in SequenceConfig,
          where: config.flow_node_id in ^node_ids,
          order_by: [asc: config.flow_node_id],
          lock: "FOR UPDATE",
          select: config.flow_node_id
        )
      )

    track_ids =
      repo.all(
        from(track in SequenceTrack,
          where: track.flow_node_id in ^node_ids,
          order_by: [asc: track.id],
          lock: "FOR UPDATE",
          select: track.id
        )
      )

    visual_layer_ids =
      repo.all(
        from(layer in SequenceVisualLayer,
          where: layer.flow_node_id in ^node_ids,
          order_by: [asc: layer.id],
          lock: "FOR UPDATE",
          select: layer.id
        )
      )

    {:ok,
     %{
       nodes: node_ids,
       connections: connection_ids,
       sequence_configs: config_ids,
       sequence_tracks: track_ids,
       sequence_visual_layers: visual_layer_ids
     }}
  end

  defp validate_restore_ownership(repo, flow_id, nodes, connections) do
    node_ids = Enum.map(nodes, & &1["original_id"])
    target_node_ids = MapSet.new(node_ids)
    connection_ids = Enum.map(connections, & &1["original_id"])
    track_owners = snapshot_resource_owners(nodes, "sequence_tracks")
    visual_layer_owners = snapshot_resource_owners(nodes, "sequence_visual_layers")

    with :ok <- validate_node_ownership(repo, flow_id, node_ids),
         :ok <- validate_connection_ownership(repo, flow_id, connection_ids, target_node_ids),
         :ok <- validate_resource_ownership(repo, SequenceTrack, flow_id, track_owners),
         :ok <-
           validate_resource_ownership(
             repo,
             SequenceVisualLayer,
             flow_id,
             visual_layer_owners
           ),
         :ok <- validate_sequence_type_transitions(repo, flow_id, nodes, target_node_ids),
         :ok <- validate_parent_boundary_transitions(repo, flow_id, nodes, target_node_ids) do
      {:ok, :valid}
    end
  end

  defp validate_node_ownership(repo, flow_id, node_ids) do
    conflicts =
      repo.all(
        from(node in FlowNode,
          where: node.id in ^node_ids and node.flow_id != ^flow_id,
          select: {node.id, node.flow_id}
        )
      )

    case conflicts do
      [] -> :ok
      [conflict | _rest] -> {:error, {:snapshot_node_owned_by_other_flow, conflict}}
    end
  end

  defp validate_connection_ownership(repo, flow_id, connection_ids, target_node_ids) do
    existing =
      repo.all(
        from(connection in FlowConnection,
          where: connection.id in ^connection_ids,
          select: {
            connection.id,
            connection.flow_id,
            connection.source_node_id,
            connection.target_node_id
          }
        )
      )

    case Enum.find(existing, fn {_id, owner_flow_id, source_id, target_id} ->
           owner_flow_id != flow_id or
             not MapSet.member?(target_node_ids, source_id) or
             not MapSet.member?(target_node_ids, target_id)
         end) do
      nil -> :ok
      conflict -> {:error, {:snapshot_connection_ownership_conflict, conflict}}
    end
  end

  defp snapshot_resource_owners(nodes, key) do
    Map.new(
      for %{"type" => "sequence", "original_id" => node_id} = node <- nodes,
          resource <- node[key] do
        {resource["original_id"], node_id}
      end
    )
  end

  defp validate_resource_ownership(repo, schema, flow_id, expected_owners) do
    ids = Map.keys(expected_owners)

    existing =
      repo.all(
        from(resource in schema,
          join: node in FlowNode,
          on: node.id == resource.flow_node_id,
          where: resource.id in ^ids,
          select: {resource.id, resource.flow_node_id, node.flow_id}
        )
      )

    case Enum.find(existing, fn {resource_id, node_id, owner_flow_id} ->
           owner_flow_id != flow_id or Map.get(expected_owners, resource_id) != node_id
         end) do
      nil -> :ok
      conflict -> {:error, {:snapshot_sequence_resource_ownership_conflict, schema, conflict}}
    end
  end

  defp validate_sequence_type_transitions(repo, flow_id, nodes, target_node_ids) do
    target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
    target_node_ids = MapSet.to_list(target_node_ids)

    transition_ids =
      sequence_transition_ids(repo, flow_id, target_types)

    case sequence_transition_conflicts(repo, flow_id, transition_ids, target_node_ids) do
      [] -> :ok
      [connection_id | _rest] -> {:error, {:sequence_transition_conflicts_with_trash, connection_id}}
    end
  end

  defp reconcile_full_project_sequence_transition_connections(repo, flow_id, nodes, opts) do
    if Keyword.get(opts, :full_project_restore, false) do
      target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
      target_node_ids = Map.keys(target_types)
      transition_ids = sequence_transition_ids(repo, flow_id, target_types)

      connection_ids =
        sequence_transition_conflicts(
          repo,
          flow_id,
          transition_ids,
          target_node_ids
        )

      with :ok <-
             validate_recoverable_sequence_transition_connections(
               flow_id,
               connection_ids,
               opts
             ) do
        delete_sequence_transition_connections(
          repo,
          flow_id,
          connection_ids
        )
      end
    else
      {:ok, []}
    end
  end

  defp reconcile_full_project_cross_boundary_connections(repo, project_id, flow_id, nodes, opts) do
    if Keyword.get(opts, :full_project_restore, false) do
      target_nodes = Map.new(nodes, &{&1["original_id"], &1})
      target_node_ids = Map.keys(target_nodes)

      connections =
        lock_cross_boundary_connections(
          repo,
          flow_id,
          target_node_ids
        )

      with :ok <-
             validate_cross_boundary_connection_ownership(
               repo,
               flow_id,
               connections
             ),
           {:ok, invalid_connections} <-
             invalid_future_cross_boundary_connections(
               repo,
               project_id,
               connections,
               target_nodes
             ),
           :ok <-
             validate_recoverable_cross_boundary_connections(
               flow_id,
               invalid_connections,
               opts
             ) do
        delete_cross_boundary_connections(
          repo,
          flow_id,
          invalid_connections
        )
      end
    else
      {:ok, []}
    end
  end

  defp lock_cross_boundary_connections(_repo, _flow_id, []), do: []

  defp lock_cross_boundary_connections(repo, flow_id, target_node_ids) do
    repo.all(
      from(connection in FlowConnection,
        where: connection.flow_id == ^flow_id,
        where:
          (connection.source_node_id in ^target_node_ids and
             connection.target_node_id not in ^target_node_ids) or
            (connection.target_node_id in ^target_node_ids and
               connection.source_node_id not in ^target_node_ids),
        order_by: [asc: connection.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp validate_cross_boundary_connection_ownership(_repo, _flow_id, []), do: :ok

  defp validate_cross_boundary_connection_ownership(repo, flow_id, connections) do
    node_ids =
      connections
      |> Enum.flat_map(&[&1.source_node_id, &1.target_node_id])
      |> Enum.uniq()

    owners =
      from(node in FlowNode,
        where: node.id in ^node_ids,
        select: {node.id, node.flow_id}
      )
      |> repo.all()
      |> Map.new()

    case Enum.find(
           connections,
           &cross_boundary_connection_ownership_conflict?(&1, flow_id, owners)
         ) do
      nil ->
        :ok

      connection ->
        ownership_details =
          cross_boundary_connection_ownership_details(connection, owners)

        {:error, {:cross_boundary_connection_ownership_conflict, ownership_details}}
    end
  end

  defp cross_boundary_connection_ownership_conflict?(connection, flow_id, owners) do
    Map.get(owners, connection.source_node_id) != flow_id or
      Map.get(owners, connection.target_node_id) != flow_id
  end

  defp cross_boundary_connection_ownership_details(connection, owners) do
    {
      connection.id,
      connection.flow_id,
      connection.source_node_id,
      Map.get(owners, connection.source_node_id),
      connection.target_node_id,
      Map.get(owners, connection.target_node_id)
    }
  end

  defp invalid_future_cross_boundary_connections(repo, project_id, connections, target_nodes) do
    connections
    |> Enum.reduce_while({:ok, []}, fn connection, {:ok, invalid} ->
      case future_cross_boundary_connection_result(
             repo,
             project_id,
             connection,
             target_nodes
           ) do
        :ok ->
          {:cont, {:ok, invalid}}

        {:error, reason} ->
          {:cont,
           {:ok,
            [
              %{connection_id: connection.id, reason: reason}
              | invalid
            ]}}
      end
    end)
    |> case do
      {:ok, invalid} -> {:ok, Enum.reverse(invalid)}
      {:error, _reason} = error -> error
    end
  end

  defp future_cross_boundary_connection_result(repo, project_id, connection, target_nodes) do
    case {
      Map.get(target_nodes, connection.source_node_id),
      Map.get(target_nodes, connection.target_node_id)
    } do
      {%{} = source_node, nil} ->
        validate_future_source_pin(
          repo,
          project_id,
          connection,
          source_node
        )

      {nil, %{} = target_node} ->
        validate_future_target_pin(connection, target_node)

      endpoints ->
        {:error, {:invalid_cross_boundary_connection_classification, connection.id, endpoints}}
    end
  end

  defp validate_future_source_pin(repo, project_id, connection, source_node) do
    case future_source_pin_valid?(
           repo,
           project_id,
           source_node,
           connection.source_pin
         ) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error, {:invalid_future_source_pin, connection.source_node_id, connection.source_pin, source_node["type"]}}

      {:error, _reason} = error ->
        error
    end
  end

  defp future_source_pin_valid?(repo, project_id, %{"type" => "subflow", "data" => data}, source_pin) do
    referenced_flow_id =
      normalize_materialized_reference_id(data["referenced_flow_id"])

    case referenced_flow_id do
      nil ->
        {:ok, false}

      referenced_flow_id ->
        validate_future_subflow_source_pin(
          repo,
          project_id,
          referenced_flow_id,
          source_pin
        )
    end
  end

  defp future_source_pin_valid?(_repo, _project_id, %{"type" => type, "data" => data}, source_pin) do
    {:ok,
     NodeConnectionRules.valid_output_pin?(
       type,
       data || %{},
       source_pin
     )}
  end

  defp validate_future_subflow_source_pin(repo, project_id, referenced_flow_id, source_pin) do
    if future_referenced_flow_active?(
         repo,
         project_id,
         referenced_flow_id
       ) do
      {:ok,
       future_dynamic_exit_pin_valid?(
         repo,
         referenced_flow_id,
         source_pin
       )}
    else
      {:error, {:invalid_future_subflow_reference, referenced_flow_id}}
    end
  end

  defp future_referenced_flow_active?(repo, project_id, referenced_flow_id) do
    repo.exists?(
      from(flow in Flow,
        where:
          flow.id == ^referenced_flow_id and
            flow.project_id == ^project_id and
            is_nil(flow.deleted_at)
      )
    )
  end

  defp future_dynamic_exit_pin_valid?(repo, referenced_flow_id, source_pin) do
    case parse_dynamic_exit_pin(source_pin) do
      {:ok, exit_id} ->
        future_exit_active?(
          repo,
          referenced_flow_id,
          exit_id
        )

      _not_valid_dynamic_pin ->
        false
    end
  end

  defp future_exit_active?(repo, referenced_flow_id, exit_id) do
    repo.exists?(
      from(node in FlowNode,
        where:
          node.id == ^exit_id and
            node.flow_id == ^referenced_flow_id and
            node.type == "exit" and
            is_nil(node.deleted_at)
      )
    )
  end

  defp validate_future_target_pin(connection, target_node) do
    if NodeConnectionRules.valid_input_pin?(
         target_node["type"],
         connection.target_pin
       ) do
      :ok
    else
      {:error, {:invalid_future_target_pin, connection.target_node_id, connection.target_pin, target_node["type"]}}
    end
  end

  defp validate_recoverable_cross_boundary_connections(_flow_id, [], _opts), do: :ok

  defp validate_recoverable_cross_boundary_connections(flow_id, invalid_connections, opts) do
    case pre_restore_flow_connection_ids(flow_id, opts) do
      {:ok, captured_ids} ->
        missing =
          Enum.reject(
            invalid_connections,
            &MapSet.member?(captured_ids, &1.connection_id)
          )

        if missing == [] do
          :ok
        else
          {:error, {:cross_boundary_connections_missing_from_pre_restore_snapshot, flow_id, missing}}
        end

      {:error, reason} ->
        {:error, {:cross_boundary_connections_not_recoverable, flow_id, invalid_connections, reason}}
    end
  end

  defp delete_cross_boundary_connections(_repo, _flow_id, []), do: {:ok, []}

  defp delete_cross_boundary_connections(repo, flow_id, invalid_connections) do
    connection_ids =
      invalid_connections
      |> Enum.map(& &1.connection_id)
      |> Enum.uniq()
      |> Enum.sort()

    case repo.delete_all(
           from(connection in FlowConnection,
             where:
               connection.flow_id == ^flow_id and
                 connection.id in ^connection_ids
           )
         ) do
      {count, _rows} when count == length(connection_ids) ->
        {:ok, connection_ids}

      {count, _rows} ->
        {:error, {:cross_boundary_connection_delete_count_mismatch, length(connection_ids), count}}
    end
  end

  defp validate_recoverable_sequence_transition_connections(_flow_id, [], _opts), do: :ok

  defp validate_recoverable_sequence_transition_connections(flow_id, connection_ids, opts) do
    case pre_restore_flow_connection_ids(flow_id, opts) do
      {:ok, captured_ids} ->
        missing_ids =
          connection_ids
          |> Enum.reject(&MapSet.member?(captured_ids, &1))
          |> Enum.sort()

        if missing_ids == [] do
          :ok
        else
          {:error, {:sequence_transition_connections_missing_from_pre_restore_snapshot, flow_id, missing_ids}}
        end

      {:error, reason} ->
        {:error, {:sequence_transition_connections_not_recoverable, flow_id, Enum.sort(connection_ids), reason}}
    end
  end

  defp pre_restore_flow_connection_ids(flow_id, opts) do
    with %{"flows" => flow_entries} when is_list(flow_entries) <-
           Keyword.get(opts, :pre_restore_snapshot),
         %{"snapshot" => %{"connections" => connections}}
         when is_list(connections) <-
           Enum.find(flow_entries, &(&1["id"] == flow_id)),
         {:ok, connection_ids} <- collect_positive_snapshot_ids(connections) do
      {:ok, MapSet.new(connection_ids)}
    else
      nil -> {:error, :pre_restore_flow_missing}
      _missing_or_invalid -> {:error, :invalid_pre_restore_snapshot}
    end
  end

  defp collect_positive_snapshot_ids(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn
      %{"original_id" => id}, {:ok, ids} when is_integer(id) and id > 0 ->
        {:cont, {:ok, [id | ids]}}

      _invalid, {:ok, _ids} ->
        {:halt, {:error, :invalid_snapshot_original_id}}
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      {:error, _reason} = error -> error
    end
  end

  defp delete_sequence_transition_connections(_repo, _flow_id, []), do: {:ok, []}

  defp delete_sequence_transition_connections(repo, flow_id, connection_ids) do
    case repo.delete_all(
           from(connection in FlowConnection,
             where:
               connection.flow_id == ^flow_id and
                 connection.id in ^connection_ids
           )
         ) do
      {count, _rows} when count == length(connection_ids) ->
        {:ok, connection_ids}

      {count, _rows} ->
        {:error, {:sequence_transition_connection_delete_count_mismatch, length(connection_ids), count}}
    end
  end

  defp sequence_transition_ids(repo, flow_id, target_types) do
    node_ids = Map.keys(target_types)

    from(node in FlowNode,
      where:
        node.flow_id == ^flow_id and
          node.id in ^node_ids and
          node.type != "sequence",
      select: node.id
    )
    |> repo.all()
    |> Enum.filter(&(Map.get(target_types, &1) == "sequence"))
  end

  defp sequence_transition_conflicts(_repo, _flow_id, [], _target_node_ids), do: []

  defp sequence_transition_conflicts(repo, flow_id, transition_ids, target_node_ids) do
    repo.all(
      from(connection in FlowConnection,
        where: connection.flow_id == ^flow_id,
        where:
          connection.source_node_id in ^transition_ids or
            connection.target_node_id in ^transition_ids,
        where:
          not (connection.source_node_id in ^target_node_ids and
                 connection.target_node_id in ^target_node_ids),
        order_by: [asc: connection.id],
        select: connection.id
      )
    )
  end

  defp validate_parent_boundary_transitions(repo, flow_id, nodes, target_node_ids) do
    target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
    target_node_ids = MapSet.to_list(target_node_ids)

    no_longer_sequence_ids =
      sequence_to_nonsequence_transition_ids(
        repo,
        flow_id,
        target_node_ids,
        target_types
      )

    conflict =
      if no_longer_sequence_ids == [] do
        nil
      else
        repo.one(
          from(node in FlowNode,
            where:
              node.flow_id == ^flow_id and node.parent_id in ^no_longer_sequence_ids and
                node.id not in ^target_node_ids,
            select: {node.id, node.parent_id},
            limit: 1
          )
        )
      end

    case conflict do
      nil -> :ok
      child -> {:error, {:node_type_transition_conflicts_with_trash_parent, child}}
    end
  end

  defp reconcile_full_project_sequence_transition_children(repo, flow_id, nodes, opts) do
    if Keyword.get(opts, :full_project_restore, false) do
      target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
      target_node_ids = Map.keys(target_types)

      transition_ids =
        sequence_to_nonsequence_transition_ids(
          repo,
          flow_id,
          target_node_ids,
          target_types
        )

      child_states =
        sequence_transition_child_states(
          repo,
          flow_id,
          transition_ids,
          target_node_ids
        )

      with :ok <-
             validate_recoverable_sequence_transition_children(
               flow_id,
               child_states,
               opts
             ) do
        detach_sequence_transition_children(repo, flow_id, child_states)
      end
    else
      {:ok, []}
    end
  end

  defp sequence_to_nonsequence_transition_ids(repo, flow_id, target_node_ids, target_types) do
    from(node in FlowNode,
      where:
        node.flow_id == ^flow_id and node.id in ^target_node_ids and
          node.type == "sequence",
      select: node.id
    )
    |> repo.all()
    |> Enum.reject(&(Map.get(target_types, &1) == "sequence"))
  end

  defp sequence_transition_child_states(_repo, _flow_id, [], _target_node_ids), do: []

  defp sequence_transition_child_states(repo, flow_id, transition_ids, target_node_ids) do
    repo.all(
      from(node in FlowNode,
        where:
          node.flow_id == ^flow_id and node.parent_id in ^transition_ids and
            node.id not in ^target_node_ids,
        order_by: [asc: node.id],
        select: {node.id, node.parent_id}
      )
    )
  end

  defp validate_recoverable_sequence_transition_children(_flow_id, [], _opts), do: :ok

  defp validate_recoverable_sequence_transition_children(flow_id, child_states, opts) do
    case pre_restore_flow_node_parent_states(flow_id, opts) do
      {:ok, captured_states} ->
        missing_states =
          child_states
          |> Enum.reject(&MapSet.member?(captured_states, &1))
          |> Enum.sort()

        if missing_states == [] do
          :ok
        else
          {:error, {:sequence_transition_children_missing_from_pre_restore_snapshot, flow_id, missing_states}}
        end

      {:error, reason} ->
        {:error, {:sequence_transition_children_not_recoverable, flow_id, Enum.sort(child_states), reason}}
    end
  end

  defp pre_restore_flow_node_parent_states(flow_id, opts) do
    with %{"flows" => flow_entries} when is_list(flow_entries) <-
           Keyword.get(opts, :pre_restore_snapshot),
         %{"snapshot" => %{"nodes" => nodes}}
         when is_list(nodes) <-
           Enum.find(flow_entries, &(&1["id"] == flow_id)),
         {:ok, node_parent_states} <- collect_snapshot_node_parent_states(nodes) do
      {:ok, MapSet.new(node_parent_states)}
    else
      nil -> {:error, :pre_restore_flow_missing}
      _missing_or_invalid -> {:error, :invalid_pre_restore_snapshot}
    end
  end

  defp collect_snapshot_node_parent_states(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn
      %{"original_id" => node_id, "parent_id" => parent_id}, {:ok, states}
      when is_integer(node_id) and node_id > 0 and
             (is_nil(parent_id) or (is_integer(parent_id) and parent_id > 0)) ->
        {:cont, {:ok, [{node_id, parent_id} | states]}}

      _invalid_node, {:ok, _states} ->
        {:halt, {:error, :invalid_snapshot_node_parent_state}}
    end)
  end

  defp detach_sequence_transition_children(_repo, _flow_id, []), do: {:ok, []}

  defp detach_sequence_transition_children(repo, flow_id, child_states) do
    child_ids = Enum.map(child_states, &elem(&1, 0))

    case repo.update_all(
           from(node in FlowNode,
             where: node.flow_id == ^flow_id and node.id in ^child_ids
           ),
           set: [parent_id: nil, updated_at: MaterializationHelpers.now()]
         ) do
      {count, _rows} when count == length(child_ids) ->
        {:ok, child_ids}

      {count, _rows} ->
        {:error, {:sequence_transition_child_detach_count_mismatch, length(child_ids), count}}
    end
  end

  defp soft_delete_absent_active_nodes(repo, flow_id, target_node_ids) do
    base_query =
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and is_nil(node.deleted_at)
      )

    query =
      if target_node_ids == [] do
        base_query
      else
        from(node in base_query, where: node.id not in ^target_node_ids)
      end

    node_states = repo.all(from(node in query, select: {node.id, node.parent_id}))
    node_ids = Enum.map(node_states, &elem(&1, 0))
    now = MaterializationHelpers.now()

    if node_ids != [] do
      affected_child_states =
        repo.all(
          from(node in FlowNode,
            where: node.parent_id in ^node_ids,
            select: {node.id, node.parent_id}
          )
        )

      repo.update_all(
        from(node in FlowNode, where: node.id in ^node_ids),
        set: [deleted_at: now, updated_at: now]
      )

      (node_states ++ affected_child_states)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.each(fn
        {_node_id, nil} ->
          :ok

        {node_id, parent_id} ->
          repo.update_all(
            from(node in FlowNode, where: node.id == ^node_id),
            set: [parent_id: parent_id]
          )
      end)
    end

    {:ok, node_ids}
  end

  defp clear_target_node_state(_repo, _flow_id, []), do: {:ok, %{configs: 0, tracks: 0, visual_layers: 0}}

  defp clear_target_node_state(repo, flow_id, target_node_ids) do
    now = MaterializationHelpers.now()

    {connections, _} =
      repo.delete_all(
        from(connection in FlowConnection,
          where:
            connection.flow_id == ^flow_id and
              connection.source_node_id in ^target_node_ids and
              connection.target_node_id in ^target_node_ids
        )
      )

    repo.update_all(
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and node.id in ^target_node_ids
      ),
      set: [parent_id: nil, updated_at: now]
    )

    {visual_layers, _} =
      repo.delete_all(from(layer in SequenceVisualLayer, where: layer.flow_node_id in ^target_node_ids))

    {tracks, _} =
      repo.delete_all(from(track in SequenceTrack, where: track.flow_node_id in ^target_node_ids))

    {configs, _} =
      repo.delete_all(from(config in SequenceConfig, where: config.flow_node_id in ^target_node_ids))

    {:ok,
     %{
       configs: configs,
       tracks: tracks,
       visual_layers: visual_layers,
       connections: connections
     }}
  end

  defp prepare_target_dialogue_id_swaps(_repo, _flow_id, []), do: {:ok, 0}

  defp prepare_target_dialogue_id_swaps(repo, flow_id, target_node_ids) do
    token = String.replace(Ecto.UUID.generate(), "-", "")

    from(node in FlowNode,
      where:
        node.flow_id == ^flow_id and
          node.id in ^target_node_ids and
          node.type == "dialogue",
      order_by: [asc: node.id]
    )
    |> repo.all()
    |> Enum.reduce_while({:ok, 0}, fn node, {:ok, count} ->
      temporary_id = "restore_#{token}_#{node.id}"
      data = Map.put(node.data || %{}, "localization_id", temporary_id)

      result =
        node
        |> Ecto.Changeset.change(data: data)
        |> Ecto.Changeset.unique_constraint(:data,
          name: :flow_nodes_dialogue_localization_id_unique
        )
        |> repo.update()

      case result do
        {:ok, _node} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reconcile_snapshot_nodes(repo, flow_id, nodes_data, snapshot, project_id, opts) do
    node_ids = Enum.map(nodes_data, & &1["original_id"])

    existing_nodes =
      from(node in FlowNode, where: node.id in ^node_ids)
      |> repo.all()
      |> Map.new(&{&1.id, &1})

    now = MaterializationHelpers.now()

    result =
      Enum.reduce_while(nodes_data, {:ok, []}, fn node_data, {:ok, restored_nodes} ->
        existing = Map.get(existing_nodes, node_data["original_id"])

        continue_node_reconciliation(
          reconcile_snapshot_node(repo, flow_id, node_data, existing, snapshot, project_id, opts, now),
          restored_nodes
        )
      end)

    case result do
      {:ok, restored_nodes} ->
        restored_nodes = Enum.reverse(restored_nodes)
        identity_map = Map.new(node_ids, &{&1, &1})
        {:ok, %{nodes: restored_nodes, node_ids: node_ids, node_id_map: identity_map}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp continue_node_reconciliation({:ok, restored_node}, restored_nodes),
    do: {:cont, {:ok, [restored_node | restored_nodes]}}

  defp continue_node_reconciliation({:error, reason}, _restored_nodes), do: {:halt, {:error, reason}}

  defp reconcile_snapshot_node(
         _repo,
         flow_id,
         %{"original_id" => node_id},
         %FlowNode{flow_id: owner_flow_id},
         _snapshot,
         _project_id,
         _opts,
         _now
       )
       when owner_flow_id != flow_id do
    {:error, {:snapshot_node_owned_by_other_flow, {node_id, owner_flow_id}}}
  end

  defp reconcile_snapshot_node(repo, flow_id, node_data, existing, snapshot, project_id, opts, now) do
    data = resolve_node_asset_refs(node_data["data"], snapshot, project_id, opts)

    node =
      existing ||
        %FlowNode{
          id: node_data["original_id"],
          flow_id: flow_id,
          inserted_at: now,
          updated_at: now
        }

    changeset =
      node
      |> FlowNode.materialize_changeset(%{
        type: node_data["type"],
        position_x: node_data["position_x"],
        position_y: node_data["position_y"],
        data: data,
        word_count: WordCount.for_node_data(node_data["type"], data),
        source: node_data["source"],
        parent_id: nil
      })
      |> Ecto.Changeset.put_change(:deleted_at, nil)

    if existing, do: repo.update(changeset), else: repo.insert(changeset)
  end

  defp reconcile_sequence_resources(repo, nodes_data, restored_nodes, snapshot, project_id, opts) do
    now = MaterializationHelpers.now()
    restored_nodes_by_id = Map.new(restored_nodes, &{&1.id, &1})

    Enum.reduce_while(
      nodes_data,
      {:ok, %{configs: 0, track_id_map: %{}, visual_layer_id_map: %{}}},
      fn
        %{"type" => "sequence", "original_id" => node_id} = node_data, {:ok, result} ->
          with %FlowNode{} <- Map.get(restored_nodes_by_id, node_id),
               {:ok, config_count} <-
                 insert_sequence_config(repo, node_id, node_data["sequence_config"], now),
               {:ok, track_id_map} <-
                 insert_restored_sequence_tracks(
                   repo,
                   node_id,
                   node_data["sequence_tracks"],
                   snapshot,
                   project_id,
                   opts,
                   now
                 ),
               {:ok, visual_layer_id_map} <-
                 insert_restored_sequence_visual_layers(
                   repo,
                   node_id,
                   node_data["sequence_visual_layers"],
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
            nil -> {:halt, {:error, {:restored_sequence_node_missing, node_id}}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        _node_data, {:ok, result} ->
          {:cont, {:ok, result}}
      end
    )
  end

  defp insert_restored_sequence_tracks(repo, node_id, tracks, snapshot, project_id, opts, now) do
    insert_restored_sequence_items(tracks, fn track_data ->
      asset_id = resolve_flow_asset(track_data["asset_id"], snapshot, project_id, opts)

      attrs =
        track_data
        |> Map.take(["kind", "position", "start_time", "end_time", "volume"])
        |> Map.put("flow_node_id", node_id)
        |> Map.put("asset_id", asset_id)

      %SequenceTrack{
        id: track_data["original_id"],
        inserted_at: now,
        updated_at: now
      }
      |> SequenceTrack.create_changeset(attrs)
      |> repo.insert()
    end)
  end

  defp insert_restored_sequence_visual_layers(repo, node_id, layers, snapshot, project_id, opts, now) do
    if flow_asset_mode(opts) == :drop do
      {:ok, %{}}
    else
      insert_restored_sequence_items(layers, fn layer_data ->
        insert_restored_sequence_visual_layer(
          repo,
          node_id,
          layer_data,
          snapshot,
          project_id,
          opts,
          now
        )
      end)
    end
  end

  defp insert_restored_sequence_visual_layer(repo, node_id, layer_data, snapshot, project_id, opts, now) do
    asset_id = resolve_flow_asset(layer_data["asset_id"], snapshot, project_id, opts)

    if is_nil(asset_id) do
      {:error, {:missing_sequence_visual_layer_asset, layer_data["asset_id"]}}
    else
      attrs =
        layer_data
        |> Map.take([
          "kind",
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

      %SequenceVisualLayer{
        id: layer_data["original_id"],
        inserted_at: now,
        updated_at: now
      }
      |> SequenceVisualLayer.create_changeset(attrs)
      |> repo.insert()
    end
  end

  defp insert_restored_sequence_items(items, insert_fun) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, id_map} ->
      case insert_fun.(item) do
        {:ok, resource} ->
          {:cont, {:ok, Map.put(id_map, item["original_id"], resource.id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp reconcile_snapshot_connections(repo, flow_id, connections, nodes, target_node_ids) do
    if target_node_ids != [] do
      repo.delete_all(
        from(connection in FlowConnection,
          where:
            connection.flow_id == ^flow_id and
              connection.source_node_id in ^target_node_ids and
              connection.target_node_id in ^target_node_ids
        )
      )
    end

    now = MaterializationHelpers.now()

    Enum.reduce_while(connections, {:ok, %{connection_id_map: %{}}}, fn connection, {:ok, result} ->
      source_node = Enum.at(nodes, connection["source_node_index"])
      target_node = Enum.at(nodes, connection["target_node_index"])

      attrs = %{
        source_node_id: source_node["original_id"],
        target_node_id: target_node["original_id"],
        source_pin: connection["source_pin"],
        target_pin: connection["target_pin"],
        label: connection["label"]
      }

      changeset =
        FlowConnection.create_changeset(
          %FlowConnection{
            id: connection["original_id"],
            flow_id: flow_id,
            inserted_at: now,
            updated_at: now
          },
          attrs
        )

      case repo.insert(changeset) do
        {:ok, restored_connection} ->
          {:cont,
           {:ok,
            %{
              connection_id_map:
                Map.put(
                  result.connection_id_map,
                  connection["original_id"],
                  restored_connection.id
                )
            }}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp extract_restored_node_localization(nodes) do
    Enum.reduce_while(nodes, {:ok, 0}, fn node, {:ok, count} ->
      case Localization.extract_flow_node(node) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp rebuild_restored_node_references(nodes, deleted_node_ids, project_id) do
    Enum.each(deleted_node_ids, fn node_id ->
      References.delete_flow_node_entity_references(node_id)
      References.delete_flow_node_variable_references(node_id)
    end)

    case Enum.reduce_while(nodes, :ok, fn node, result ->
           continue_node_reference_rebuild(
             node,
             result,
             project_id
           )
         end) do
      :ok -> {:ok, length(nodes)}
      {:error, reason} -> {:error, reason}
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

  defp link_snapshot_node_parents(repo, nodes_data, node_id_map) do
    nodes_by_original_id =
      nodes_data
      |> Enum.reject(&is_nil(&1["original_id"]))
      |> Map.new(&{&1["original_id"], &1})

    Enum.reduce_while(nodes_data, {:ok, 0}, fn node_data, acc ->
      link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map)
    end)
  end

  defp link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map) do
    link_snapshot_node_parent(
      repo,
      node_data,
      acc,
      nodes_by_original_id,
      node_id_map,
      node_data["parent_id"]
    )
  end

  defp link_snapshot_node_parent(_repo, _node_data, {:ok, count}, _nodes_by_original_id, _node_id_map, nil) do
    {:cont, {:ok, count}}
  end

  defp link_snapshot_node_parent(repo, node_data, {:ok, count}, nodes_by_original_id, node_id_map, parent_original_id) do
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

  defp insert_sequence_resources(repo, nodes_data, node_id_map, snapshot, project_id, opts, now) do
    Enum.reduce_while(
      nodes_data,
      {:ok, %{configs: 0, track_id_map: %{}, visual_layer_id_map: %{}}},
      fn
        %{"type" => "sequence"} = node_data, {:ok, result} ->
          node_id = Map.fetch!(node_id_map, node_data["original_id"])

          with {:ok, config_count} <- insert_sequence_config(repo, node_id, node_data["sequence_config"], now),
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

        _node_data, {:ok, result} ->
          {:cont, {:ok, result}}
      end
    )
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
        asset_id = resolve_flow_asset(track_data["asset_id"], snapshot, project_id, opts)

        attrs =
          track_data
          |> Map.take(["kind", "position", "start_time", "end_time", "volume"])
          |> Map.put("flow_node_id", node_id)
          |> Map.put("asset_id", asset_id)

        %SequenceTrack{inserted_at: now, updated_at: now}
        |> SequenceTrack.create_changeset(attrs)
        |> repo.insert()
      end
    )
  end

  defp insert_sequence_tracks(_repo, _node_id, tracks, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_tracks_snapshot, tracks}}
  end

  defp insert_sequence_visual_layers(repo, node_id, layers, snapshot, project_id, opts, now) when is_list(layers) do
    if flow_asset_mode(opts) == :drop do
      {:ok, %{}}
    else
      insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now)
    end
  end

  defp insert_sequence_visual_layers(_repo, _node_id, layers, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_visual_layers_snapshot, layers}}
  end

  defp insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now) do
    insert_sequence_items(
      layers,
      :sequence_visual_layer,
      fn layer_data ->
        asset_id = resolve_flow_asset(layer_data["asset_id"], snapshot, project_id, opts)
        insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now)
      end
    )
  end

  defp insert_sequence_visual_layer(_repo, _node_id, layer_data, nil, _now) do
    {:error, {:missing_sequence_visual_layer_asset, layer_data["asset_id"]}}
  end

  defp insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now) do
    attrs =
      layer_data
      |> Map.take([
        "kind",
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
    |> SequenceVisualLayer.create_changeset(attrs)
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
        resolved = resolve_flow_asset(audio_id, snapshot, project_id, opts)
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
          case repo.insert(materialized_node_changeset(flow_id, node_data, data, now)) do
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

  defp materialized_node_changeset(flow_id, node_data, data, now) do
    FlowNode.materialize_changeset(%FlowNode{flow_id: flow_id, inserted_at: now, updated_at: now}, %{
      type: node_data["type"],
      position_x: node_data["position_x"] || 0.0,
      position_y: node_data["position_y"] || 0.0,
      data: data,
      word_count: WordCount.for_node_data(node_data["type"], data),
      source: node_data["source"] || "manual"
    })
  end

  defp insert_flow_connections(_repo, _flow_id, [], _nodes_data, _materialized_nodes_data, _node_id_map, _opts, _now),
    do: {:ok, %{}}

  defp insert_flow_connections(
         repo,
         flow_id,
         connections_data,
         nodes_data,
         materialized_nodes_data,
         node_id_map,
         opts,
         now
       ) do
    Enum.reduce_while(connections_data, {:ok, %{}}, fn connection_data, {:ok, id_map} ->
      source_node = Enum.at(nodes_data, connection_data["source_node_index"])
      target_node = Enum.at(nodes_data, connection_data["target_node_index"])

      materialized_source_node =
        Enum.at(materialized_nodes_data, connection_data["source_node_index"])

      with %{"original_id" => source_original_id} <- source_node,
           %{"original_id" => target_original_id} <- target_node,
           {:ok, source_node_id} <- Map.fetch(node_id_map, source_original_id),
           {:ok, target_node_id} <- Map.fetch(node_id_map, target_original_id),
           {:ok, source_pin} <-
             materialize_dynamic_pin(
               repo,
               connection_data,
               source_node,
               materialized_source_node,
               opts
             ),
           {:ok, connection} <-
             %FlowConnection{flow_id: flow_id, inserted_at: now, updated_at: now}
             |> FlowConnection.create_changeset(%{
               source_node_id: source_node_id,
               target_node_id: target_node_id,
               source_pin: source_pin,
               target_pin: connection_data["target_pin"],
               label: connection_data["label"]
             })
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

  defp materialize_flow_external_references(snapshot, project_id, opts, mode) do
    with {:ok, scene_id} <-
           materialize_external_reference(
             snapshot["scene_id"],
             Scene,
             :scene,
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
      {"avatar_id", Storyarn.Sheets.SheetAvatar, :avatar},
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
         {:ok, data} <-
           AvatarIntegrity.lock_and_normalize_node_avatar_for_project(
             project_id,
             node["type"],
             data
           ) do
      {:ok, Map.put(node, "data", data)}
    end
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
    with :ok <- validate_flow_exit_target_contract(node_id, data) do
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

  defp validate_materialized_dynamic_exit_pins(repo, connections, nodes) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      source_node = Enum.at(nodes, connection["source_node_index"])

      case validate_materialized_dynamic_exit_pin(
             repo,
             connection,
             source_node
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_materialized_dynamic_exit_pin(repo, connection, source_node) do
    case materialized_dynamic_exit_pin(connection, source_node) do
      :not_dynamic ->
        :ok

      {:ok, exit_id, referenced_flow_id} ->
        validate_materialized_exit_node(
          repo,
          connection,
          exit_id,
          referenced_flow_id
        )

      {:error, reason} ->
        dynamic_exit_pin_error(connection, reason)
    end
  end

  defp validate_materialized_exit_node(repo, connection, exit_id, referenced_flow_id) do
    if materialized_exit_node?(repo, exit_id, referenced_flow_id),
      do: :ok,
      else: dynamic_exit_pin_error(connection, :exit_not_in_referenced_flow)
  end

  defp dynamic_exit_pin_error(connection, reason) do
    {:error, {:dynamic_exit_pin_not_materializable, connection["original_id"], connection["source_pin"], reason}}
  end

  defp materialized_dynamic_exit_pin(%{"source_pin" => pin}, %{"type" => "subflow", "data" => data}) do
    case parse_dynamic_exit_pin(pin) do
      :not_dynamic ->
        :not_dynamic

      {:ok, exit_id} ->
        case normalize_materialized_reference_id(data["referenced_flow_id"]) do
          nil -> {:error, :missing_referenced_flow}
          referenced_flow_id -> {:ok, exit_id, referenced_flow_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp materialized_dynamic_exit_pin(_connection, _source_node), do: :not_dynamic

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

  defp resolve_flow_asset(asset_id, snapshot, project_id, opts) do
    case flow_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        AssetHashResolver.resolve_asset_fk(
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          MaterializationHelpers.asset_resolution_opts(opts, asset_mode)
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

  # ========== Diff Snapshots ==========

  # Fields excluded from node comparison (canvas position and denormalized counts are noise)
  @node_ignore_fields ["position_x", "position_y", "original_id", "word_count"]

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    []
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "name",
      :property,
      dgettext("flows", "Renamed flow")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "shortcut",
      :property,
      dgettext("flows", "Changed shortcut")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "description",
      :property,
      dgettext("flows", "Changed description")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "scene_id",
      :property,
      dgettext("flows", "Changed scene")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "settings",
      :property,
      dgettext("flows", "Changed settings")
    )
    |> diff_nodes_and_connections(
      old_snapshot["nodes"] || [],
      new_snapshot["nodes"] || [],
      old_snapshot["connections"] || [],
      new_snapshot["connections"] || []
    )
    |> Enum.reverse()
  end

  # Diff nodes first, then use node matching to normalize connection indexes
  # so that position-only moves don't produce phantom connection changes.
  defp diff_nodes_and_connections(changes, old_nodes, new_nodes, old_conns, new_conns) do
    # Build identity-based index maps so the positional fallback can find
    # a node's index within its own list (old or new) without scanning the
    # concatenated list, which broke when IDs were regenerated.
    old_pos = node_position_map(old_nodes)
    new_pos = node_position_map(new_nodes)

    key_fns = [
      # Primary: match by original_id (same DB session)
      & &1["original_id"],
      # Secondary: match by type + technical_id (stable across restores)
      fn node ->
        tid = get_in(node, ["data", "technical_id"])
        if tid && tid != "", do: {node["type"], tid}
      end,
      # Tertiary: match by type + position within list
      fn node ->
        idx = Map.get(old_pos, node_identity(node)) || Map.get(new_pos, node_identity(node))
        if idx, do: {:type_pos, node["type"], idx}
      end
    ]

    {matched, added, removed} = DiffHelpers.match_by_keys(old_nodes, new_nodes, key_fns)

    {old_parent_tokens, new_parent_tokens} = parent_identity_tokens(matched)

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        node_differs?(old, new, old_parent_tokens, new_parent_tokens)
      end)

    # Build old_index → new_index mapping from matched node pairs
    # so connections can be compared by semantic identity, not positional index
    old_node_index = old_nodes |> Enum.with_index() |> Map.new()
    new_node_index = new_nodes |> Enum.with_index() |> Map.new()

    old_index_to_new =
      Enum.reduce(matched, %{}, fn {old_node, new_node}, acc ->
        old_idx = Map.get(old_node_index, old_node)
        new_idx = Map.get(new_node_index, new_node)
        if old_idx && new_idx, do: Map.put(acc, old_idx, new_idx), else: acc
      end)

    changes
    |> append_node_change_list(added, :added)
    |> append_node_change_list(removed, :removed)
    |> append_node_change_list_modified(modified)
    |> diff_connections(old_conns, new_conns, old_index_to_new)
  end

  defp parent_identity_tokens(matched) do
    matched
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}}, fn {{old_node, new_node}, token}, {old_tokens, new_tokens} ->
      {
        maybe_put_parent_token(old_tokens, old_node["original_id"], token),
        maybe_put_parent_token(new_tokens, new_node["original_id"], token)
      }
    end)
  end

  defp maybe_put_parent_token(tokens, nil, _token), do: tokens
  defp maybe_put_parent_token(tokens, node_id, token), do: Map.put(tokens, node_id, token)

  defp node_differs?(old, new, old_parent_tokens, new_parent_tokens) do
    old_cleaned = normalize_node_for_diff(old, old_parent_tokens)
    new_cleaned = normalize_node_for_diff(new, new_parent_tokens)
    old_cleaned != new_cleaned
  end

  defp normalize_node_for_diff(node, parent_tokens) do
    node
    |> Map.drop(@node_ignore_fields)
    |> Map.update("parent_id", nil, &Map.get(parent_tokens, &1, {:unmatched_parent, &1}))
  end

  defp append_node_change_list(changes, [], _action), do: changes

  defp append_node_change_list(changes, nodes, action) do
    Enum.reduce(nodes, changes, fn node, acc ->
      type = node["type"] || "unknown"

      detail =
        case action do
          :added -> dgettext("flows", "Added %{type} node", type: type)
          :removed -> dgettext("flows", "Removed %{type} node", type: type)
        end

      [%{category: :node, action: action, detail: detail} | acc]
    end)
  end

  defp append_node_change_list_modified(changes, []), do: changes

  defp append_node_change_list_modified(changes, modified_pairs) do
    Enum.reduce(modified_pairs, changes, fn {_old, new}, acc ->
      type = new["type"] || "unknown"
      detail = dgettext("flows", "Modified %{type} node", type: type)
      [%{category: :node, action: :modified, detail: detail} | acc]
    end)
  end

  defp diff_connections(changes, old_conns, new_conns, old_index_to_new) do
    # Remap old connection indexes to new coordinate space so that
    # node position-only moves don't appear as connection changes.
    # Connections referencing removed nodes get unique sentinel indexes
    # so they won't falsely match new connections at the same raw index.
    remapped_old_conns =
      old_conns
      |> Enum.with_index()
      |> Enum.map(fn {conn, idx} ->
        new_src = Map.get(old_index_to_new, conn["source_node_index"])
        new_tgt = Map.get(old_index_to_new, conn["target_node_index"])

        if new_src && new_tgt do
          conn
          |> Map.put("source_node_index", new_src)
          |> Map.put("target_node_index", new_tgt)
        else
          # Node was removed — use unique sentinel to ensure this appears as removed
          conn
          |> Map.put("source_node_index", {:removed, idx})
          |> Map.put("target_node_index", {:removed, idx})
        end
      end)

    key_fn = fn conn ->
      {conn["source_node_index"], conn["target_node_index"], conn["source_pin"], conn["target_pin"]}
    end

    {matched, added, removed} = DiffHelpers.match_by_keys(remapped_old_conns, new_conns, [key_fn])

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, ["label"])
      end)

    changes
    |> append_conn_changes(added, :added)
    |> append_conn_changes(removed, :removed)
    |> append_conn_changes_modified(modified)
  end

  defp append_conn_changes(changes, [], _action), do: changes

  defp append_conn_changes(changes, conns, action) do
    Enum.reduce(conns, changes, fn _conn, acc ->
      detail =
        case action do
          :added -> dgettext("flows", "Added connection")
          :removed -> dgettext("flows", "Removed connection")
        end

      [%{category: :connection, action: action, detail: detail} | acc]
    end)
  end

  defp append_conn_changes_modified(changes, []), do: changes

  defp append_conn_changes_modified(changes, modified_pairs) do
    Enum.reduce(modified_pairs, changes, fn _pair, acc ->
      [
        %{
          category: :connection,
          action: :modified,
          detail: dgettext("flows", "Modified connection")
        }
        | acc
      ]
    end)
  end

  # ========== Scan References ==========

  @impl true
  def scan_references(snapshot) do
    refs = []

    refs =
      maybe_add_ref(refs, :scene, snapshot["scene_id"], dgettext("flows", "Flow backdrop scene"))

    refs =
      (snapshot["nodes"] || [])
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {node, idx}, acc ->
        data = node["data"] || %{}
        type = node["type"] || "unknown"

        acc =
          acc
          |> maybe_add_ref(
            :sheet,
            data["speaker_sheet_id"],
            dgettext("flows", "Node #%{n} (%{type}) — speaker", n: idx, type: type)
          )
          |> maybe_add_ref(
            :flow,
            data["referenced_flow_id"],
            dgettext("flows", "Node #%{n} (%{type}) — referenced flow", n: idx, type: type)
          )
          |> maybe_add_ref(
            :asset,
            data["audio_asset_id"],
            dgettext("flows", "Node #%{n} (%{type}) — audio", n: idx, type: type)
          )

        add_sequence_asset_refs(acc, node, idx)
      end)

    add_localization_asset_refs(refs, snapshot)
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]

  defp add_sequence_asset_refs(refs, node, node_index) do
    refs =
      node
      |> snapshot_collection("sequence_tracks")
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {track, track_index}, acc ->
        if is_map(track) do
          maybe_add_ref(
            acc,
            :asset,
            track["asset_id"],
            dgettext("flows", "Node #%{n} sequence track #%{track} — audio",
              n: node_index,
              track: track_index
            )
          )
        else
          acc
        end
      end)

    node
    |> snapshot_collection("sequence_visual_layers")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {layer, layer_index}, acc ->
      if is_map(layer) do
        maybe_add_ref(
          acc,
          :asset,
          layer["asset_id"],
          dgettext("flows", "Node #%{n} sequence visual layer #%{layer}",
            n: node_index,
            layer: layer_index
          )
        )
      else
        acc
      end
    end)
  end

  defp add_localization_asset_refs(refs, snapshot) do
    snapshot
    |> snapshot_collection("localization")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{} = row, index}, acc ->
        maybe_add_ref(
          acc,
          :asset,
          row["vo_asset_id"],
          dgettext("flows", "Localization row #%{n} — voice-over", n: index)
        )

      {_row, _index}, acc ->
        acc
    end)
  end

  defp snapshot_collection(snapshot, key) when is_map(snapshot) do
    case Map.get(snapshot, key, []) do
      collection when is_list(collection) -> collection
      _malformed -> []
    end
  end

  defp snapshot_collection(_snapshot, _key), do: []

  # Identity key for a snapshot node used by the positional fallback matcher.
  # Uses type + spatial position as a lightweight fingerprint.
  defp node_identity(node) do
    {node["type"], node["position_x"], node["position_y"]}
  end

  # Builds an identity → list-index map for a list of snapshot nodes.
  defp node_position_map(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, idx}, acc ->
      Map.put_new(acc, node_identity(node), idx)
    end)
  end
end

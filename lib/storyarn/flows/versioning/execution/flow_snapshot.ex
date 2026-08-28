defmodule Storyarn.Flows.Versioning.FlowSnapshot do
  @moduledoc """
  Flow-owned snapshot builder and in-place restorer.

  Snapshots retain Flow graph identity, sequence resources, translations, and
  the metadata required by the history viewer. Foreign entities are consumed
  through Flow-owned records over the current shared schema.

  Entity restore preserves the current Flow and child identities and returns
  only `{:ok, %Flow{}}`. Cross-project `external_id_maps` and reconstitution
  `id_maps` belong exclusively to the Projects snapshot codec.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.Versioning.AssetCatalog
  alias Storyarn.Flows.Versioning.Entities.AssetRecord
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.FlowSnapshotDiff
  alias Storyarn.Flows.Versioning.FlowSnapshotValidator
  alias Storyarn.Flows.Versioning.LocalizationCodec
  alias Storyarn.Flows.Versioning.Projections.LocalizedTextRecord
  alias Storyarn.Flows.Versioning.Projections.SheetAvatarRecord
  alias Storyarn.Flows.Versioning.Projections.SheetRecord
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Flows.Versioning.SourceContract
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @flow_fields ~w(name shortcut description is_main settings scene_id)

  @doc "Builds a deterministic snapshot from current persisted Flow state."
  @spec build(Flow.t()) :: map()
  def build(%Flow{id: flow_id, project_id: project_id}) when is_integer(flow_id) and is_integer(project_id) do
    case Repo.transaction(
           fn -> build_transaction(flow_id, project_id) end,
           isolation: :repeatable_read
         ) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> raise ArgumentError, "cannot build Flow snapshot: #{inspect(reason)}"
    end
  end

  @doc false
  def build_snapshot(%Flow{} = flow), do: build(flow)

  defp build_transaction(flow_id, project_id) do
    with {:ok, _project} <- References.lock_active_project(project_id),
         {:ok, flow} <- lock_flow(flow_id, project_id),
         :ok <- lock_localization_inventory(project_id),
         {:ok, snapshot} <- build_locked(flow) do
      snapshot
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Restores a snapshot under Flow and safety-version locks."
  @spec restore(Flow.t(), map(), keyword()) :: {:ok, Flow.t()} | {:error, term()}
  def restore(flow, snapshot, opts \\ [])

  def restore(%Flow{} = flow, snapshot, opts) when is_map(snapshot) do
    with :ok <- RestorePolicy.ensure_enabled(Keyword.get(opts, :restore_action)),
         :ok <- validate(snapshot, flow.id) do
      flow
      |> restore_with_main_retry(snapshot, opts)
      |> finalize_restore(opts)
    end
  end

  def restore(%Flow{}, snapshot, _opts), do: {:error, {:invalid_flow_snapshot, snapshot}}

  defp restore_with_main_retry(flow, snapshot, opts) do
    AssetCatalog.with_snapshot_asset_restore_scope(flow.project_id, fn asset_scope ->
      restore_with_main_retry(flow, snapshot, opts, asset_scope)
    end)
  end

  defp restore_with_main_retry(flow, snapshot, opts, asset_scope) do
    result =
      AssetCatalog.run_snapshot_asset_restore_transaction(
        asset_scope,
        flow.project_id,
        fn ^asset_scope ->
          {:ok,
           restore_transaction(
             flow,
             snapshot,
             Keyword.put(opts, :snapshot_asset_scope, asset_scope)
           )}
        end
      )

    if main_constraint_error?(result) and
         not Keyword.get(opts, :__force_non_main_on_conflict, false) do
      restore_with_main_retry(
        flow,
        snapshot,
        Keyword.put(opts, :__force_non_main_on_conflict, true),
        asset_scope
      )
    else
      result
    end
  end

  defp finalize_restore({:ok, %Flow{} = flow}, opts) do
    run_post_commit_restore_hook(opts)

    active_nodes = from(node in FlowNode, where: is_nil(node.deleted_at))

    restored =
      Repo.preload(
        flow,
        [
          :connections,
          nodes: {active_nodes, [:sequence_config, :sequence_tracks, :sequence_visual_layers]}
        ],
        force: true
      )

    {:ok, restored}
  end

  defp finalize_restore({:error, _reason} = error, _opts), do: error

  defp main_constraint_error?({:error, %Changeset{} = changeset}), do: main_constraint_error?(changeset)

  defp main_constraint_error?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
      metadata[:constraint] == :unique and
        to_string(metadata[:constraint_name]) == "flows_project_id_is_main_index"
    end)
  end

  defp main_constraint_error?(_result), do: false

  defp run_post_commit_restore_hook(opts) do
    case Keyword.get(opts, :__post_commit_restore_hook) do
      hook when is_function(hook, 0) -> hook.()
      _hook -> :ok
    end
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
  def restore_snapshot(%Flow{} = flow, snapshot, opts \\ []), do: restore(flow, snapshot, opts)

  @doc false
  def diff_snapshots(old_snapshot, new_snapshot), do: diff(old_snapshot, new_snapshot)

  @doc "Returns structured changes used by version history summaries."
  @spec diff(map(), map()) :: [map()]
  def diff(old_snapshot, new_snapshot) when is_map(old_snapshot) and is_map(new_snapshot) do
    FlowSnapshotDiff.diff(old_snapshot, new_snapshot)
  end

  @doc "Extracts every external reference needed by restore conflict preview."
  @spec scan_references(map()) :: [map()]
  defdelegate scan_references(snapshot), to: Storyarn.Flows.Versioning.Execution.ReferenceScanner, as: :scan

  defp lock_flow(flow_id, project_id) do
    case Repo.one(from(flow in Flow, where: flow.id == ^flow_id, lock: "FOR UPDATE")) do
      %Flow{project_id: ^project_id, deleted_at: nil} = flow -> {:ok, flow}
      %Flow{project_id: ^project_id} -> {:error, :flow_not_active}
      %Flow{} -> {:error, :flow_scope_mismatch}
      nil -> {:error, :flow_not_found}
    end
  end

  defp lock_localization_inventory(project_id) do
    Localization.lock_inventory!(project_id)
  end

  defp build_locked(flow) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.flow_id == ^flow.id and is_nil(node.deleted_at),
          order_by: [asc: node.position_x, asc: node.position_y, asc: node.type, asc: node.id],
          preload: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
        )
      )

    with {:ok, normalized_nodes} <-
           validate_and_normalize_node_references(nodes, flow.project_id, flow.scene_id),
         :ok <- References.validate_flow_node_variable_targets(normalized_nodes, flow.project_id),
         :ok <- validate_flow_reference_cycles(flow.id, normalized_nodes),
         target_locales = LocalizationCodec.active_target_locales(flow.project_id),
         localization = capture_localization(normalized_nodes, flow.project_id, target_locales),
         :ok <- validate_localization_references(localization, flow.project_id),
         {:ok, connections} <- active_connections(flow.id, normalized_nodes),
         :ok <- validate_dynamic_pins(connections, normalized_nodes),
         localization = complete_snapshot_localization(localization, normalized_nodes, target_locales),
         {:ok, {asset_blob_hashes, asset_metadata}} <-
           capture_asset_catalog(normalized_nodes, localization, flow.project_id) do
      id_to_index =
        normalized_nodes
        |> Enum.with_index()
        |> Map.new(fn {node, index} -> {node.id, index} end)

      node_snapshots = Enum.map(normalized_nodes, &node_snapshot/1)

      snapshot = %{
        "original_id" => flow.id,
        "name" => flow.name,
        "shortcut" => flow.shortcut,
        "description" => flow.description,
        "is_main" => flow.is_main,
        "settings" => flow.settings,
        "scene_id" => flow.scene_id,
        "nodes" => node_snapshots,
        "connections" => Enum.map(connections, &connection_snapshot(&1, id_to_index)),
        "referenced_sheets" => referenced_sheets(normalized_nodes, flow.project_id),
        "asset_blob_hashes" => asset_blob_hashes,
        "asset_metadata" => asset_metadata,
        "localization" => localization,
        "localization_manifest" => LocalizationCodec.manifest(localization, target_locales)
      }

      with :ok <- FlowSnapshotValidator.validate(snapshot, flow.id), do: {:ok, snapshot}
    end
  end

  defp validate_and_normalize_node_references(nodes, project_id, scene_id) do
    direct_specs =
      Enum.flat_map(nodes, fn node ->
        data = node.data || %{}

        [
          {:sheet, {:flow_node, node.id, "speaker_sheet_id"}, data["speaker_sheet_id"]},
          {:sheet, {:flow_node, node.id, "location_sheet_id"}, data["location_sheet_id"]},
          {:flow, {:flow_node, node.id, "referenced_flow_id"}, data["referenced_flow_id"]}
        ] ++ exit_target_specs(node) ++ mention_specs(node)
      end)

    # Keeping every external reference in one ordered lock prevents concurrent
    # trashing between validation and snapshot capture.
    specs = [{:scene, {:flow, "scene_id"}, scene_id} | direct_specs]

    with {:ok, _ids} <- References.lock_active_references(project_id, specs) do
      normalize_avatar_references(nodes, project_id)
    end
  end

  defp normalize_avatar_references(nodes, project_id) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, normalized} ->
      case References.lock_and_normalize_node_avatar_for_project(
             project_id,
             node.type,
             node.data || %{}
           ) do
        {:ok, data} ->
          data = normalize_direct_reference_fields(data)
          {:cont, {:ok, [%{node | data: data} | normalized]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp exit_target_specs(%FlowNode{type: "exit", id: id, data: data}) when is_map(data) do
    case {data["target_type"], data["target_id"]} do
      {"flow", target_id} -> [{:flow, {:flow_node, id, "target_id"}, target_id}]
      {"scene", target_id} -> [{:scene, {:flow_node, id, "target_id"}, target_id}]
      {nil, nil} -> []
      {"", nil} -> []
      invalid -> [{:invalid, {:flow_node, id, "target"}, invalid}]
    end
  end

  defp exit_target_specs(_node), do: []

  defp mention_specs(%FlowNode{id: id, data: data}) do
    data
    |> References.rich_text_html_candidates()
    |> Enum.reduce_while({:ok, []}, fn html, {:ok, specs} ->
      accumulate_mention_specs(html, id, specs)
    end)
    |> case do
      {:ok, specs} -> specs
      {:error, reason} -> [{:invalid, {:flow_node, id, "mention"}, reason}]
    end
  end

  defp accumulate_mention_specs(html, node_id, specs) do
    case References.extract_rich_text_mentions(html) do
      {:ok, mentions} -> {:cont, {:ok, Enum.map(mentions, &mention_spec(&1, node_id)) ++ specs}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp mention_spec(%{type: "sheet", id: id}, node_id), do: {:sheet, {:flow_node, node_id, "mention"}, id}

  defp mention_spec(%{type: "flow", id: id}, node_id), do: {:flow, {:flow_node, node_id, "mention"}, id}

  defp active_connections(flow_id, nodes) do
    connections =
      Repo.all(
        from(connection in FlowConnection,
          where: connection.flow_id == ^flow_id,
          order_by: [
            asc: connection.source_node_id,
            asc: connection.source_pin,
            asc: connection.target_node_id,
            asc: connection.target_pin,
            asc: connection.id
          ],
          lock: "FOR SHARE"
        )
      )

    endpoint_ids =
      connections
      |> Enum.flat_map(&[&1.source_node_id, &1.target_node_id])
      |> Enum.uniq()

    endpoints =
      from(node in FlowNode,
        where: node.id in ^endpoint_ids,
        select: {node.id, node.flow_id, node.deleted_at}
      )
      |> Repo.all()
      |> Map.new(fn {id, owner_flow_id, deleted_at} ->
        {id, %{flow_id: owner_flow_id, deleted_at: deleted_at}}
      end)

    case Enum.find(connections, fn connection ->
           invalid_endpoint_owner?(endpoints[connection.source_node_id], flow_id) or
             invalid_endpoint_owner?(endpoints[connection.target_node_id], flow_id)
         end) do
      nil ->
        active_ids = MapSet.new(nodes, & &1.id)

        {:ok,
         Enum.filter(connections, fn connection ->
           MapSet.member?(active_ids, connection.source_node_id) and
             MapSet.member?(active_ids, connection.target_node_id)
         end)}

      connection ->
        {:error, {:connection_outside_flow, connection.id}}
    end
  end

  defp invalid_endpoint_owner?(%{flow_id: flow_id}, flow_id), do: false
  defp invalid_endpoint_owner?(_endpoint, _flow_id), do: true

  defp validate_dynamic_pins(connections, nodes) do
    nodes_by_id = Map.new(nodes, &{&1.id, &1})

    with {:ok, dynamic_pins} <-
           Enum.reduce_while(connections, {:ok, []}, fn connection, {:ok, pins} ->
             source = Map.fetch!(nodes_by_id, connection.source_node_id)
             connection |> build_dynamic_exit_pin(source) |> accumulate_dynamic_pin(pins)
           end) do
      validate_materializable_dynamic_pins(dynamic_pins, lock_dynamic_exits(dynamic_pins))
    end
  end

  defp accumulate_dynamic_pin({:ok, nil}, pins), do: {:cont, {:ok, pins}}
  defp accumulate_dynamic_pin({:ok, pin}, pins), do: {:cont, {:ok, [pin | pins]}}
  defp accumulate_dynamic_pin({:error, reason}, _pins), do: {:halt, {:error, reason}}

  defp lock_dynamic_exits(dynamic_pins) do
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
  end

  defp validate_materializable_dynamic_pins(dynamic_pins, locked_exits) do
    Enum.reduce_while(dynamic_pins, :ok, fn pin, :ok ->
      validate_materializable_dynamic_pin(pin, Map.get(locked_exits, pin.exit_id))
    end)
  end

  defp validate_materializable_dynamic_pin(pin, locked_exit) do
    case dynamic_exit_pin_state(locked_exit, pin.referenced_flow_id) do
      :ok ->
        {:cont, :ok}

      reason ->
        {:halt, {:error, {:dynamic_exit_pin_not_materializable, pin.connection_id, pin.source_pin, reason}}}
    end
  end

  defp build_dynamic_exit_pin(%FlowConnection{} = connection, %FlowNode{type: "subflow"} = source) do
    case parse_dynamic_exit_pin(connection.source_pin) do
      :not_dynamic ->
        {:ok, nil}

      {:ok, exit_id} ->
        case normalize_id_value((source.data || %{})["referenced_flow_id"]) do
          referenced_flow_id when is_integer(referenced_flow_id) ->
            {:ok,
             %{
               connection_id: connection.id,
               source_pin: connection.source_pin,
               exit_id: exit_id,
               referenced_flow_id: referenced_flow_id
             }}

          _invalid ->
            {:error,
             {:dynamic_exit_pin_not_materializable, connection.id, connection.source_pin, :missing_referenced_flow}}
        end

      {:error, reason} ->
        {:error, {:dynamic_exit_pin_not_materializable, connection.id, connection.source_pin, reason}}
    end
  end

  defp build_dynamic_exit_pin(_connection, _source), do: {:ok, nil}

  defp dynamic_exit_pin_state(nil, _referenced_flow_id), do: :exit_not_found

  defp dynamic_exit_pin_state(%{deleted_at: deleted_at}, _referenced_flow_id) when not is_nil(deleted_at),
    do: :exit_in_trash

  defp dynamic_exit_pin_state(%{type: type}, _referenced_flow_id) when type != "exit", do: :referenced_node_not_exit

  defp dynamic_exit_pin_state(%{flow_id: flow_id}, referenced_flow_id) when flow_id != referenced_flow_id,
    do: :exit_not_in_referenced_flow

  defp dynamic_exit_pin_state(_exit, _referenced_flow_id), do: :ok

  defp normalize_direct_reference_fields(data) do
    data =
      Enum.reduce(
        ~w(speaker_sheet_id location_sheet_id referenced_flow_id audio_asset_id),
        data,
        fn field, normalized ->
          case Map.fetch(normalized, field) do
            {:ok, value} -> Map.put(normalized, field, normalize_id_value(value))
            :error -> normalized
          end
        end
      )

    if data["target_type"] in ["flow", "scene"] and Map.has_key?(data, "target_id"),
      do: Map.update!(data, "target_id", &normalize_id_value/1),
      else: data
  end

  defp capture_asset_catalog(nodes, localization, project_id) do
    asset_ids =
      Enum.flat_map(nodes, fn node ->
        [(node.data || %{})["audio_asset_id"]] ++
          Enum.map(sequence_tracks(node), & &1.asset_id) ++
          Enum.map(sequence_layers(node), & &1.asset_id)
      end) ++ Enum.map(localization, & &1["vo_asset_id"])

    AssetCatalog.capture_snapshot_asset_catalog(project_id, asset_ids)
  end

  defp capture_localization(nodes, project_id, target_locales) do
    LocalizationCodec.capture(
      project_id,
      %{"flow_node" => Enum.map(nodes, & &1.id)},
      target_locales: target_locales
    )
  end

  defp validate_localization_references(rows, project_id) do
    specs =
      Enum.flat_map(rows, fn row ->
        [
          {:asset, {:localized_text, row["source_id"], "vo_asset_id"}, row["vo_asset_id"]},
          {:sheet, {:localized_text, row["source_id"], "speaker_sheet_id"}, row["speaker_sheet_id"]}
        ]
      end)

    case References.lock_active_references(project_id, specs) do
      {:ok, _ids} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp complete_snapshot_localization(localization, nodes, target_locales) do
    nodes
    |> Enum.map(&node_snapshot/1)
    |> snapshot_localization_sources()
    |> pending_localization_sources()
    |> then(&LocalizationCodec.complete_pending_rows(localization, &1, target_locales))
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
    |> maybe_add_localization_source(node_id, "stage_directions", data["stage_directions"], nil)
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
      [
        {{node_id, field},
         %{
           text: text,
           speaker_sheet_id: speaker_sheet_id,
           metadata: SourceContract.field_metadata("flow_node", field)
         }}
        | sources
      ]
    end
  end

  defp maybe_add_localization_source(sources, _node_id, _field, _text, _speaker_sheet_id), do: sources

  defp node_snapshot(node) do
    base = %{
      "original_id" => node.id,
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "data" => node.data,
      "parent_id" => node.parent_id
    }

    if node.type == "sequence" do
      Map.merge(base, %{
        "sequence_config" => sequence_config_snapshot(node.sequence_config),
        "sequence_tracks" =>
          node |> sequence_tracks() |> Enum.sort_by(&{&1.kind, &1.position, &1.id}) |> Enum.map(&track_snapshot/1),
        "sequence_visual_layers" =>
          node |> sequence_layers() |> Enum.sort_by(&{&1.z_index, &1.id}) |> Enum.map(&layer_snapshot/1)
      })
    else
      base
    end
  end

  defp sequence_config_snapshot(%SequenceConfig{} = config) do
    %{"name" => config.name, "width" => config.width, "height" => config.height}
  end

  defp sequence_config_snapshot(_config), do: nil

  defp track_snapshot(track) do
    %{
      "original_id" => track.id,
      "kind" => track.kind,
      "position" => track.position,
      "asset_id" => track.asset_id,
      "start_time" => decimal_string(track.start_time),
      "end_time" => decimal_string(track.end_time),
      "volume" => decimal_string(track.volume)
    }
  end

  defp layer_snapshot(layer) do
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

  defp connection_snapshot(connection, id_to_index) do
    %{
      "original_id" => connection.id,
      "source_node_index" => Map.fetch!(id_to_index, connection.source_node_id),
      "target_node_index" => Map.fetch!(id_to_index, connection.target_node_id),
      "source_pin" => connection.source_pin,
      "target_pin" => connection.target_pin,
      "label" => connection.label
    }
  end

  defp sequence_tracks(%FlowNode{sequence_tracks: tracks}) when is_list(tracks), do: tracks
  defp sequence_tracks(_node), do: []
  defp sequence_layers(%FlowNode{sequence_visual_layers: layers}) when is_list(layers), do: layers
  defp sequence_layers(_node), do: []
  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp referenced_sheets(nodes, project_id) do
    ids =
      nodes
      |> Enum.flat_map(fn node ->
        data = node.data || %{}
        [normalize_id_value(data["speaker_sheet_id"]), normalize_id_value(data["location_sheet_id"])]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    sheets =
      Repo.all(
        from(sheet in SheetRecord,
          where:
            sheet.project_id == ^project_id and sheet.id in ^ids and
              is_nil(sheet.deleted_at),
          order_by: [asc: sheet.id]
        )
      )

    default_avatar_asset_ids = default_avatar_asset_ids(Enum.map(sheets, & &1.id))

    asset_ids =
      sheets
      |> Enum.map(& &1.banner_asset_id)
      |> Kernel.++(Map.values(default_avatar_asset_ids))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assets_by_id =
      from(asset in AssetRecord,
        where:
          asset.project_id == ^project_id and asset.id in ^asset_ids and
            is_nil(asset.deleted_at)
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Map.new(sheets, fn sheet ->
      {to_string(sheet.id),
       %{
         "id" => sheet.id,
         "name" => sheet.name,
         "shortcut" => sheet.shortcut,
         "color" => sheet.color,
         "avatar_url" => asset_url(assets_by_id[default_avatar_asset_ids[sheet.id]]),
         "banner_url" => asset_url(assets_by_id[sheet.banner_asset_id])
       }}
    end)
  end

  defp default_avatar_asset_ids([]), do: %{}

  defp default_avatar_asset_ids(sheet_ids) do
    from(avatar in SheetAvatarRecord,
      where: avatar.sheet_id in ^sheet_ids,
      order_by: [asc: avatar.sheet_id, desc: avatar.is_default, asc: avatar.position, asc: avatar.id],
      select: {avatar.sheet_id, avatar.asset_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {sheet_id, asset_id}, defaults ->
      Map.put_new(defaults, sheet_id, asset_id)
    end)
  end

  defp asset_url(%AssetRecord{metadata: %{"web_url" => url}}) when is_binary(url), do: url
  defp asset_url(%AssetRecord{url: url}) when is_binary(url), do: url
  defp asset_url(_asset), do: nil

  defp restore_transaction(flow, snapshot, opts) do
    with {:ok, _project} <- References.lock_active_project(flow.project_id, :update),
         {:ok, locked_flow} <- lock_flow(flow.id, flow.project_id),
         {:ok, _version} <- lock_safety_version(locked_flow, opts),
         {:ok, _incoming_pins} <-
           lock_and_validate_incoming_dynamic_pins(
             locked_flow.project_id,
             locked_flow.id,
             snapshot["nodes"]
           ),
         {:ok, _scope} <- lock_restore_scope(locked_flow.id),
         :ok <- lock_localization_inventory(locked_flow.project_id),
         :ok <- verify_pre_restore_baseline(locked_flow, opts),
         {:ok, normalized_snapshot} <- validate_restore_references(snapshot, locked_flow),
         {:ok, restored} <- apply_snapshot(locked_flow, normalized_snapshot, opts) do
      restored
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_and_validate_incoming_dynamic_pins(project_id, restored_flow_id, snapshot_nodes) do
    project_flow_ids =
      Repo.all(
        from(flow in Flow,
          where: flow.project_id == ^project_id,
          order_by: [asc: flow.id],
          select: flow.id
        )
      )

    locked_nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.flow_id in ^project_flow_ids,
          order_by: [asc: node.id],
          lock: "FOR UPDATE",
          select: %{id: node.id, type: node.type, flow_id: node.flow_id, data: node.data}
        )
      )

    source_nodes = Enum.filter(locked_nodes, &(&1.type == "subflow"))
    source_node_ids = Enum.map(source_nodes, & &1.id)

    connections =
      Repo.all(
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

    with :ok <- validate_project_connection_ownership(connections, nodes_by_id, MapSet.new(project_flow_ids)),
         :ok <-
           validate_incoming_dynamic_connections(
             connections,
             source_nodes_by_id,
             restored_flow_id,
             target_exit_ids
           ) do
      {:ok, %{source_nodes: source_node_ids, connections: Enum.map(connections, & &1.id)}}
    end
  end

  defp validate_project_connection_ownership(connections, nodes_by_id, project_flow_ids) do
    case Enum.find(connections, fn connection ->
           source_node = Map.get(nodes_by_id, connection.source_node_id)
           target_node = Map.get(nodes_by_id, connection.target_node_id)

           is_nil(source_node) or is_nil(target_node) or
             not MapSet.member?(project_flow_ids, connection.flow_id) or
             source_node.flow_id != connection.flow_id or target_node.flow_id != connection.flow_id
         end) do
      nil ->
        :ok

      connection ->
        {:error,
         {:incoming_dynamic_connection_ownership_conflict,
          {connection.id, connection.flow_id, connection.source_node_id, connection.target_node_id}}}
    end
  end

  defp validate_incoming_dynamic_connections(connections, source_nodes_by_id, restored_flow_id, target_exit_ids) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      validate_incoming_dynamic_connection(
        connection,
        Map.fetch!(source_nodes_by_id, connection.source_node_id),
        restored_flow_id,
        target_exit_ids
      )
    end)
  end

  defp validate_incoming_dynamic_connection(connection, source_node, restored_flow_id, target_exit_ids) do
    if normalize_id_value(source_node.data["referenced_flow_id"]) == restored_flow_id do
      connection.source_pin
      |> validate_incoming_dynamic_pin(target_exit_ids)
      |> incoming_dynamic_pin_step(connection, restored_flow_id)
    else
      {:cont, :ok}
    end
  end

  defp incoming_dynamic_pin_step(:ok, _connection, _restored_flow_id), do: {:cont, :ok}

  defp incoming_dynamic_pin_step({:error, reason}, connection, restored_flow_id) do
    {:halt,
     {:error, {:incoming_dynamic_exit_pin_would_break, connection.id, connection.source_pin, restored_flow_id, reason}}}
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

  defp parse_dynamic_exit_pin("exit_" <> exit_id_text) do
    case Integer.parse(exit_id_text) do
      {exit_id, ""} when exit_id > 0 -> {:ok, exit_id}
      _invalid -> {:error, :invalid_exit_node_id}
    end
  end

  defp parse_dynamic_exit_pin(_pin), do: :not_dynamic

  defp lock_restore_scope(flow_id) do
    node_ids =
      Repo.all(
        from(node in FlowNode,
          where: node.flow_id == ^flow_id,
          order_by: [asc: node.id],
          lock: "FOR UPDATE",
          select: node.id
        )
      )

    connection_ids =
      Repo.all(
        from(connection in FlowConnection,
          where: connection.flow_id == ^flow_id,
          order_by: [asc: connection.id],
          lock: "FOR UPDATE",
          select: connection.id
        )
      )

    config_ids =
      Repo.all(
        from(config in SequenceConfig,
          where: config.flow_node_id in ^node_ids,
          order_by: [asc: config.flow_node_id],
          lock: "FOR UPDATE",
          select: config.flow_node_id
        )
      )

    track_ids =
      Repo.all(
        from(track in SequenceTrack,
          where: track.flow_node_id in ^node_ids,
          order_by: [asc: track.id],
          lock: "FOR UPDATE",
          select: track.id
        )
      )

    layer_ids =
      Repo.all(
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
       sequence_visual_layers: layer_ids
     }}
  end

  defp lock_safety_version(flow, opts) do
    case Keyword.fetch(opts, :pre_restore_version_identity) do
      {:ok, identity} ->
        lock_safety_version_identity(flow, Keyword.get(opts, :user_id), identity)

      :error ->
        {:ok, :not_required}
    end
  end

  defp lock_safety_version_identity(flow, user_id, identity) do
    with :ok <- validate_safety_version_identity(flow, user_id, identity) do
      version =
        Repo.one(
          from(candidate in EntityVersionRecord,
            where:
              candidate.id == ^identity.id and candidate.entity_type == "flow" and
                candidate.entity_id == ^flow.id and candidate.project_id == ^flow.project_id,
            lock: "FOR SHARE"
          )
        )

      cond do
        is_nil(version) -> {:error, :pre_restore_version_not_durable}
        version_identity(version) != identity -> {:error, :pre_restore_version_identity_mismatch}
        true -> {:ok, version}
      end
    end
  end

  defp validate_safety_version_identity(flow, user_id, %{
         id: version_id,
         entity_type: "flow",
         entity_id: entity_id,
         project_id: project_id,
         created_by_id: identity_user_id,
         version_number: version_number,
         storage_key: storage_key,
         snapshot_size_bytes: snapshot_size_bytes,
         checksum: checksum
       }) do
    valid? =
      Enum.all?([
        entity_id == flow.id,
        project_id == flow.project_id,
        identity_user_id == user_id,
        positive_id?(version_id),
        positive_id?(version_number),
        is_binary(storage_key),
        is_integer(snapshot_size_bytes) and snapshot_size_bytes >= 0,
        is_binary(checksum)
      ])

    if valid?, do: :ok, else: {:error, :invalid_pre_restore_version_identity}
  end

  defp validate_safety_version_identity(_flow, _user_id, _identity), do: {:error, :invalid_pre_restore_version_identity}

  defp version_identity(version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp verify_pre_restore_baseline(flow, opts) do
    case Keyword.fetch(opts, :pre_restore_snapshot) do
      {:ok, expected} when is_map(expected) ->
        compare_pre_restore_baseline(flow, expected)

      {:ok, _invalid} ->
        {:error, :invalid_pre_restore_snapshot}

      :error ->
        :ok
    end
  end

  defp compare_pre_restore_baseline(flow, expected) do
    with {:ok, current} <- build_locked(flow) do
      if normalize_json(current) == normalize_json(expected),
        do: :ok,
        else: {:error, :flow_changed_since_pre_restore_snapshot}
    end
  end

  defp validate_restore_references(snapshot, flow) do
    with {:ok, normalized_nodes} <- normalize_snapshot_jump_targets(snapshot["nodes"]) do
      validate_normalized_restore_references(Map.put(snapshot, "nodes", normalized_nodes), flow)
    end
  end

  defp validate_normalized_restore_references(snapshot, flow) do
    project_id = flow.project_id
    nodes = snapshot["nodes"]
    root_specs = [{:scene, {:flow, "scene_id"}, snapshot["scene_id"]}]

    node_specs =
      Enum.flat_map(nodes, fn node ->
        data = node["data"] || %{}

        [
          {:sheet, {:flow_node, node["original_id"], "speaker_sheet_id"}, data["speaker_sheet_id"]},
          {:sheet, {:flow_node, node["original_id"], "location_sheet_id"}, data["location_sheet_id"]},
          {:flow, {:flow_node, node["original_id"], "referenced_flow_id"}, data["referenced_flow_id"]}
        ] ++
          snapshot_exit_specs(node) ++ snapshot_mention_specs(node)
      end)

    localization_specs =
      Enum.flat_map(snapshot["localization"] || [], fn row ->
        [{:sheet, {:localized_text, row["source_id"], "speaker_sheet_id"}, row["speaker_sheet_id"]}]
      end)

    with {:ok, _ids} <-
           References.lock_active_references(
             project_id,
             root_specs ++ node_specs ++ localization_specs
           ),
         {:ok, normalized_nodes} <- normalize_snapshot_avatars(nodes, project_id) do
      with :ok <- References.validate_flow_node_variable_targets(normalized_nodes, project_id),
           :ok <- validate_flow_reference_cycles(flow.id, normalized_nodes),
           :ok <- validate_snapshot_dynamic_pins(snapshot["connections"], normalized_nodes) do
        {:ok, Map.put(snapshot, "nodes", normalized_nodes)}
      end
    end
  end

  defp normalize_snapshot_jump_targets(nodes) do
    with {:ok, hub_counts} <- validate_snapshot_hub_ids(nodes) do
      nodes
      |> Enum.reduce_while({:ok, []}, fn
        %{"type" => "jump", "data" => data} = node, {:ok, normalized_nodes} ->
          normalize_snapshot_jump_node(node, data, hub_counts, normalized_nodes)

        node, {:ok, normalized_nodes} ->
          {:cont, {:ok, [node | normalized_nodes]}}
      end)
      |> reverse_normalized_nodes()
    end
  end

  defp normalize_snapshot_jump_node(node, data, hub_counts, normalized_nodes) do
    case normalize_snapshot_jump_target(data, hub_counts) do
      {:ok, normalized_data} ->
        {:cont, {:ok, [Map.put(node, "data", normalized_data) | normalized_nodes]}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_snapshot_hub_ids(nodes) do
    nodes
    |> Enum.reduce_while({:ok, %{}}, fn
      %{"original_id" => node_id, "type" => "hub", "data" => data}, {:ok, counts}
      when is_map(data) ->
        hub_id = data["hub_id"]

        if is_binary(hub_id) and String.trim(hub_id) != "" do
          {:cont, {:ok, Map.update(counts, hub_id, 1, &(&1 + 1))}}
        else
          {:halt, {:error, {:invalid_snapshot_hub_id, node_id, hub_id}}}
        end

      _node, {:ok, counts} ->
        {:cont, {:ok, counts}}
    end)
    |> reject_duplicate_snapshot_hub_id()
  end

  defp reject_duplicate_snapshot_hub_id({:ok, hub_counts}) do
    case Enum.find(hub_counts, fn {_hub_id, count} -> count > 1 end) do
      {hub_id, _count} -> {:error, {:duplicate_snapshot_hub_id, hub_id}}
      nil -> {:ok, hub_counts}
    end
  end

  defp reject_duplicate_snapshot_hub_id({:error, _reason} = error), do: error

  defp normalize_snapshot_jump_target(%{} = data, hub_counts) do
    value = data["target_hub_id"]

    cond do
      value in [nil, ""] -> {:ok, data}
      not is_binary(value) -> {:error, {:invalid_jump_target, value}}
      String.trim(value) == "" -> {:ok, Map.put(data, "target_hub_id", "")}
      Map.get(hub_counts, value) == 1 -> {:ok, data}
      true -> {:error, {:invalid_jump_target, value}}
    end
  end

  defp reverse_normalized_nodes({:ok, nodes}), do: {:ok, Enum.reverse(nodes)}
  defp reverse_normalized_nodes({:error, _reason} = error), do: error

  defp snapshot_exit_specs(%{"type" => "exit", "original_id" => id, "data" => data}) when is_map(data) do
    case {data["target_type"], data["target_id"]} do
      {"flow", target_id} -> [{:flow, {:flow_node, id, "target_id"}, target_id}]
      {"scene", target_id} -> [{:scene, {:flow_node, id, "target_id"}, target_id}]
      {nil, nil} -> []
      {"", nil} -> []
      invalid -> [{:invalid, {:flow_node, id, "target"}, invalid}]
    end
  end

  defp snapshot_exit_specs(_node), do: []

  defp snapshot_mention_specs(node) do
    mention_specs(%FlowNode{id: node["original_id"], data: node["data"] || %{}})
  end

  defp normalize_snapshot_avatars(nodes, project_id) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case References.lock_and_normalize_node_avatar_for_project(
             project_id,
             node["type"],
             node["data"] || %{}
           ) do
        {:ok, data} ->
          data = normalize_direct_reference_fields(data)
          {:cont, {:ok, [Map.put(node, "data", data) | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _reason} = error -> error
    end
  end

  defp validate_flow_reference_cycles(flow_id, nodes) do
    references = Enum.flat_map(nodes, &flow_reference/1)

    circular_pairs =
      references
      |> Enum.map(fn {_node_id, target_flow_id} -> {flow_id, target_flow_id} end)
      |> Editor.circular_reference_pairs()

    case Enum.find(references, fn {_node_id, target_flow_id} ->
           MapSet.member?(circular_pairs, {flow_id, target_flow_id})
         end) do
      nil -> :ok
      {node_id, target_flow_id} -> {:error, {:circular_flow_reference, flow_id, node_id, target_flow_id}}
    end
  end

  defp flow_reference(%FlowNode{id: id, type: type, data: data}), do: flow_reference(id, type, data)

  defp flow_reference(%{"original_id" => id, "type" => type, "data" => data}), do: flow_reference(id, type, data)

  defp flow_reference(_node), do: []

  defp flow_reference(node_id, "subflow", %{"referenced_flow_id" => target_flow_id}),
    do: normalized_flow_reference(node_id, target_flow_id)

  defp flow_reference(node_id, "exit", %{"exit_mode" => "flow_reference", "referenced_flow_id" => target_flow_id}),
    do: normalized_flow_reference(node_id, target_flow_id)

  defp flow_reference(_node_id, _type, _data), do: []

  defp normalized_flow_reference(node_id, target_flow_id) do
    case normalize_id(target_flow_id) do
      {:ok, id} when is_integer(id) -> [{node_id, id}]
      _invalid -> []
    end
  end

  defp validate_snapshot_dynamic_pins(connections, nodes) do
    with {:ok, dynamic_pins} <-
           Enum.reduce_while(connections, {:ok, []}, fn connection, {:ok, pins} ->
             source = Enum.at(nodes, connection["source_node_index"])
             connection |> snapshot_dynamic_exit_pin(source) |> accumulate_dynamic_pin(pins)
           end) do
      validate_materializable_dynamic_pins(dynamic_pins, lock_dynamic_exits(dynamic_pins))
    end
  end

  defp snapshot_dynamic_exit_pin(%{"original_id" => connection_id, "source_pin" => source_pin}, %{
         "type" => "subflow",
         "data" => data
       }) do
    case parse_dynamic_exit_pin(source_pin) do
      :not_dynamic ->
        {:ok, nil}

      {:ok, exit_id} ->
        case normalize_id_value(data["referenced_flow_id"]) do
          referenced_flow_id when is_integer(referenced_flow_id) ->
            {:ok,
             %{
               connection_id: connection_id,
               source_pin: source_pin,
               exit_id: exit_id,
               referenced_flow_id: referenced_flow_id
             }}

          _invalid ->
            {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, :missing_referenced_flow}}
        end

      {:error, reason} ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, reason}}
    end
  end

  defp snapshot_dynamic_exit_pin(_connection, _source), do: {:ok, nil}

  defp apply_snapshot(flow, snapshot, opts) do
    nodes_data = snapshot["nodes"]
    target_node_ids = Enum.map(nodes_data, & &1["original_id"])
    snapshot_node_ids = MapSet.new(nodes_data, & &1["original_id"])
    current_nodes = Repo.all(from(node in FlowNode, where: node.flow_id == ^flow.id, lock: "FOR UPDATE"))

    with :ok <- validate_node_ownership(current_nodes, nodes_data, flow.id),
         :ok <-
           validate_graph_resource_ownership(
             current_nodes,
             nodes_data,
             snapshot["connections"],
             flow.id
           ),
         is_main = restorable_main_state(flow, snapshot["is_main"], opts),
         :ok <- run_before_main_write_hook(opts),
         {:ok, updated_flow} <- update_flow(flow, snapshot, is_main),
         {:ok, deleted_node_ids} <- soft_delete_absent_nodes(current_nodes, snapshot_node_ids),
         {:ok, _cleared} <- clear_target_node_state(flow.id, target_node_ids),
         {:ok, _swapped} <- prepare_target_dialogue_id_swaps(flow.id, target_node_ids),
         {:ok, restored_nodes} <-
           restore_nodes(flow.id, current_nodes, nodes_data, snapshot, flow.project_id, opts),
         :ok <- restore_node_parents(restored_nodes, nodes_data),
         {:ok, _resources} <-
           restore_sequence_resources(restored_nodes, nodes_data, snapshot, flow.project_id, opts),
         {:ok, _connections} <-
           restore_connections(flow.id, restored_nodes, nodes_data, snapshot["connections"]),
         :ok <- archive_restore_localization(flow, deleted_node_ids, target_node_ids),
         :ok <- restore_localization(flow, restored_nodes, nodes_data, snapshot, opts),
         :ok <- rebuild_references(deleted_node_ids, restored_nodes, flow.project_id) do
      {:ok, updated_flow}
    end
  end

  defp validate_node_ownership(current_nodes, nodes_data, flow_id) do
    snapshot_ids = Enum.map(nodes_data, & &1["original_id"])
    current_ids = MapSet.new(current_nodes, & &1.id)

    foreign =
      Repo.all(
        from(node in FlowNode,
          where: node.id in ^snapshot_ids and node.flow_id != ^flow_id,
          select: node.id,
          lock: "FOR SHARE"
        )
      )

    cond do
      foreign != [] -> {:error, {:snapshot_node_owned_by_other_flow, foreign}}
      Enum.any?(snapshot_ids, &(not is_integer(&1) or &1 <= 0)) -> {:error, :invalid_snapshot_node_id}
      MapSet.size(MapSet.new(snapshot_ids)) != length(snapshot_ids) -> {:error, :duplicate_snapshot_node_id}
      true -> validate_missing_snapshot_ids(snapshot_ids, current_ids)
    end
  end

  defp validate_missing_snapshot_ids(snapshot_ids, current_ids) do
    missing = Enum.reject(snapshot_ids, &MapSet.member?(current_ids, &1))

    if missing == [] or Enum.all?(missing, &available_primary_key?(FlowNode, &1)),
      do: :ok,
      else: {:error, :snapshot_node_id_conflict}
  end

  defp available_primary_key?(schema, id), do: is_nil(Repo.get(schema, id))

  defp validate_graph_resource_ownership(current_nodes, nodes_data, connections, flow_id) do
    target_node_ids = MapSet.new(nodes_data, & &1["original_id"])
    track_owners = snapshot_resource_owners(nodes_data, "sequence_tracks")
    visual_layer_owners = snapshot_resource_owners(nodes_data, "sequence_visual_layers")

    with :ok <- validate_connection_ownership(connections, flow_id, target_node_ids),
         :ok <- validate_sequence_resource_ownership(SequenceTrack, flow_id, track_owners),
         :ok <- validate_sequence_resource_ownership(SequenceVisualLayer, flow_id, visual_layer_owners),
         :ok <- validate_sequence_type_transitions(flow_id, nodes_data, target_node_ids),
         :ok <- validate_parent_boundary_transitions(flow_id, nodes_data, target_node_ids) do
      validate_current_node_scope(current_nodes, flow_id)
    end
  end

  defp validate_current_node_scope(current_nodes, flow_id) do
    if Enum.all?(current_nodes, &(&1.flow_id == flow_id)),
      do: :ok,
      else: {:error, :invalid_locked_flow_node_scope}
  end

  defp validate_connection_ownership(connections, flow_id, target_node_ids) do
    ids = Enum.map(connections, & &1["original_id"])

    existing =
      Repo.all(
        from(connection in FlowConnection,
          where: connection.id in ^ids,
          select: {
            connection.id,
            connection.flow_id,
            connection.source_node_id,
            connection.target_node_id
          },
          lock: "FOR SHARE"
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

  defp validate_sequence_resource_ownership(schema, flow_id, expected_owners) do
    ids = Map.keys(expected_owners)

    existing =
      Repo.all(
        from(resource in schema,
          join: node in FlowNode,
          on: node.id == resource.flow_node_id,
          where: resource.id in ^ids,
          select: {resource.id, resource.flow_node_id, node.flow_id},
          lock: "FOR SHARE"
        )
      )

    case Enum.find(existing, fn {resource_id, node_id, owner_flow_id} ->
           owner_flow_id != flow_id or Map.get(expected_owners, resource_id) != node_id
         end) do
      nil -> :ok
      conflict -> {:error, {:snapshot_sequence_resource_ownership_conflict, schema, conflict}}
    end
  end

  defp validate_sequence_type_transitions(flow_id, nodes, target_node_ids) do
    target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
    target_ids = MapSet.to_list(target_node_ids)

    transition_ids =
      from(node in FlowNode,
        where:
          node.flow_id == ^flow_id and node.id in ^target_ids and
            node.type != "sequence",
        select: node.id
      )
      |> Repo.all()
      |> Enum.filter(&(Map.get(target_types, &1) == "sequence"))

    conflicts =
      if transition_ids == [] do
        []
      else
        Repo.all(
          from(connection in FlowConnection,
            where: connection.flow_id == ^flow_id,
            where:
              connection.source_node_id in ^transition_ids or
                connection.target_node_id in ^transition_ids,
            where:
              not (connection.source_node_id in ^target_ids and
                     connection.target_node_id in ^target_ids),
            order_by: [asc: connection.id],
            select: connection.id
          )
        )
      end

    case conflicts do
      [] -> :ok
      [connection_id | _rest] -> {:error, {:sequence_transition_conflicts_with_trash, connection_id}}
    end
  end

  defp validate_parent_boundary_transitions(flow_id, nodes, target_node_ids) do
    target_types = Map.new(nodes, &{&1["original_id"], &1["type"]})
    target_ids = MapSet.to_list(target_node_ids)

    no_longer_sequence_ids =
      from(node in FlowNode,
        where:
          node.flow_id == ^flow_id and node.id in ^target_ids and
            node.type == "sequence",
        select: node.id
      )
      |> Repo.all()
      |> Enum.reject(&(Map.get(target_types, &1) == "sequence"))

    conflict =
      if no_longer_sequence_ids == [] do
        nil
      else
        Repo.one(
          from(node in FlowNode,
            where:
              node.flow_id == ^flow_id and node.parent_id in ^no_longer_sequence_ids and
                node.id not in ^target_ids,
            order_by: [asc: node.id],
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

  defp clear_target_node_state(_flow_id, []), do: {:ok, %{configs: 0, tracks: 0, visual_layers: 0, connections: 0}}

  defp clear_target_node_state(flow_id, target_node_ids) do
    now = TimeHelpers.now()

    {connections, _} =
      Repo.delete_all(
        from(connection in FlowConnection,
          where:
            connection.flow_id == ^flow_id and
              connection.source_node_id in ^target_node_ids and
              connection.target_node_id in ^target_node_ids
        )
      )

    Repo.update_all(
      from(node in FlowNode,
        where: node.flow_id == ^flow_id and node.id in ^target_node_ids
      ),
      set: [parent_id: nil, updated_at: now]
    )

    {layers, _} =
      Repo.delete_all(from(layer in SequenceVisualLayer, where: layer.flow_node_id in ^target_node_ids))

    {tracks, _} =
      Repo.delete_all(from(track in SequenceTrack, where: track.flow_node_id in ^target_node_ids))

    {configs, _} =
      Repo.delete_all(from(config in SequenceConfig, where: config.flow_node_id in ^target_node_ids))

    {:ok, %{configs: configs, tracks: tracks, visual_layers: layers, connections: connections}}
  end

  defp prepare_target_dialogue_id_swaps(_flow_id, []), do: {:ok, 0}

  defp prepare_target_dialogue_id_swaps(flow_id, target_node_ids) do
    token = String.replace(Ecto.UUID.generate(), "-", "")

    from(node in FlowNode,
      where:
        node.flow_id == ^flow_id and node.id in ^target_node_ids and
          node.type == "dialogue",
      order_by: [asc: node.id]
    )
    |> Repo.all()
    |> Enum.reduce_while({:ok, 0}, fn node, {:ok, count} ->
      data = Map.put(node.data || %{}, "localization_id", "restore_#{token}_#{node.id}")

      result =
        node
        |> Changeset.change(data: data)
        |> Changeset.unique_constraint(:data, name: :flow_nodes_dialogue_localization_id_unique)
        |> Repo.update()

      case result do
        {:ok, _node} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_nodes(flow_id, current_nodes, nodes_data, snapshot, project_id, opts) do
    current_by_id = Map.new(current_nodes, &{&1.id, &1})

    Enum.reduce_while(nodes_data, {:ok, %{}}, fn data, {:ok, restored} ->
      case restore_node(flow_id, current_by_id, data, snapshot, project_id, opts) do
        {:ok, restored_node} -> {:cont, {:ok, Map.put(restored, restored_node.id, restored_node)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_node(flow_id, current_by_id, data, snapshot, project_id, opts) do
    id = data["original_id"]
    node = Map.get(current_by_id, id, %FlowNode{id: id, flow_id: flow_id})

    with {:ok, node_data} <- resolve_node_asset_refs(data["data"], snapshot, project_id, opts) do
      attrs = %{
        type: data["type"],
        position_x: data["position_x"],
        position_y: data["position_y"],
        data: node_data,
        word_count: Localization.node_word_count(data["type"], node_data),
        parent_id: nil
      }

      node
      |> FlowNode.materialize_changeset(attrs)
      |> Changeset.put_change(:deleted_at, nil)
      |> persist_restored_node(node)
    end
  end

  defp persist_restored_node(changeset, %{__meta__: %{state: :built}}), do: Repo.insert(changeset)
  defp persist_restored_node(changeset, _node), do: Repo.update(changeset)

  defp resolve_node_asset_refs(data, snapshot, project_id, opts) when is_map(data) do
    case data["audio_asset_id"] do
      nil ->
        {:ok, data}

      asset_id ->
        with {:ok, audio_asset_id} <-
               resolve_flow_asset(
                 asset_id,
                 snapshot,
                 project_id,
                 opts,
                 "audio/",
                 :flow_node_audio
               ) do
          {:ok, Map.put(data, "audio_asset_id", audio_asset_id)}
        end
    end
  end

  defp restore_node_parents(restored, nodes_data) do
    Enum.reduce_while(nodes_data, :ok, fn data, :ok ->
      restore_node_parent(restored, data)
    end)
  end

  defp restore_node_parent(_restored, %{"parent_id" => nil}), do: {:cont, :ok}

  defp restore_node_parent(restored, data) do
    parent_id = data["parent_id"]

    with %FlowNode{type: "sequence"} <- Map.get(restored, parent_id),
         %FlowNode{} = node <- Map.get(restored, data["original_id"]),
         {:ok, _node} <- node |> FlowNode.reparent_changeset(%{parent_id: parent_id}) |> Repo.update() do
      {:cont, :ok}
    else
      _invalid -> {:halt, {:error, {:invalid_snapshot_parent, data["original_id"], parent_id}}}
    end
  end

  defp soft_delete_absent_nodes(current_nodes, snapshot_ids) do
    now = TimeHelpers.now()

    absent_nodes =
      Enum.reject(
        current_nodes,
        &(MapSet.member?(snapshot_ids, &1.id) or not is_nil(&1.deleted_at))
      )

    absent_ids = Enum.map(absent_nodes, & &1.id)

    if absent_ids != [] do
      affected_child_states =
        Repo.all(
          from(node in FlowNode,
            where: node.parent_id in ^absent_ids,
            select: {node.id, node.parent_id}
          )
        )

      Repo.update_all(
        from(node in FlowNode, where: node.id in ^absent_ids and is_nil(node.deleted_at)),
        set: [deleted_at: now, updated_at: now]
      )

      (Enum.map(absent_nodes, &{&1.id, &1.parent_id}) ++ affected_child_states)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.each(fn
        {_node_id, nil} ->
          :ok

        {node_id, parent_id} ->
          Repo.update_all(
            from(node in FlowNode, where: node.id == ^node_id),
            set: [parent_id: parent_id]
          )
      end)
    end

    {:ok, absent_ids}
  end

  defp restore_sequence_resources(restored, nodes_data, snapshot, project_id, opts) do
    Enum.reduce_while(
      nodes_data,
      {:ok, %{configs: 0, track_ids: %{}, visual_layer_ids: %{}}},
      fn data, {:ok, summary} ->
        node = Map.fetch!(restored, data["original_id"])
        restore_sequence_resources_for_node(node, data, snapshot, project_id, opts, summary)
      end
    )
  end

  defp restore_sequence_resources_for_node(%FlowNode{type: type}, _data, _snapshot, _project_id, _opts, summary)
       when type != "sequence", do: {:cont, {:ok, summary}}

  defp restore_sequence_resources_for_node(node, data, snapshot, project_id, opts, summary) do
    with {:ok, config_count} <- restore_sequence_config(node.id, data["sequence_config"]),
         {:ok, track_ids} <-
           restore_sequence_tracks(
             node.id,
             data["sequence_tracks"] || [],
             snapshot,
             project_id,
             opts
           ),
         {:ok, layer_ids} <-
           restore_sequence_layers(
             node.id,
             data["sequence_visual_layers"] || [],
             snapshot,
             project_id,
             opts
           ) do
      {:cont,
       {:ok,
        %{
          configs: summary.configs + config_count,
          track_ids: Map.merge(summary.track_ids, track_ids),
          visual_layer_ids: Map.merge(summary.visual_layer_ids, layer_ids)
        }}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp restore_sequence_config(_node_id, nil), do: {:ok, 0}

  defp restore_sequence_config(node_id, data) when is_map(data) do
    case %SequenceConfig{}
         |> SequenceConfig.create_changeset(%{
           flow_node_id: node_id,
           name: data["name"],
           width: data["width"],
           height: data["height"]
         })
         |> Repo.insert() do
      {:ok, _config} -> {:ok, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_sequence_config(_node_id, data), do: {:error, {:invalid_sequence_config, data}}

  defp restore_sequence_tracks(node_id, tracks, snapshot, project_id, opts) do
    Enum.reduce_while(tracks, {:ok, %{}}, fn data, {:ok, ids} ->
      with {:ok, asset_id} <-
             resolve_flow_asset(
               data["asset_id"],
               snapshot,
               project_id,
               opts,
               "audio/",
               :sequence_track
             ),
           {:ok, track} <-
             %SequenceTrack{id: data["original_id"]}
             |> SequenceTrack.create_changeset(%{
               flow_node_id: node_id,
               kind: data["kind"],
               position: data["position"],
               asset_id: asset_id,
               start_time: data["start_time"],
               end_time: data["end_time"],
               volume: data["volume"]
             })
             |> Repo.insert() do
        {:cont, {:ok, Map.put(ids, data["original_id"], track.id)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_sequence_layers(node_id, layers, snapshot, project_id, opts) do
    if flow_asset_mode(opts) == :drop do
      {:ok, %{}}
    else
      do_restore_sequence_layers(node_id, layers, snapshot, project_id, opts)
    end
  end

  defp do_restore_sequence_layers(node_id, layers, snapshot, project_id, opts) do
    Enum.reduce_while(layers, {:ok, %{}}, fn data, {:ok, ids} ->
      with {:ok, asset_id} <-
             resolve_flow_asset(
               data["asset_id"],
               snapshot,
               project_id,
               opts,
               "image/",
               :sequence_visual_layer
             ),
           true <- is_integer(asset_id) || {:error, {:missing_sequence_visual_layer_asset, data["asset_id"]}},
           attrs =
             data
             |> Map.take(~w(kind label z_index slot x y width height anchor_x anchor_y fit opacity visible))
             |> Map.put("flow_node_id", node_id)
             |> Map.put("asset_id", asset_id),
           {:ok, layer} <-
             %SequenceVisualLayer{id: data["original_id"]}
             |> SequenceVisualLayer.create_changeset(attrs)
             |> Repo.insert() do
        {:cont, {:ok, Map.put(ids, data["original_id"], layer.id)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_connections(flow_id, restored, nodes_data, connections) do
    node_ids = Enum.map(nodes_data, &Map.fetch!(restored, &1["original_id"]).id)

    Enum.reduce_while(connections, {:ok, %{}}, fn data, {:ok, ids} ->
      source_id = Enum.at(node_ids, data["source_node_index"])
      target_id = Enum.at(node_ids, data["target_node_index"])

      result =
        %FlowConnection{id: data["original_id"], flow_id: flow_id}
        |> FlowConnection.create_changeset(%{
          source_node_id: source_id,
          target_node_id: target_id,
          source_pin: data["source_pin"],
          target_pin: data["target_pin"],
          label: data["label"]
        })
        |> Repo.insert()

      case result do
        {:ok, connection} -> {:cont, {:ok, Map.put(ids, data["original_id"], connection.id)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp archive_restore_localization(flow, deleted_node_ids, target_node_ids) do
    now = TimeHelpers.now()
    archive_deleted_localization(flow.project_id, deleted_node_ids, now)

    archive_target_localization(
      flow.project_id,
      target_node_ids,
      LocalizationCodec.active_target_locales(flow.project_id),
      now
    )

    :ok
  end

  defp archive_deleted_localization(_project_id, [], _now), do: :ok

  defp archive_deleted_localization(project_id, deleted_node_ids, now) do
    Repo.update_all(
      from(text in LocalizedTextRecord,
        where:
          text.project_id == ^project_id and text.source_type == "flow_node" and
            text.source_id in ^deleted_node_ids and is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "source_deleted", updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp archive_target_localization(_project_id, [], _active_target_locales, _now), do: :ok
  defp archive_target_localization(_project_id, _target_node_ids, [], _now), do: :ok

  defp archive_target_localization(project_id, target_node_ids, active_target_locales, now) do
    Repo.update_all(
      from(text in LocalizedTextRecord,
        where:
          text.project_id == ^project_id and text.source_type == "flow_node" and
            text.source_id in ^target_node_ids and text.locale_code in ^active_target_locales and
            is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "version_replaced", updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp restore_localization(flow, restored, _nodes_data, snapshot, opts) do
    rows =
      LocalizationCodec.active_target_rows(
        flow.project_id,
        Map.get(snapshot, "localization", [])
      )

    with {:ok, rows} <- materialize_localization_assets(rows, snapshot, flow.project_id, opts),
         :ok <-
           LocalizationCodec.restore(
             flow.project_id,
             rows,
             %{node: Map.new(restored, fn {id, node} -> {id, node.id} end)}
           ) do
      extract_restored_localization(restored)
    end
  end

  defp extract_restored_localization(restored) do
    Enum.reduce_while(Map.values(restored), :ok, fn node, :ok ->
      case Localization.extract_flow_node(node) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp materialize_localization_assets(rows, snapshot, project_id, opts) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, materialized} ->
      case resolve_flow_asset(
             row["vo_asset_id"],
             snapshot,
             project_id,
             opts,
             "audio/",
             :localized_text_voice_over
           ) do
        {:ok, asset_id} ->
          row =
            row
            |> Map.put("vo_asset_id", asset_id)
            |> maybe_drop_voice_status(flow_asset_mode(opts))

          {:cont, {:ok, [row | materialized]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, materialized} -> {:ok, Enum.reverse(materialized)}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_drop_voice_status(%{"vo_status" => status} = row, :drop) when status in ~w(recorded approved),
    do: Map.put(row, "vo_status", "needed")

  defp maybe_drop_voice_status(row, _asset_mode), do: row

  defp resolve_flow_asset(asset_id, snapshot, project_id, opts, expected_prefix, context) do
    case Keyword.fetch(opts, :snapshot_asset_scope) do
      {:ok, scope} ->
        AssetCatalog.materialize_snapshot_asset(
          scope,
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          flow_asset_mode(opts),
          expected_content_type_prefix: expected_prefix,
          asset_context: context
        )

      :error ->
        {:error, :snapshot_asset_restore_scope_not_found}
    end
  end

  defp flow_asset_mode(opts) do
    case Keyword.get(opts, :asset_mode, :reuse) do
      :drop -> :drop
      :copy -> :copy
      _mode -> :reuse
    end
  end

  defp rebuild_references(deleted_ids, restored, project_id) do
    Enum.each(deleted_ids, fn node_id ->
      References.delete_entity_references(node_id)
      References.delete_variable_references(node_id)
    end)

    Enum.reduce_while(Map.values(restored), :ok, fn node, :ok ->
      with :ok <- References.update_entity_references(node, project_id: project_id),
           :ok <- normalize_reference_result(References.update_variable_references(node)) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_reference_result(:ok), do: :ok
  defp normalize_reference_result({:error, _reason} = error), do: error
  defp normalize_reference_result(other), do: {:error, {:unexpected_reference_result, other}}

  defp restorable_main_state(_flow, false, _opts), do: false

  defp restorable_main_state(flow, true, opts) do
    if Keyword.get(opts, :__force_non_main_on_conflict, false) do
      false
    else
      not Repo.exists?(
        from(candidate in Flow,
          where:
            candidate.project_id == ^flow.project_id and candidate.id != ^flow.id and
              candidate.is_main == true and is_nil(candidate.deleted_at)
        )
      )
    end
  end

  defp update_flow(flow, snapshot, is_main) do
    attrs = snapshot |> Map.take(@flow_fields) |> Map.put("is_main", is_main)
    flow |> Flow.update_changeset(attrs) |> Repo.update()
  end

  defp validate(snapshot, flow_id), do: FlowSnapshotValidator.validate(snapshot, flow_id)

  defp normalize_id(nil), do: {:ok, nil}
  defp normalize_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp normalize_id(_id), do: :error
  defp normalize_id_value(value), do: with({:ok, id} <- normalize_id(value), do: id)
  defp positive_id?(id), do: is_integer(id) and id > 0

  defp normalize_json(value), do: value |> Jason.encode!() |> Jason.decode!()
end

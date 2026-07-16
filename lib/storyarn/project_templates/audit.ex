defmodule Storyarn.ProjectTemplates.Audit do
  @moduledoc """
  Validates whether a project can be published as a template.

  This first pass focuses on known migration hazards that can corrupt a cloned
  flow graph. The report shape is JSON-serializable so it can be stored on each
  immutable template version.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery

  @doc """
  Runs template-publication audit checks for a project.
  """
  @spec run(integer()) :: {:ok, map()} | {:error, map()}
  def run(project_id) do
    case run_with_snapshot(project_id) do
      {:ok, report, _snapshot} -> {:ok, report}
      {:error, report} -> {:error, report}
    end
  end

  @doc """
  Runs the audit and returns the snapshot used by the materialization check.
  """
  @spec run_with_snapshot(integer()) :: {:ok, map(), map()} | {:error, map()}
  def run_with_snapshot(project_id) do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project_id)

    static_errors =
      []
      |> Kernel.++(stale_connection_errors(project_id))
      |> Kernel.++(unsafe_subflow_pin_errors(project_id))
      |> Kernel.++(invalid_scene_pin_sheet_ref_errors(project_id))
      |> Kernel.++(invalid_scene_pin_flow_ref_errors(project_id))
      |> Kernel.++(invalid_scene_zone_scene_target_errors(project_id))
      |> Kernel.++(invalid_scene_zone_flow_target_errors(project_id))
      |> Kernel.++(invalid_localization_source_ref_errors(project_id))
      |> Kernel.++(unsupported_localization_source_ref_errors(project_id))
      |> Kernel.++(uncopiable_asset_reference_errors(project_id))
      |> Kernel.++(snapshot_sequence_integrity_errors(snapshot))

    {materialization_errors, materialization_report} =
      materialization_audit(project_id, snapshot, static_errors)

    errors = static_errors ++ materialization_errors

    report = %{
      "status" => if(errors == [], do: "passed", else: "failed"),
      "errors" => errors,
      "warnings" => [],
      "entity_counts" => snapshot_entity_counts(snapshot),
      "materialization" => materialization_report
    }

    if errors == [], do: {:ok, report, snapshot}, else: {:error, report}
  end

  @doc """
  Verifies that an already-built template snapshot can be materialized in this deployment.
  """
  @spec verify_snapshot_materialization(map(), integer(), integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def verify_snapshot_materialization(snapshot, workspace_id, user_id, opts \\ []) do
    snapshot_counts = snapshot_entity_counts(snapshot)
    integrity_errors = snapshot_sequence_integrity_errors(snapshot)

    case recover_snapshot_in_rollback(snapshot, workspace_id, user_id, opts) do
      {:ok, recovered_counts, materialized_errors} ->
        count_errors =
          count_mismatch_errors(
            "snapshot_recovery_count_mismatch",
            "snapshot_count",
            snapshot_counts,
            "recovered_count",
            recovered_counts
          )

        errors = integrity_errors ++ count_errors ++ materialized_errors

        report = %{
          "status" => if(errors == [], do: "passed", else: "failed"),
          "errors" => errors,
          "snapshot_counts" => snapshot_counts,
          "recovered_counts" => recovered_counts
        }

        if errors == [], do: {:ok, report}, else: {:error, report}

      {:error, reason} ->
        {:error,
         %{
           "status" => "failed",
           "errors" =>
             integrity_errors ++
               [
                 %{
                   "type" => "template_materialization_failed",
                   "reason" => inspect(reason)
                 }
               ],
           "snapshot_counts" => snapshot_counts,
           "recovery_error" => inspect(reason)
         }}
    end
  end

  @doc """
  Performs the pure structural checks required before a stored template snapshot
  can be installed. This keeps legacy artifacts that omitted sequence state from
  silently materializing incomplete projects.
  """
  @spec validate_snapshot_integrity(map()) :: :ok | {:error, [map()]}
  def validate_snapshot_integrity(snapshot) when is_map(snapshot) do
    case snapshot_sequence_integrity_errors(snapshot) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate_snapshot_integrity(_snapshot) do
    {:error, [%{"type" => "invalid_template_snapshot"}]}
  end

  defp snapshot_sequence_integrity_errors(snapshot) do
    snapshot
    |> snapshot_collection("flows")
    |> Enum.with_index()
    |> Enum.flat_map(&snapshot_flow_integrity_errors/1)
  end

  defp snapshot_flow_integrity_errors({flow_entry, _flow_index}) when is_map(flow_entry) do
    snapshot_flow_integrity_errors(flow_entry, flow_entry["snapshot"])
  end

  defp snapshot_flow_integrity_errors({_flow_entry, flow_index}) do
    [%{"type" => "invalid_snapshot_flow", "flow_index" => flow_index}]
  end

  defp snapshot_flow_integrity_errors(flow_entry, flow_snapshot) when is_map(flow_snapshot) do
    flow_id = flow_entry["id"] || flow_snapshot["original_id"]
    nodes = snapshot_collection(flow_snapshot, "nodes")
    {valid_nodes, malformed_nodes} = Enum.split_with(nodes, &is_map/1)
    nodes_by_original_id = Map.new(valid_nodes, &{&1["original_id"], &1})

    shape_errors = Enum.map(malformed_nodes, &invalid_snapshot_flow_node_error(&1, flow_id))
    duplicate_errors = duplicate_snapshot_node_id_errors(valid_nodes, flow_id)

    node_errors =
      Enum.flat_map(valid_nodes, &sequence_snapshot_errors(&1, nodes_by_original_id, flow_id))

    shape_errors ++ duplicate_errors ++ node_errors
  end

  defp snapshot_flow_integrity_errors(flow_entry, _malformed_snapshot) do
    [
      %{
        "type" => "invalid_snapshot_flow_snapshot",
        "flow_id" => flow_entry["id"]
      }
    ]
  end

  defp invalid_snapshot_flow_node_error(node, flow_id) do
    %{
      "type" => "invalid_snapshot_flow_node",
      "flow_id" => flow_id,
      "value" => inspect(node)
    }
  end

  defp duplicate_snapshot_node_id_errors(nodes, flow_id) do
    nodes
    |> Enum.reject(&is_nil(&1["original_id"]))
    |> Enum.group_by(& &1["original_id"])
    |> Enum.flat_map(fn
      {_node_id, [_node]} ->
        []

      {node_id, duplicates} ->
        [
          %{
            "type" => "duplicate_snapshot_flow_node_id",
            "flow_id" => flow_id,
            "node_id" => node_id,
            "count" => length(duplicates)
          }
        ]
    end)
  end

  defp sequence_snapshot_errors(node, nodes_by_original_id, flow_id) do
    sequence? = node["type"] == "sequence"

    config_errors =
      if sequence? and not is_map(node["sequence_config"]) do
        [
          %{
            "type" => "missing_sequence_config_snapshot",
            "flow_id" => flow_id,
            "node_id" => node["original_id"]
          }
        ]
      else
        []
      end

    collection_errors =
      Enum.flat_map(
        ["sequence_tracks", "sequence_visual_layers"],
        &sequence_collection_snapshot_errors(node, &1, flow_id, sequence?)
      )

    config_errors ++ collection_errors ++ snapshot_parent_errors(node, nodes_by_original_id, flow_id)
  end

  defp sequence_collection_snapshot_errors(node, key, flow_id, sequence?) do
    case Map.fetch(node, key) do
      {:ok, value} when is_list(value) ->
        sequence_collection_item_errors(value, node["original_id"], key, flow_id)

      {:ok, value} when not is_list(value) ->
        [
          %{
            "type" => "invalid_sequence_collection_snapshot",
            "flow_id" => flow_id,
            "node_id" => node["original_id"],
            "field" => key
          }
        ]

      :error ->
        missing_sequence_collection_errors(sequence?, node["original_id"], key, flow_id)
    end
  end

  defp sequence_collection_item_errors(items, node_id, key, flow_id) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(&sequence_collection_item_error(&1, node_id, key, flow_id))
  end

  defp sequence_collection_item_error({item, _index}, _node_id, _key, _flow_id) when is_map(item), do: []

  defp sequence_collection_item_error({_item, index}, node_id, key, flow_id) do
    [
      %{
        "type" => "invalid_sequence_collection_item_snapshot",
        "flow_id" => flow_id,
        "node_id" => node_id,
        "field" => key,
        "index" => index
      }
    ]
  end

  defp missing_sequence_collection_errors(false, _node_id, _key, _flow_id), do: []

  defp missing_sequence_collection_errors(true, node_id, key, flow_id) do
    [
      %{
        "type" => "missing_sequence_collection_snapshot",
        "flow_id" => flow_id,
        "node_id" => node_id,
        "field" => key
      }
    ]
  end

  defp snapshot_parent_errors(node, nodes_by_original_id, flow_id) do
    parent_id = node["parent_id"]
    node_id = node["original_id"]

    case {parent_id, Map.get(nodes_by_original_id, parent_id)} do
      {nil, _parent} ->
        []

      {parent_id, %{"type" => "sequence", "original_id" => parent_id}}
      when parent_id != node_id ->
        []

      {parent_id, parent} ->
        [
          %{
            "type" => "invalid_sequence_parent_snapshot",
            "flow_id" => flow_id,
            "node_id" => node_id,
            "parent_id" => parent_id,
            "parent_type" => parent && parent["type"]
          }
        ]
    end
  end

  defp stale_connection_errors(project_id) do
    query =
      from c in FlowConnection,
        join: f in Flow,
        on: f.id == c.flow_id,
        left_join: source in FlowNode,
        on: source.id == c.source_node_id and source.flow_id == f.id and is_nil(source.deleted_at),
        left_join: target in FlowNode,
        on: target.id == c.target_node_id and target.flow_id == f.id and is_nil(target.deleted_at),
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(source.id) or is_nil(target.id),
        select: %{
          "type" => "stale_flow_connection",
          "flow_id" => f.id,
          "connection_id" => c.id,
          "source_node_id" => c.source_node_id,
          "source_pin" => c.source_pin,
          "target_node_id" => c.target_node_id,
          "target_pin" => c.target_pin
        }

    Repo.all(query)
  end

  defp unsafe_subflow_pin_errors(project_id) do
    active_exit_node_ids_by_flow = active_exit_node_ids_by_flow(project_id)

    project_id
    |> subflow_exit_pin_refs()
    |> Enum.reject(&remappable_exit_pin?(&1, active_exit_node_ids_by_flow))
    |> Enum.map(&subflow_exit_pin_error/1)
  end

  defp subflow_exit_pin_refs(project_id) do
    query =
      from c in FlowConnection,
        join: f in Flow,
        on: f.id == c.flow_id,
        join: source in FlowNode,
        on: source.id == c.source_node_id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(source.deleted_at),
        where: source.type == "subflow" and like(c.source_pin, "exit_%"),
        select: %{
          flow_id: f.id,
          connection_id: c.id,
          source_node_id: c.source_node_id,
          source_node_data: source.data,
          source_pin: c.source_pin,
          target_node_id: c.target_node_id,
          target_pin: c.target_pin
        }

    Repo.all(query)
  end

  defp active_exit_node_ids_by_flow(project_id) do
    query =
      from n in FlowNode,
        join: f in Flow,
        on: f.id == n.flow_id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(n.deleted_at),
        where: n.type == "exit",
        select: {f.id, n.id}

    query
    |> Repo.all()
    |> Enum.reduce(%{}, fn {flow_id, node_id}, acc ->
      Map.update(acc, flow_id, MapSet.new([node_id]), &MapSet.put(&1, node_id))
    end)
  end

  defp remappable_exit_pin?(
         %{source_node_data: source_node_data, source_pin: "exit_" <> old_id_text},
         active_exit_node_ids_by_flow
       ) do
    case Integer.parse(old_id_text) do
      {old_id, ""} ->
        case Map.get(active_exit_node_ids_by_flow, referenced_flow_id(source_node_data)) do
          %MapSet{} = active_exit_node_ids -> MapSet.member?(active_exit_node_ids, old_id)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp referenced_flow_id(%{"referenced_flow_id" => referenced_flow_id}) when is_integer(referenced_flow_id) do
    referenced_flow_id
  end

  defp referenced_flow_id(%{"referenced_flow_id" => referenced_flow_id}) when is_binary(referenced_flow_id) do
    case Integer.parse(referenced_flow_id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp referenced_flow_id(_source_node_data), do: nil

  defp subflow_exit_pin_error(ref) do
    %{
      "type" => "unremappable_subflow_exit_pin",
      "flow_id" => ref.flow_id,
      "connection_id" => ref.connection_id,
      "source_node_id" => ref.source_node_id,
      "referenced_flow_id" => referenced_flow_id(ref.source_node_data),
      "source_pin" => ref.source_pin,
      "target_node_id" => ref.target_node_id,
      "target_pin" => ref.target_pin
    }
  end

  defp invalid_scene_pin_sheet_ref_errors(project_id) do
    query =
      from p in ScenePin,
        join: scene in Scene,
        on: scene.id == p.scene_id,
        left_join: sheet in Sheet,
        on: sheet.id == p.sheet_id and sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: not is_nil(p.sheet_id) and is_nil(sheet.id),
        select: %{
          "type" => "invalid_scene_pin_sheet_ref",
          "scene_id" => scene.id,
          "pin_id" => p.id,
          "sheet_id" => p.sheet_id
        }

    Repo.all(query)
  end

  defp invalid_scene_pin_flow_ref_errors(project_id) do
    query =
      from p in ScenePin,
        join: scene in Scene,
        on: scene.id == p.scene_id,
        left_join: flow in Flow,
        on: flow.id == p.flow_id and flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: not is_nil(p.flow_id) and is_nil(flow.id),
        select: %{
          "type" => "invalid_scene_pin_flow_ref",
          "scene_id" => scene.id,
          "pin_id" => p.id,
          "flow_id" => p.flow_id
        }

    Repo.all(query)
  end

  defp invalid_scene_zone_scene_target_errors(project_id) do
    query =
      from z in SceneZone,
        join: scene in Scene,
        on: scene.id == z.scene_id,
        left_join: target_scene in Scene,
        on: target_scene.id == z.target_id and target_scene.project_id == ^project_id and is_nil(target_scene.deleted_at),
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: z.target_type == "scene" and not is_nil(z.target_id) and is_nil(target_scene.id),
        select: %{
          "type" => "invalid_scene_zone_target_ref",
          "scene_id" => scene.id,
          "zone_id" => z.id,
          "target_type" => z.target_type,
          "target_id" => z.target_id
        }

    Repo.all(query)
  end

  defp invalid_scene_zone_flow_target_errors(project_id) do
    query =
      from z in SceneZone,
        join: scene in Scene,
        on: scene.id == z.scene_id,
        left_join: target_flow in Flow,
        on: target_flow.id == z.target_id and target_flow.project_id == ^project_id and is_nil(target_flow.deleted_at),
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: z.target_type == "flow" and not is_nil(z.target_id) and is_nil(target_flow.id),
        select: %{
          "type" => "invalid_scene_zone_target_ref",
          "scene_id" => scene.id,
          "zone_id" => z.id,
          "target_type" => z.target_type,
          "target_id" => z.target_id
        }

    Repo.all(query)
  end

  defp invalid_localization_source_ref_errors(project_id) do
    []
    |> Kernel.++(invalid_flow_node_localization_ref_errors(project_id))
    |> Kernel.++(invalid_block_localization_ref_errors(project_id))
    |> Kernel.++(invalid_sheet_localization_ref_errors(project_id))
  end

  defp invalid_flow_node_localization_ref_errors(project_id) do
    query =
      from text in LocalizedText,
        left_join: node in FlowNode,
        on: node.id == text.source_id and is_nil(node.deleted_at),
        left_join: flow in Flow,
        on: flow.id == node.flow_id and flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where:
          text.project_id == ^project_id and text.source_type == "flow_node" and
            is_nil(text.archived_at),
        where: is_nil(flow.id),
        select: %{
          "type" => "invalid_localization_source_ref",
          "localized_text_id" => text.id,
          "source_type" => text.source_type,
          "source_id" => text.source_id,
          "source_field" => text.source_field
        }

    Repo.all(query)
  end

  defp invalid_block_localization_ref_errors(project_id) do
    query =
      from text in LocalizedText,
        left_join: block in Block,
        on: block.id == text.source_id and is_nil(block.deleted_at),
        left_join: sheet in Sheet,
        on: sheet.id == block.sheet_id and sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where:
          text.project_id == ^project_id and text.source_type == "block" and
            is_nil(text.archived_at),
        where: is_nil(sheet.id),
        select: %{
          "type" => "invalid_localization_source_ref",
          "localized_text_id" => text.id,
          "source_type" => text.source_type,
          "source_id" => text.source_id,
          "source_field" => text.source_field
        }

    Repo.all(query)
  end

  defp invalid_sheet_localization_ref_errors(project_id) do
    query =
      from text in LocalizedText,
        left_join: sheet in Sheet,
        on: sheet.id == text.source_id and sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where:
          text.project_id == ^project_id and text.source_type == "sheet" and
            is_nil(text.archived_at),
        where: is_nil(sheet.id),
        select: %{
          "type" => "invalid_localization_source_ref",
          "localized_text_id" => text.id,
          "source_type" => text.source_type,
          "source_id" => text.source_id,
          "source_field" => text.source_field
        }

    Repo.all(query)
  end

  defp unsupported_localization_source_ref_errors(project_id) do
    source_types = SourceContract.source_types()

    query =
      from text in LocalizedText,
        where: text.project_id == ^project_id,
        where: text.source_type not in ^source_types,
        select: %{
          "type" => "unsupported_localization_source_ref",
          "localized_text_id" => text.id,
          "source_type" => text.source_type,
          "source_id" => text.source_id,
          "source_field" => text.source_field
        }

    Repo.all(query)
  end

  defp uncopiable_asset_reference_errors(project_id) do
    {invalid_refs, asset_refs} =
      project_id
      |> referenced_asset_refs()
      |> Enum.split_with(&is_nil(&1.asset_id))

    assets_by_id = assets_by_id(Enum.map(asset_refs, & &1.asset_id))

    invalid_errors = Enum.map(invalid_refs, &invalid_asset_reference_error/1)

    asset_errors =
      asset_refs
      |> Enum.reject(&copiable_project_asset?(&1, assets_by_id, project_id))
      |> Enum.map(&asset_reference_error(&1, Map.get(assets_by_id, &1.asset_id), project_id))

    invalid_errors ++ asset_errors
  end

  defp referenced_asset_refs(project_id) do
    []
    |> Kernel.++(sheet_banner_asset_refs(project_id))
    |> Kernel.++(sheet_avatar_asset_refs(project_id))
    |> Kernel.++(block_gallery_asset_refs(project_id))
    |> Kernel.++(scene_background_asset_refs(project_id))
    |> Kernel.++(scene_pin_icon_asset_refs(project_id))
    |> Kernel.++(scene_zone_label_icon_asset_refs(project_id))
    |> Kernel.++(flow_audio_asset_refs(project_id))
    |> Kernel.++(sequence_track_asset_refs(project_id))
    |> Kernel.++(sequence_visual_layer_asset_refs(project_id))
    |> Kernel.++(localized_vo_asset_refs(project_id))
  end

  defp sheet_banner_asset_refs(project_id) do
    query =
      from sheet in Sheet,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: not is_nil(sheet.banner_asset_id),
        select: %{
          entity_type: "sheet",
          entity_id: sheet.id,
          field: "banner_asset_id",
          asset_id: sheet.banner_asset_id,
          raw_asset_id: sheet.banner_asset_id
        }

    Repo.all(query)
  end

  defp sheet_avatar_asset_refs(project_id) do
    query =
      from avatar in SheetAvatar,
        join: sheet in Sheet,
        on: sheet.id == avatar.sheet_id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        select: %{
          entity_type: "sheet_avatar",
          entity_id: avatar.id,
          field: "asset_id",
          asset_id: avatar.asset_id,
          raw_asset_id: avatar.asset_id
        }

    Repo.all(query)
  end

  defp block_gallery_asset_refs(project_id) do
    query =
      from gallery_image in BlockGalleryImage,
        join: block in Block,
        on: block.id == gallery_image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        select: %{
          entity_type: "block_gallery_image",
          entity_id: gallery_image.id,
          field: "asset_id",
          asset_id: gallery_image.asset_id,
          raw_asset_id: gallery_image.asset_id
        }

    Repo.all(query)
  end

  defp scene_background_asset_refs(project_id) do
    query =
      from scene in Scene,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: not is_nil(scene.background_asset_id),
        select: %{
          entity_type: "scene",
          entity_id: scene.id,
          field: "background_asset_id",
          asset_id: scene.background_asset_id,
          raw_asset_id: scene.background_asset_id
        }

    Repo.all(query)
  end

  defp scene_pin_icon_asset_refs(project_id) do
    query =
      from pin in ScenePin,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: not is_nil(pin.icon_asset_id),
        select: %{
          entity_type: "scene_pin",
          entity_id: pin.id,
          field: "icon_asset_id",
          asset_id: pin.icon_asset_id,
          raw_asset_id: pin.icon_asset_id
        }

    Repo.all(query)
  end

  defp scene_zone_label_icon_asset_refs(project_id) do
    query =
      from zone in SceneZone,
        join: scene in Scene,
        on: scene.id == zone.scene_id,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where: not is_nil(zone.label_icon_asset_id),
        select: %{
          entity_type: "scene_zone",
          entity_id: zone.id,
          field: "label_icon_asset_id",
          asset_id: zone.label_icon_asset_id,
          raw_asset_id: zone.label_icon_asset_id
        }

    Repo.all(query)
  end

  defp flow_audio_asset_refs(project_id) do
    query =
      from node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at),
        where: not is_nil(fragment("?->>'audio_asset_id'", node.data)),
        select: %{
          entity_type: "flow_node",
          entity_id: node.id,
          field: "data.audio_asset_id",
          asset_id: fragment("?->>'audio_asset_id'", node.data),
          raw_asset_id: fragment("?->>'audio_asset_id'", node.data)
        }

    query
    |> Repo.all()
    |> Enum.map(&normalize_asset_ref/1)
  end

  defp sequence_track_asset_refs(project_id) do
    query =
      from track in SequenceTrack,
        join: node in FlowNode,
        on: node.id == track.flow_node_id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at) and not is_nil(track.asset_id),
        select: %{
          entity_type: "flow_node_sequence_track",
          entity_id: track.id,
          field: "asset_id",
          asset_id: track.asset_id,
          raw_asset_id: track.asset_id
        }

    Repo.all(query)
  end

  defp sequence_visual_layer_asset_refs(project_id) do
    query =
      from layer in SequenceVisualLayer,
        join: node in FlowNode,
        on: node.id == layer.flow_node_id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at),
        select: %{
          entity_type: "flow_node_sequence_visual_layer",
          entity_id: layer.id,
          field: "asset_id",
          asset_id: layer.asset_id,
          raw_asset_id: layer.asset_id
        }

    Repo.all(query)
  end

  defp localized_vo_asset_refs(project_id) do
    query =
      from text in LocalizedText,
        where: text.project_id == ^project_id,
        where: not is_nil(text.vo_asset_id),
        select: %{
          entity_type: "localized_text",
          entity_id: text.id,
          field: "vo_asset_id",
          asset_id: text.vo_asset_id,
          raw_asset_id: text.vo_asset_id
        }

    Repo.all(query)
  end

  defp normalize_asset_ref(%{asset_id: asset_id} = ref) do
    case normalize_asset_id(asset_id) do
      {:ok, id} -> %{ref | asset_id: id}
      :error -> %{ref | asset_id: nil}
    end
  end

  defp normalize_asset_id(asset_id) when is_integer(asset_id), do: {:ok, asset_id}

  defp normalize_asset_id(asset_id) when is_binary(asset_id) do
    case Integer.parse(asset_id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp normalize_asset_id(_asset_id), do: :error

  defp assets_by_id([]), do: %{}

  defp assets_by_id(asset_ids) do
    asset_ids = Enum.uniq(asset_ids)

    Asset
    |> where([asset], asset.id in ^asset_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp copiable_project_asset?(ref, assets_by_id, project_id) do
    case Map.get(assets_by_id, ref.asset_id) do
      nil -> false
      %Asset{project_id: ^project_id} = asset -> copiable_asset?(asset)
      %Asset{} -> false
    end
  end

  defp copiable_asset?(%Asset{key: key, blob_hash: blob_hash}) do
    present?(key) and present?(blob_hash)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp invalid_asset_reference_error(ref) do
    %{
      "type" => "invalid_asset_reference",
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "raw_asset_id" => ref.raw_asset_id
    }
  end

  defp asset_reference_error(ref, nil, _project_id) do
    %{
      "type" => "missing_asset_reference",
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "asset_id" => ref.asset_id
    }
  end

  defp asset_reference_error(ref, %Asset{} = asset, project_id) do
    type =
      if asset.project_id == project_id do
        "uncopiable_asset_reference"
      else
        "cross_project_asset_reference"
      end

    %{
      "type" => type,
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "asset_id" => ref.asset_id,
      "asset_project_id" => asset.project_id,
      "has_key" => present?(asset.key),
      "has_blob_hash" => present?(asset.blob_hash)
    }
  end

  defp materialization_audit(_project_id, _snapshot, static_errors) when static_errors != [] do
    {[],
     %{
       "status" => "skipped",
       "reason" => "static_errors"
     }}
  end

  defp materialization_audit(project_id, snapshot, []) do
    source_counts = materialized_entity_counts(project_id)
    snapshot_counts = snapshot_entity_counts(snapshot)

    source_snapshot_errors =
      count_mismatch_errors(
        "source_snapshot_count_mismatch",
        "source_count",
        source_counts,
        "snapshot_count",
        snapshot_counts
      )

    case recover_project_in_rollback(project_id, snapshot) do
      {:ok, recovered_counts, materialized_asset_errors} ->
        snapshot_recovery_errors =
          count_mismatch_errors(
            "snapshot_recovery_count_mismatch",
            "snapshot_count",
            snapshot_counts,
            "recovered_count",
            recovered_counts
          )

        errors = source_snapshot_errors ++ snapshot_recovery_errors ++ materialized_asset_errors

        {errors,
         %{
           "status" => if(errors == [], do: "passed", else: "failed"),
           "source_counts" => source_counts,
           "snapshot_counts" => snapshot_counts,
           "recovered_counts" => recovered_counts
         }}

      {:error, reason} ->
        error = %{
          "type" => "template_materialization_failed",
          "reason" => inspect(reason)
        }

        {[error],
         %{
           "status" => "failed",
           "source_counts" => source_counts,
           "snapshot_counts" => snapshot_counts,
           "recovery_error" => inspect(reason)
         }}
    end
  end

  defp recover_project_in_rollback(project_id, snapshot) do
    project = Repo.get!(Project, project_id)

    recover_snapshot_in_rollback(snapshot, project.workspace_id, project.owner_id, name: "Template Audit #{project.id}")
  end

  defp recover_snapshot_in_rollback(snapshot, workspace_id, user_id, opts) do
    {result, copied_asset_keys} =
      snapshot
      |> recover_project_transaction_result(workspace_id, user_id, opts)
      |> extract_recover_project_result()

    cleanup_materialized_asset_storage(copied_asset_keys)

    result
  end

  defp recover_project_transaction_result(snapshot, workspace_id, user_id, opts) do
    name = Keyword.get(opts, :name, "Template Materialization Audit")

    Repo.transaction(
      fn ->
        result =
          with {:ok, recovered_project} <-
                 ProjectRecovery.recover_project(workspace_id, snapshot, user_id,
                   name: name,
                   template_clone: true
                 ) do
            {:ok, materialized_entity_counts(recovered_project.id),
             materialized_asset_reference_errors(recovered_project.id),
             materialized_asset_storage_keys(recovered_project.id)}
          end

        Repo.rollback({:template_materialization_audit, result})
      end,
      timeout: to_timeout(minute: 5)
    )
  end

  defp extract_recover_project_result({:error, {:template_materialization_audit, {:ok, counts, errors, asset_keys}}}) do
    {{:ok, counts, errors}, asset_keys}
  end

  defp extract_recover_project_result({:error, {:template_materialization_audit, {:error, reason}}}) do
    {{:error, reason}, []}
  end

  defp extract_recover_project_result({:error, reason}) do
    {{:error, reason}, []}
  end

  defp extract_recover_project_result({:ok, _unexpected}) do
    {{:error, :unexpected_materialization_audit_commit}, []}
  end

  defp materialized_asset_storage_keys(project_id) do
    query =
      from asset in Asset,
        where: asset.project_id == ^project_id,
        where: not is_nil(asset.key),
        select: asset.key

    Repo.all(query)
  end

  defp cleanup_materialized_asset_storage(asset_keys) do
    asset_keys
    |> Enum.uniq()
    |> Enum.each(fn key ->
      _ = Storage.delete(key)
    end)
  end

  defp count_mismatch_errors(type, left_label, left_counts, right_label, right_counts) do
    left_counts
    |> Map.keys()
    |> Kernel.++(Map.keys(right_counts))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      left_value = Map.get(left_counts, key, 0)
      right_value = Map.get(right_counts, key, 0)

      if left_value == right_value do
        []
      else
        [
          %{
            "type" => type,
            "count_key" => key,
            left_label => left_value,
            right_label => right_value
          }
        ]
      end
    end)
  end

  defp materialized_entity_counts(project_id) do
    %{
      "sheets" => count_active_project_records(Sheet, project_id),
      "sheet_blocks" => count_active_sheet_blocks(project_id),
      "sheet_avatars" => count_sheet_avatars(project_id),
      "block_gallery_images" => count_block_gallery_images(project_id),
      "flows" => count_active_project_records(Flow, project_id),
      "flow_nodes" => count_flow_nodes(project_id),
      "flow_connections" => count_flow_connections(project_id),
      "flow_node_parent_links" => count_flow_node_parent_links(project_id),
      "sequence_configs" => count_sequence_children(SequenceConfig, project_id),
      "sequence_tracks" => count_sequence_children(SequenceTrack, project_id),
      "sequence_visual_layers" => count_sequence_children(SequenceVisualLayer, project_id),
      "scenes" => count_active_project_records(Scene, project_id),
      "scene_layers" => count_scene_children(SceneLayer, project_id),
      "scene_pins" => count_scene_children(ScenePin, project_id),
      "scene_zones" => count_scene_children(SceneZone, project_id),
      "scene_connections" => count_scene_children(SceneConnection, project_id),
      "scene_annotations" => count_scene_children(SceneAnnotation, project_id),
      "languages" => count_project_records(ProjectLanguage, project_id),
      "localized_texts" => count_project_records(LocalizedText, project_id),
      "glossary_entries" => count_project_records(GlossaryEntry, project_id)
    }
  end

  defp count_active_project_records(schema, project_id) do
    query = from(record in schema, where: record.project_id == ^project_id and is_nil(record.deleted_at))

    Repo.aggregate(query, :count)
  end

  defp count_project_records(schema, project_id) do
    Repo.aggregate(from(record in schema, where: record.project_id == ^project_id), :count)
  end

  defp count_active_sheet_blocks(project_id) do
    query =
      from block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_sheet_avatars(project_id) do
    query =
      from avatar in SheetAvatar,
        join: sheet in Sheet,
        on: sheet.id == avatar.sheet_id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_block_gallery_images(project_id) do
    query =
      from gallery_image in BlockGalleryImage,
        join: block in Block,
        on: block.id == gallery_image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_flow_nodes(project_id) do
    query =
      from node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_flow_connections(project_id) do
    query =
      from connection in FlowConnection,
        join: flow in Flow,
        on: flow.id == connection.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_flow_node_parent_links(project_id) do
    query =
      from node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at) and not is_nil(node.parent_id)

    Repo.aggregate(query, :count)
  end

  defp count_sequence_children(schema, project_id) do
    query =
      from child in schema,
        join: node in FlowNode,
        on: node.id == child.flow_node_id,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        where: is_nil(node.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp count_scene_children(schema, project_id) do
    query =
      from record in schema,
        join: scene in Scene,
        on: scene.id == record.scene_id,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at)

    Repo.aggregate(query, :count)
  end

  defp snapshot_entity_counts(snapshot) do
    sheets = snapshot_collection(snapshot, "sheets")
    flows = snapshot_collection(snapshot, "flows")
    scenes = snapshot_collection(snapshot, "scenes")
    localization = if is_map(snapshot["localization"]), do: snapshot["localization"], else: %{}

    sheet_snapshots = snapshots_for(sheets)
    flow_snapshots = snapshots_for(flows)
    scene_snapshots = snapshots_for(scenes)

    %{}
    |> Map.merge(snapshot_sheet_counts(sheets, sheet_snapshots))
    |> Map.merge(snapshot_flow_counts(flows, flow_snapshots))
    |> Map.merge(snapshot_scene_counts(scenes, scene_snapshots))
    |> Map.merge(snapshot_localization_counts(localization))
  end

  defp snapshots_for(entries) do
    Enum.map(entries, fn
      %{"snapshot" => snapshot} when is_map(snapshot) -> snapshot
      _entry -> %{}
    end)
  end

  defp snapshot_sheet_counts(sheets, sheet_snapshots) do
    %{
      "sheets" => length(sheets),
      "sheet_blocks" => sum_nested_count(sheet_snapshots, "blocks"),
      "sheet_avatars" => sum_nested_count(sheet_snapshots, "avatars"),
      "block_gallery_images" => count_snapshot_gallery_images(sheet_snapshots)
    }
  end

  defp snapshot_flow_counts(flows, flow_snapshots) do
    nodes = Enum.flat_map(flow_snapshots, &snapshot_collection(&1, "nodes"))

    %{
      "flows" => length(flows),
      "flow_nodes" => length(nodes),
      "flow_connections" => sum_nested_count(flow_snapshots, "connections"),
      "flow_node_parent_links" => Enum.count(nodes, &(not is_nil(&1["parent_id"]))),
      "sequence_configs" => Enum.count(nodes, &is_map(&1["sequence_config"])),
      "sequence_tracks" => sum_nested_count(nodes, "sequence_tracks"),
      "sequence_visual_layers" => sum_nested_count(nodes, "sequence_visual_layers")
    }
  end

  defp snapshot_scene_counts(scenes, scene_snapshots) do
    %{
      "scenes" => length(scenes),
      "scene_layers" => count_snapshot_scene_layers(scene_snapshots),
      "scene_pins" => count_snapshot_scene_children(scene_snapshots, "pins", "orphan_pins"),
      "scene_zones" => count_snapshot_scene_children(scene_snapshots, "zones", "orphan_zones"),
      "scene_connections" => sum_nested_count(scene_snapshots, "connections"),
      "scene_annotations" => count_snapshot_scene_children(scene_snapshots, "annotations", "orphan_annotations")
    }
  end

  defp snapshot_localization_counts(localization) do
    %{
      "languages" => length(localization["languages"] || []),
      "localized_texts" => length(localization["texts"] || []),
      "glossary_entries" => length(localization["glossary"] || [])
    }
  end

  defp sum_nested_count(entries, key) do
    Enum.sum(Enum.map(entries, &length(snapshot_collection(&1, key))))
  end

  defp snapshot_collection(snapshot, key) when is_map(snapshot) do
    case Map.get(snapshot, key, []) do
      collection when is_list(collection) -> collection
      _malformed -> []
    end
  end

  defp snapshot_collection(_snapshot, _key), do: []

  defp count_snapshot_gallery_images(sheet_snapshots) do
    sheet_snapshots
    |> Enum.flat_map(&(&1["blocks"] || []))
    |> sum_nested_count("gallery_images")
  end

  defp count_snapshot_scene_layers(scene_snapshots) do
    sum_nested_count(scene_snapshots, "layers")
  end

  defp count_snapshot_scene_children(scene_snapshots, layer_child_key, orphan_key) do
    Enum.sum(
      Enum.map(scene_snapshots, fn scene ->
        scene
        |> Map.get("layers", [])
        |> sum_nested_count(layer_child_key)
        |> Kernel.+(length(scene[orphan_key] || []))
      end)
    )
  end

  defp materialized_asset_reference_errors(project_id) do
    {invalid_refs, asset_refs} =
      project_id
      |> referenced_asset_refs()
      |> Enum.split_with(&is_nil(&1.asset_id))

    assets_by_id = assets_by_id(Enum.map(asset_refs, & &1.asset_id))

    Enum.map(invalid_refs, &materialized_invalid_asset_reference_error/1) ++
      materialized_missing_or_cross_project_asset_errors(asset_refs, assets_by_id, project_id)
  end

  defp materialized_missing_or_cross_project_asset_errors(asset_refs, assets_by_id, project_id) do
    Enum.flat_map(asset_refs, fn ref ->
      case Map.get(assets_by_id, ref.asset_id) do
        nil ->
          [materialized_missing_asset_reference_error(ref)]

        %Asset{project_id: ^project_id} ->
          []

        %Asset{} = asset ->
          [materialized_cross_project_asset_reference_error(ref, asset)]
      end
    end)
  end

  defp materialized_invalid_asset_reference_error(ref) do
    %{
      "type" => "invalid_asset_after_materialization",
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "raw_asset_id" => ref.raw_asset_id
    }
  end

  defp materialized_missing_asset_reference_error(ref) do
    %{
      "type" => "missing_asset_after_materialization",
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "asset_id" => ref.asset_id
    }
  end

  defp materialized_cross_project_asset_reference_error(ref, asset) do
    %{
      "type" => "cross_project_asset_after_materialization",
      "entity_type" => ref.entity_type,
      "entity_id" => ref.entity_id,
      "field" => ref.field,
      "asset_id" => ref.asset_id,
      "asset_project_id" => asset.project_id
    }
  end
end

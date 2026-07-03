defmodule Storyarn.ProjectTemplates.Audit do
  @moduledoc """
  Validates whether a project can be published as a template.

  This first pass focuses on known migration hazards that can corrupt a cloned
  flow graph. The report shape is JSON-serializable so it can be stored on each
  immutable template version.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  @doc """
  Runs template-publication audit checks for a project.
  """
  @spec run(integer()) :: {:ok, map()} | {:error, map()}
  def run(project_id) do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project_id)

    errors =
      []
      |> Kernel.++(stale_connection_errors(project_id))
      |> Kernel.++(unsafe_subflow_pin_errors(project_id))
      |> Kernel.++(invalid_scene_pin_sheet_ref_errors(project_id))
      |> Kernel.++(invalid_scene_pin_flow_ref_errors(project_id))
      |> Kernel.++(invalid_scene_zone_scene_target_errors(project_id))
      |> Kernel.++(invalid_scene_zone_flow_target_errors(project_id))
      |> Kernel.++(uncopiable_asset_reference_errors(project_id))

    report = %{
      "status" => if(errors == [], do: "passed", else: "failed"),
      "errors" => errors,
      "warnings" => [],
      "entity_counts" => Map.get(snapshot, "entity_counts", %{})
    }

    if errors == [], do: {:ok, report}, else: {:error, report}
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
    active_node_ids_by_flow = active_node_ids_by_flow(project_id)

    project_id
    |> subflow_exit_pin_refs()
    |> Enum.reject(&remappable_exit_pin?(&1, active_node_ids_by_flow))
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
          source_pin: c.source_pin,
          target_node_id: c.target_node_id,
          target_pin: c.target_pin
        }

    Repo.all(query)
  end

  defp active_node_ids_by_flow(project_id) do
    query =
      from n in FlowNode,
        join: f in Flow,
        on: f.id == n.flow_id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(n.deleted_at),
        select: {f.id, n.id}

    query
    |> Repo.all()
    |> Enum.reduce(%{}, fn {flow_id, node_id}, acc ->
      Map.update(acc, flow_id, MapSet.new([node_id]), &MapSet.put(&1, node_id))
    end)
  end

  defp remappable_exit_pin?(%{flow_id: flow_id, source_pin: "exit_" <> old_id_text}, active_node_ids_by_flow) do
    case Integer.parse(old_id_text) do
      {old_id, ""} ->
        active_node_ids = Map.get(active_node_ids_by_flow, flow_id)
        MapSet.member?(active_node_ids, old_id)

      _ ->
        false
    end
  end

  defp subflow_exit_pin_error(ref) do
    %{
      "type" => "unremappable_subflow_exit_pin",
      "flow_id" => ref.flow_id,
      "connection_id" => ref.connection_id,
      "source_node_id" => ref.source_node_id,
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
end

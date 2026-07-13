defmodule Storyarn.Versioning.Builders.SceneBuilder do
  @moduledoc """
  Snapshot builder for scenes.

  Captures scene metadata, layers (sorted by position), and per-layer
  zones, pins, and annotations. Connections reference pins by
  (layer_index, pin_index_within_layer) for portability.
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Repo
  alias Storyarn.Scenes.RoutePoints
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.MaterializationHelpers

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Scene{} = scene) do
    scene =
      Repo.preload(scene, [
        {:layers, [:zones, :pins]},
        :zones,
        :pins,
        :annotations,
        :connections
      ])

    sorted_layers = Enum.sort_by(scene.layers, &{&1.position, &1.id})

    orphan_zones =
      scene.zones |> Enum.filter(&is_nil(&1.layer_id)) |> Enum.sort_by(&{&1.position, &1.id})

    orphan_pins =
      scene.pins |> Enum.filter(&is_nil(&1.layer_id)) |> Enum.sort_by(&{&1.position, &1.id})

    orphan_annotations =
      scene.annotations
      |> Enum.filter(&is_nil(&1.layer_id))
      |> Enum.sort_by(&{&1.position, &1.id})

    # Group annotations by layer_id for snapshot building
    annotations_by_layer = Enum.group_by(scene.annotations, & &1.layer_id)

    # Build pin ID → (layer_index, pin_index) map for connections
    pin_index_map = build_pin_index_map(sorted_layers, orphan_pins)

    layer_snapshots = Enum.map(sorted_layers, &layer_to_snapshot(&1, annotations_by_layer))

    connection_snapshots =
      scene.connections
      |> Enum.filter(&snapshotable_connection?(&1, pin_index_map))
      |> Enum.sort_by(fn conn ->
        {layer_idx, pin_idx} = Map.get(pin_index_map, conn.from_pin_id, {999_999, conn.id})
        {layer_idx, pin_idx, conn.id}
      end)
      |> Enum.map(&connection_to_snapshot(&1, pin_index_map))

    # Collect asset IDs from scene + pins + zone label icons
    pin_asset_ids =
      sorted_layers
      |> Enum.flat_map(fn layer -> Enum.map(layer.pins, & &1.icon_asset_id) end)
      |> Kernel.++(Enum.map(orphan_pins, & &1.icon_asset_id))

    zone_asset_ids =
      sorted_layers
      |> Enum.flat_map(fn layer -> Enum.map(layer.zones, & &1.label_icon_asset_id) end)
      |> Kernel.++(Enum.map(orphan_zones, & &1.label_icon_asset_id))

    asset_ids = [scene.background_asset_id | pin_asset_ids ++ zone_asset_ids]
    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
      "original_id" => scene.id,
      "name" => scene.name,
      "shortcut" => scene.shortcut,
      "description" => scene.description,
      "width" => scene.width,
      "height" => scene.height,
      "default_zoom" => scene.default_zoom,
      "default_center_x" => scene.default_center_x,
      "default_center_y" => scene.default_center_y,
      "scale_unit" => scene.scale_unit,
      "scale_value" => scene.scale_value,
      "fog_color" => scene.fog_color,
      "fog_opacity" => scene.fog_opacity,
      "exploration_display_mode" => scene.exploration_display_mode,
      "background_asset_id" => scene.background_asset_id,
      "layers" => layer_snapshots,
      "orphan_zones" => Enum.map(orphan_zones, &zone_to_snapshot/1),
      "orphan_pins" => Enum.map(orphan_pins, &pin_to_snapshot/1),
      "orphan_annotations" => Enum.map(orphan_annotations, &annotation_to_snapshot/1),
      "connections" => connection_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
    }
  end

  defp build_pin_index_map(sorted_layers, orphan_pins) do
    layer_pin_map =
      sorted_layers
      |> Enum.with_index()
      |> Enum.flat_map(fn {layer, layer_idx} ->
        layer.pins
        |> Enum.sort_by(&{&1.position, &1.id})
        |> Enum.with_index()
        |> Enum.map(fn {pin, pin_idx} -> {pin.id, {layer_idx, pin_idx}} end)
      end)

    orphan_pin_map =
      orphan_pins
      |> Enum.with_index()
      |> Enum.map(fn {pin, pin_idx} -> {pin.id, {-1, pin_idx}} end)

    Map.new(layer_pin_map ++ orphan_pin_map)
  end

  defp layer_to_snapshot(%SceneLayer{} = layer, annotations_by_layer) do
    sorted_zones = Enum.sort_by(layer.zones, &{&1.position, &1.id})
    sorted_pins = Enum.sort_by(layer.pins, &{&1.position, &1.id})

    sorted_annotations =
      annotations_by_layer
      |> Map.get(layer.id, [])
      |> Enum.sort_by(&{&1.position, &1.id})

    %{
      "original_id" => layer.id,
      "name" => layer.name,
      "is_default" => layer.is_default,
      "position" => layer.position,
      "visible" => layer.visible,
      "fog_enabled" => layer.fog_enabled,
      "zones" => Enum.map(sorted_zones, &zone_to_snapshot/1),
      "pins" => Enum.map(sorted_pins, &pin_to_snapshot/1),
      "annotations" => Enum.map(sorted_annotations, &annotation_to_snapshot/1)
    }
  end

  defp zone_to_snapshot(%SceneZone{} = zone) do
    %{
      "original_id" => zone.id,
      "name" => zone.name,
      "shortcut" => zone.shortcut,
      "hidden" => zone.hidden,
      "vertices" => zone.vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "target_type" => zone.target_type,
      "target_id" => zone.target_id,
      "tooltip" => zone.tooltip,
      "position" => zone.position,
      "locked" => zone.locked,
      "action_type" => zone.action_type,
      "action_data" => zone.action_data,
      "label_mode" => zone.label_mode,
      "label_font_size" => zone.label_font_size,
      "label_font_family" => zone.label_font_family,
      "label_font_weight" => zone.label_font_weight,
      "label_font_style" => zone.label_font_style,
      "label_icon_asset_id" => zone.label_icon_asset_id,
      "condition" => zone.condition,
      "condition_effect" => zone.condition_effect,
      "is_walkable" => zone.is_walkable
    }
  end

  defp pin_to_snapshot(%ScenePin{} = pin) do
    %{
      "original_id" => pin.id,
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "opacity" => pin.opacity,
      "label" => pin.label,
      "shortcut" => pin.shortcut,
      "hidden" => pin.hidden,
      "flow_id" => pin.flow_id,
      "tooltip" => pin.tooltip,
      "size" => pin.size,
      "position" => pin.position,
      "locked" => pin.locked,
      "sheet_id" => pin.sheet_id,
      "icon_asset_id" => pin.icon_asset_id,
      "condition" => pin.condition,
      "condition_effect" => pin.condition_effect,
      "is_playable" => pin.is_playable,
      "is_leader" => pin.is_leader
    }
  end

  defp annotation_to_snapshot(%SceneAnnotation{} = annotation) do
    %{
      "original_id" => annotation.id,
      "text" => annotation.text,
      "position_x" => annotation.position_x,
      "position_y" => annotation.position_y,
      "font_size" => annotation.font_size,
      "color" => annotation.color,
      "position" => annotation.position,
      "locked" => annotation.locked
    }
  end

  defp connection_to_snapshot(%SceneConnection{} = conn, pin_index_map) do
    {from_layer_idx, from_pin_idx} = optional_pin_index(pin_index_map, conn.from_pin_id)
    {to_layer_idx, to_pin_idx} = optional_pin_index(pin_index_map, conn.to_pin_id)

    %{
      "original_id" => conn.id,
      "from_layer_index" => from_layer_idx,
      "from_pin_index" => from_pin_idx,
      "to_layer_index" => to_layer_idx,
      "to_pin_index" => to_pin_idx,
      "line_style" => conn.line_style,
      "line_width" => conn.line_width,
      "color" => conn.color,
      "label" => conn.label,
      "bidirectional" => conn.bidirectional,
      "show_label" => conn.show_label,
      "waypoints" => conn.waypoints,
      "from_stop" => conn.from_stop,
      "to_stop" => conn.to_stop,
      "from_pause_ms" => conn.from_pause_ms,
      "to_pause_ms" => conn.to_pause_ms
    }
  end

  defp snapshotable_connection?(conn, pin_index_map) do
    RoutePoints.enough_points?(conn.from_pin_id, conn.to_pin_id, conn.waypoints) and
      optional_pin_in_snapshot?(pin_index_map, conn.from_pin_id) and
      optional_pin_in_snapshot?(pin_index_map, conn.to_pin_id)
  end

  defp optional_pin_in_snapshot?(_pin_index_map, nil), do: true
  defp optional_pin_in_snapshot?(pin_index_map, pin_id), do: Map.has_key?(pin_index_map, pin_id)

  defp optional_pin_index(_pin_index_map, nil), do: {nil, nil}
  defp optional_pin_index(pin_index_map, pin_id), do: Map.fetch!(pin_index_map, pin_id)

  # ========== Restore Snapshot ==========

  @impl true
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    fn ->
      now = MaterializationHelpers.now()

      scene_attrs =
        Map.merge(
          %{
            project_id: project_id,
            name: snapshot["name"],
            shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
            description: snapshot["description"],
            width: snapshot["width"],
            height: snapshot["height"],
            default_zoom: snapshot["default_zoom"],
            default_center_x: snapshot["default_center_x"],
            default_center_y: snapshot["default_center_y"],
            scale_unit: snapshot["scale_unit"],
            scale_value: snapshot["scale_value"],
            fog_color: snapshot_default(snapshot, "fog_color", "#000000"),
            fog_opacity: snapshot_default(snapshot, "fog_opacity", 0.85),
            exploration_display_mode: snapshot_default(snapshot, "exploration_display_mode", "fit"),
            background_asset_id:
              resolve_scene_background_asset(snapshot["background_asset_id"], snapshot, project_id, opts),
            parent_id: MaterializationHelpers.root_parent_id(opts),
            position: MaterializationHelpers.root_position(opts)
          },
          MaterializationHelpers.timestamps(now)
        )

      with {:ok, scene_id} <-
             MaterializationHelpers.insert_one_returning_id(Repo, Scene, scene_attrs),
           {:ok, inserted_layers} <-
             insert_scene_layers(Repo, scene_id, snapshot["layers"] || [], now),
           layer_id_map =
             MaterializationHelpers.build_id_map(snapshot["layers"] || [], inserted_layers),
           {:ok, nested_results} <-
             insert_scene_layer_children(
               Repo,
               scene_id,
               snapshot["layers"] || [],
               inserted_layers,
               snapshot,
               project_id,
               now,
               opts
             ),
           {:ok, orphan_results} <-
             insert_scene_orphan_children(
               Repo,
               scene_id,
               snapshot,
               project_id,
               now,
               opts
             ),
           pin_ids_by_layer =
             Map.put(nested_results.pin_ids_by_layer, -1, orphan_results.pin_ids),
           {:ok, connection_id_map} <-
             insert_scene_connections(
               Repo,
               scene_id,
               snapshot["connections"] || [],
               pin_ids_by_layer,
               now
             ) do
        scene =
          Scene
          |> Repo.get!(scene_id)
          |> Repo.preload(
            [
              :background_asset,
              :connections,
              :annotations,
              :zones,
              [pins: [:icon_asset, sheet: [avatars: :asset]]],
              {:layers, [:zones, :pins]}
            ],
            force: true
          )

        id_maps = %{
          scene: MaterializationHelpers.root_id_map(snapshot, scene_id),
          layer: layer_id_map,
          zone: Map.merge(nested_results.zone_id_map, orphan_results.zone_id_map),
          pin: Map.merge(nested_results.pin_id_map, orphan_results.pin_id_map),
          connection: connection_id_map,
          annotation: Map.merge(nested_results.annotation_id_map, orphan_results.annotation_id_map)
        }

        {scene, id_maps}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {scene, id_maps}} -> {:ok, scene, id_maps}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def restore_snapshot(%Scene{} = scene, snapshot, opts \\ []) do
    Multi.new()
    |> Multi.update(:scene, fn _changes ->
      Scene.update_changeset(scene, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        description: snapshot["description"],
        width: snapshot["width"],
        height: snapshot["height"],
        default_zoom: snapshot["default_zoom"],
        default_center_x: snapshot["default_center_x"],
        default_center_y: snapshot["default_center_y"],
        scale_unit: snapshot["scale_unit"],
        scale_value: snapshot["scale_value"],
        fog_color: snapshot_default(snapshot, "fog_color", "#000000"),
        fog_opacity: snapshot_default(snapshot, "fog_opacity", 0.85),
        background_asset_id:
          resolve_scene_asset(
            snapshot["background_asset_id"],
            snapshot,
            scene.project_id,
            opts
          )
      })
    end)
    |> Multi.delete_all(:delete_connections, fn _changes ->
      from(c in SceneConnection, where: c.scene_id == ^scene.id)
    end)
    |> Multi.delete_all(:delete_annotations, fn _changes ->
      from(a in SceneAnnotation, where: a.scene_id == ^scene.id)
    end)
    |> Multi.delete_all(:delete_pins, fn _changes ->
      from(p in ScenePin, where: p.scene_id == ^scene.id)
    end)
    |> Multi.delete_all(:delete_zones, fn _changes ->
      from(z in SceneZone, where: z.scene_id == ^scene.id)
    end)
    |> Multi.delete_all(:delete_layers, fn _changes ->
      from(l in SceneLayer, where: l.scene_id == ^scene.id)
    end)
    |> Multi.run(:restore_layers, fn repo, _changes ->
      restore_layers(repo, scene.id, snapshot["layers"] || [], snapshot, scene.project_id, opts)
    end)
    |> Multi.run(:restore_orphans, fn repo, _changes ->
      restore_orphan_entities(repo, scene.id, snapshot, scene.project_id, opts)
    end)
    |> Multi.run(:restore_connections, fn repo,
                                          %{
                                            restore_layers: layer_data,
                                            restore_orphans: orphan_data
                                          } ->
      restore_connections(
        repo,
        scene.id,
        snapshot["connections"] || [],
        Map.put(layer_data, -1, %{pin_ids: orphan_data.pin_ids})
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{scene: updated_scene}} ->
        {:ok,
         Repo.preload(
           updated_scene,
           [
             :background_asset,
             :connections,
             :annotations,
             :zones,
             [pins: [:icon_asset, sheet: [avatars: :asset]]],
             {:layers, [:zones, :pins]}
           ],
           force: true
         )}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_layers(_repo, _scene_id, [], _snapshot, _project_id, _opts), do: {:ok, %{}}

  defp restore_layers(repo, scene_id, layers_data, snapshot, project_id, opts) do
    now = MaterializationHelpers.now()

    layer_data =
      layers_data
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {layer_data, layer_idx}, acc ->
        {layer_id, pin_ids} =
          restore_single_layer(
            repo,
            scene_id,
            layer_data,
            layer_idx,
            now,
            snapshot,
            project_id,
            opts
          )

        Map.put(acc, layer_idx, %{layer_id: layer_id, pin_ids: pin_ids})
      end)

    {:ok, layer_data}
  end

  defp restore_single_layer(repo, scene_id, layer_data, layer_idx, now, snapshot, project_id, opts) do
    layer_id = insert_layer(repo, scene_id, layer_data, layer_idx, now)
    insert_layer_zones(repo, scene_id, layer_id, layer_data["zones"] || [], now, snapshot, project_id, opts)

    pin_ids =
      insert_layer_pins(
        repo,
        scene_id,
        layer_id,
        layer_data["pins"] || [],
        now,
        snapshot,
        project_id,
        opts
      )

    insert_layer_annotations(repo, scene_id, layer_id, layer_data["annotations"] || [], now)
    {layer_id, pin_ids}
  end

  defp insert_layer(repo, scene_id, layer_data, layer_idx, now) do
    attrs = %{
      scene_id: scene_id,
      name: layer_data["name"],
      is_default: layer_data["is_default"] || false,
      position: layer_data["position"] || layer_idx,
      visible: Map.get(layer_data, "visible", true),
      fog_enabled: layer_data["fog_enabled"] || false,
      inserted_at: now,
      updated_at: now
    }

    case repo.insert_all(SceneLayer, [attrs], returning: [:id]) do
      {1, [%{id: layer_id}]} -> layer_id
      {0, _} -> raise "Failed to insert scene layer during restore"
    end
  end

  defp insert_layer_zones(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: :ok

  defp insert_layer_zones(repo, scene_id, layer_id, zones_data, now, snapshot, project_id, opts) do
    Enum.each(zones_data, fn zone_data ->
      attrs = build_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts)
      insert_single!(repo, SceneZone, attrs, "scene zone")
    end)
  end

  defp build_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    zone_data
    |> zone_base_attrs()
    |> Map.merge(%{
      scene_id: scene_id,
      layer_id: layer_id,
      label_icon_asset_id: resolve_scene_asset(zone_data["label_icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp zone_base_attrs(d) do
    normalized_behavior = zone_behavior_attrs(d)

    Map.merge(
      %{
        name: d["name"],
        shortcut: d["shortcut"],
        hidden: d["hidden"] || false,
        vertices: d["vertices"],
        fill_color: d["fill_color"],
        border_color: d["border_color"],
        tooltip: d["tooltip"],
        condition: d["condition"]
      },
      Map.merge(zone_defaulted_attrs(d), normalized_behavior)
    )
  end

  defp zone_defaulted_attrs(d) do
    d
    |> zone_style_defaults()
    |> Map.merge(zone_label_defaults(d))
  end

  defp zone_style_defaults(d) do
    %{
      border_width: d["border_width"] || 2,
      border_style: d["border_style"] || "solid",
      opacity: d["opacity"] || 0.3,
      position: d["position"] || 0,
      locked: d["locked"] || false
    }
  end

  defp zone_label_defaults(d) do
    %{
      label_mode: d["label_mode"] || "text",
      label_font_size: d["label_font_size"] || 12,
      label_font_family: d["label_font_family"] || "system",
      label_font_weight: d["label_font_weight"] || "600",
      label_font_style: d["label_font_style"] || "normal",
      label_icon_asset_id: d["label_icon_asset_id"]
    }
  end

  defp zone_behavior_attrs(d) do
    action_type = normalize_zone_action_type(d["action_type"])
    action_data = normalize_zone_action_data(action_type, d["action_data"])
    {target_type, target_id} = normalize_zone_target(d["target_type"], d["target_id"])
    convert_to_walkable? = legacy_walkable_only?(action_type, action_data, target_type, target_id, d["is_walkable"])

    action_type = if convert_to_walkable?, do: "walkable", else: action_type

    %{
      target_type: if(action_type == "action", do: target_type),
      target_id: if(action_type == "action", do: target_id),
      action_type: action_type,
      action_data: if(action_type == "walkable", do: %{}, else: action_data),
      condition_effect: d["condition_effect"] || "hide",
      is_walkable: action_type == "walkable"
    }
  end

  defp normalize_zone_action_type(type) when type in ["action", "walkable", "display", "collection"], do: type
  defp normalize_zone_action_type(_type), do: "action"

  defp normalize_zone_action_data("action", %{"assignments" => assignments} = data) when is_list(assignments), do: data
  defp normalize_zone_action_data("action", _), do: %{"assignments" => []}

  defp normalize_zone_action_data("display", %{"variable_ref" => ref} = data) when is_binary(ref) do
    Map.put_new(data, "display_mode", "value")
  end

  defp normalize_zone_action_data("display", _), do: %{"variable_ref" => "", "display_mode" => "value"}

  defp normalize_zone_action_data("collection", %{"items" => items} = data) when is_list(items), do: data
  defp normalize_zone_action_data("collection", _), do: %{"items" => []}
  defp normalize_zone_action_data("walkable", _), do: %{}
  defp normalize_zone_action_data(_type, data) when is_map(data), do: data
  defp normalize_zone_action_data(_type, _), do: %{}

  defp normalize_zone_target(target_type, target_id) when target_type in ["flow", "scene"] and is_integer(target_id),
    do: {target_type, target_id}

  defp normalize_zone_target(_target_type, _target_id), do: {nil, nil}

  defp legacy_walkable_only?("action", action_data, nil, nil, true) do
    assignments = action_data["assignments"] || []
    assignments == []
  end

  defp legacy_walkable_only?(_action_type, _action_data, _target_type, _target_id, _is_walkable), do: false

  defp insert_single!(repo, schema, attrs, label) do
    case repo.insert_all(schema, [attrs]) do
      {1, _} -> :ok
      {0, _} -> raise "Failed to insert #{label} during restore"
    end
  end

  defp insert_layer_pins(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: []

  defp insert_layer_pins(repo, scene_id, layer_id, pins_data, now, snapshot, project_id, opts) do
    Enum.map(pins_data, fn pin_data ->
      attrs = build_pin_attrs(pin_data, scene_id, layer_id, now, snapshot, project_id, opts)

      case repo.insert_all(ScenePin, [attrs], returning: [:id]) do
        {1, [%{id: pin_id}]} -> pin_id
        {0, _} -> raise "Failed to insert scene pin during restore"
      end
    end)
  end

  defp build_pin_attrs(pin_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    pin_data
    |> pin_base_attrs()
    |> Map.merge(%{
      scene_id: scene_id,
      layer_id: layer_id,
      sheet_id: resolve_scene_sheet_id(pin_data["sheet_id"], project_id, opts),
      icon_asset_id: resolve_scene_asset(pin_data["icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp pin_base_attrs(d) do
    Map.merge(
      %{
        position_x: d["position_x"],
        position_y: d["position_y"],
        icon: d["icon"],
        color: d["color"],
        label: d["label"],
        shortcut: d["shortcut"],
        hidden: d["hidden"] || false,
        flow_id: d["flow_id"],
        tooltip: d["tooltip"],
        condition: d["condition"]
      },
      pin_defaulted_attrs(d)
    )
  end

  defp pin_defaulted_attrs(d) do
    Map.merge(
      %{
        pin_type: d["pin_type"] || "location",
        opacity: d["opacity"] || 1.0,
        size: d["size"] || "md",
        position: d["position"] || 0,
        locked: d["locked"] || false
      },
      pin_action_defaults(d)
    )
  end

  defp pin_action_defaults(d) do
    %{
      condition_effect: d["condition_effect"] || "hide",
      is_playable: d["is_playable"] || false,
      is_leader: d["is_leader"] || false
    }
  end

  defp insert_layer_annotations(_repo, _scene_id, _layer_id, [], _now), do: :ok

  defp insert_layer_annotations(repo, scene_id, layer_id, annotations_data, now) do
    Enum.each(annotations_data, fn ann_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        text: ann_data["text"],
        position_x: ann_data["position_x"],
        position_y: ann_data["position_y"],
        font_size: ann_data["font_size"] || "md",
        color: ann_data["color"],
        position: ann_data["position"] || 0,
        locked: ann_data["locked"] || false,
        inserted_at: now,
        updated_at: now
      }

      insert_single!(repo, SceneAnnotation, attrs, "scene annotation")
    end)
  end

  defp restore_connections(_repo, _scene_id, [], _layer_data), do: {:ok, 0}

  defp restore_connections(repo, scene_id, connections_data, layer_data) do
    now = MaterializationHelpers.now()

    # Build indexed maps for O(1) pin lookups
    pin_index_maps =
      Map.new(layer_data, fn {layer_idx, %{pin_ids: pin_ids}} ->
        indexed = pin_ids |> Enum.with_index() |> Map.new(fn {id, idx} -> {idx, id} end)
        {layer_idx, %{map: indexed, count: length(pin_ids)}}
      end)

    entries =
      connections_data
      |> Enum.filter(&restorable_connection?(&1, pin_index_maps))
      |> Enum.map(fn conn ->
        %{
          scene_id: scene_id,
          from_pin_id: lookup_snapshot_pin(pin_index_maps, conn["from_layer_index"], conn["from_pin_index"]),
          to_pin_id: lookup_snapshot_pin(pin_index_maps, conn["to_layer_index"], conn["to_pin_index"]),
          line_style: conn["line_style"] || "solid",
          line_width: conn["line_width"] || 2,
          color: conn["color"],
          label: conn["label"],
          bidirectional: Map.get(conn, "bidirectional", true),
          show_label: Map.get(conn, "show_label", true),
          waypoints: conn["waypoints"] || [],
          from_stop: Map.get(conn, "from_stop", true),
          to_stop: Map.get(conn, "to_stop", true),
          from_pause_ms: conn["from_pause_ms"],
          to_pause_ms: conn["to_pause_ms"],
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = repo.insert_all(SceneConnection, entries)
    {:ok, count}
  end

  defp insert_scene_layers(_repo, _scene_id, [], _now), do: {:ok, []}

  defp insert_scene_layers(repo, scene_id, layers_data, now) do
    entries =
      layers_data
      |> Enum.with_index()
      |> Enum.map(fn {layer_data, layer_idx} ->
        Map.merge(
          %{
            scene_id: scene_id,
            name: layer_data["name"],
            is_default: layer_data["is_default"] || false,
            position: layer_data["position"] || layer_idx,
            visible: Map.get(layer_data, "visible", true),
            fog_enabled: layer_data["fog_enabled"] || false
          },
          MaterializationHelpers.timestamps(now)
        )
      end)

    MaterializationHelpers.insert_all_returning(repo, SceneLayer, entries, [:id])
  end

  defp insert_scene_layer_children(repo, scene_id, layers_data, inserted_layers, snapshot, project_id, now, opts) do
    layers_data
    |> Enum.zip(inserted_layers)
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, %{zone_id_map: %{}, pin_id_map: %{}, annotation_id_map: %{}, pin_ids_by_layer: %{}}},
      fn {{layer_data, inserted_layer}, layer_idx}, {:ok, acc} ->
        with {:ok, zone_inserted} <-
               insert_layer_zones_with_ids(
                 repo,
                 scene_id,
                 inserted_layer.id,
                 layer_data["zones"] || [],
                 now,
                 snapshot,
                 project_id,
                 opts
               ),
             {:ok, pin_inserted} <-
               insert_layer_pins_with_ids(
                 repo,
                 scene_id,
                 inserted_layer.id,
                 layer_data["pins"] || [],
                 now,
                 snapshot,
                 project_id,
                 opts
               ),
             {:ok, annotation_inserted} <-
               insert_layer_annotations_with_ids(
                 repo,
                 scene_id,
                 inserted_layer.id,
                 layer_data["annotations"] || [],
                 now
               ) do
          updated =
            acc
            |> Map.update!(
              :zone_id_map,
              &Map.merge(
                &1,
                MaterializationHelpers.build_id_map(layer_data["zones"] || [], zone_inserted)
              )
            )
            |> Map.update!(
              :pin_id_map,
              &Map.merge(
                &1,
                MaterializationHelpers.build_id_map(layer_data["pins"] || [], pin_inserted)
              )
            )
            |> Map.update!(
              :annotation_id_map,
              &Map.merge(
                &1,
                MaterializationHelpers.build_id_map(
                  layer_data["annotations"] || [],
                  annotation_inserted
                )
              )
            )
            |> put_layer_pin_ids(layer_idx, pin_inserted)

          {:cont, {:ok, updated}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
  end

  defp insert_scene_orphan_children(repo, scene_id, snapshot, project_id, now, opts) do
    with {:ok, zone_inserted} <-
           insert_layer_zones_with_ids(
             repo,
             scene_id,
             nil,
             snapshot["orphan_zones"] || [],
             now,
             snapshot,
             project_id,
             opts
           ),
         {:ok, pin_inserted} <-
           insert_layer_pins_with_ids(
             repo,
             scene_id,
             nil,
             snapshot["orphan_pins"] || [],
             now,
             snapshot,
             project_id,
             opts
           ),
         {:ok, annotation_inserted} <-
           insert_layer_annotations_with_ids(
             repo,
             scene_id,
             nil,
             snapshot["orphan_annotations"] || [],
             now
           ) do
      {:ok,
       %{
         zone_id_map: MaterializationHelpers.build_id_map(snapshot["orphan_zones"] || [], zone_inserted),
         pin_id_map: MaterializationHelpers.build_id_map(snapshot["orphan_pins"] || [], pin_inserted),
         annotation_id_map:
           MaterializationHelpers.build_id_map(
             snapshot["orphan_annotations"] || [],
             annotation_inserted
           ),
         pin_ids: Enum.map(pin_inserted, & &1.id)
       }}
    end
  end

  defp inserted_pin_ids(pin_rows), do: Enum.map(pin_rows, & &1.id)

  defp put_layer_pin_ids(results, layer_idx, pin_rows) do
    Map.update!(results, :pin_ids_by_layer, &Map.put(&1, layer_idx, inserted_pin_ids(pin_rows)))
  end

  defp restore_orphan_entities(repo, scene_id, snapshot, project_id, opts) do
    now = MaterializationHelpers.now()

    with :ok <- insert_layer_zones(repo, scene_id, nil, snapshot["orphan_zones"] || [], now, snapshot, project_id, opts),
         orphan_pin_ids =
           insert_layer_pins(
             repo,
             scene_id,
             nil,
             snapshot["orphan_pins"] || [],
             now,
             snapshot,
             project_id,
             opts
           ),
         :ok <-
           insert_layer_annotations(
             repo,
             scene_id,
             nil,
             snapshot["orphan_annotations"] || [],
             now
           ) do
      {:ok, %{pin_ids: orphan_pin_ids}}
    end
  end

  defp insert_layer_zones_with_ids(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: {:ok, []}

  defp insert_layer_zones_with_ids(repo, scene_id, layer_id, zones_data, now, snapshot, project_id, opts) do
    entries =
      Enum.map(zones_data, fn zone_data ->
        build_materialized_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts)
      end)

    MaterializationHelpers.insert_all_returning(repo, SceneZone, entries, [:id])
  end

  defp build_materialized_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    preserve_external_refs? = MaterializationHelpers.preserve_external_refs?(opts)
    attrs = zone_base_attrs(zone_data)

    Map.merge(attrs, %{
      scene_id: scene_id,
      layer_id: layer_id,
      target_type: materialized_zone_target_type(attrs, zone_data, preserve_external_refs?),
      target_id: materialized_zone_target_id(attrs, zone_data, preserve_external_refs?),
      label_icon_asset_id: resolve_scene_asset(zone_data["label_icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp materialized_zone_target_type(%{action_type: "action"} = attrs, zone_data, true) do
    {target_type, _target_id} = normalize_zone_target(zone_data["target_type"], zone_data["target_id"])
    target_type || attrs.target_type
  end

  defp materialized_zone_target_type(attrs, _zone_data, _preserve_external_refs?), do: attrs.target_type

  defp materialized_zone_target_id(%{action_type: "action"} = attrs, zone_data, true) do
    {_target_type, target_id} = normalize_zone_target(zone_data["target_type"], zone_data["target_id"])
    target_id || attrs.target_id
  end

  defp materialized_zone_target_id(attrs, _zone_data, _preserve_external_refs?), do: attrs.target_id

  defp insert_layer_pins_with_ids(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: {:ok, []}

  defp insert_layer_pins_with_ids(repo, scene_id, layer_id, pins_data, now, snapshot, project_id, opts) do
    entries =
      Enum.map(pins_data, fn pin_data ->
        build_materialized_pin_attrs(
          pin_data,
          scene_id,
          layer_id,
          now,
          snapshot,
          project_id,
          opts
        )
      end)

    MaterializationHelpers.insert_all_returning(repo, ScenePin, entries, [:id])
  end

  defp build_materialized_pin_attrs(pin_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    preserve_external_refs? = MaterializationHelpers.preserve_external_refs?(opts)

    pin_data
    |> pin_base_attrs()
    |> Map.merge(%{
      scene_id: scene_id,
      layer_id: layer_id,
      flow_id: if(preserve_external_refs?, do: pin_data["flow_id"]),
      sheet_id:
        if(preserve_external_refs?,
          do: resolve_scene_sheet_id(pin_data["sheet_id"], project_id, opts)
        ),
      icon_asset_id: resolve_scene_asset(pin_data["icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_layer_annotations_with_ids(_repo, _scene_id, _layer_id, [], _now), do: {:ok, []}

  defp insert_layer_annotations_with_ids(repo, scene_id, layer_id, annotations_data, now) do
    entries =
      Enum.map(annotations_data, fn ann_data ->
        Map.merge(
          %{
            scene_id: scene_id,
            layer_id: layer_id,
            text: ann_data["text"],
            position_x: ann_data["position_x"],
            position_y: ann_data["position_y"],
            font_size: ann_data["font_size"] || "md",
            color: ann_data["color"],
            position: ann_data["position"] || 0,
            locked: ann_data["locked"] || false
          },
          MaterializationHelpers.timestamps(now)
        )
      end)

    MaterializationHelpers.insert_all_returning(repo, SceneAnnotation, entries, [:id])
  end

  defp insert_scene_connections(_repo, _scene_id, [], _pin_ids_by_layer, _now), do: {:ok, %{}}

  defp insert_scene_connections(repo, scene_id, connections_data, pin_ids_by_layer, now) do
    {entries, snapshots} =
      Enum.reduce(connections_data, {[], []}, fn conn, {acc_entries, acc_snapshots} ->
        from_pin_id =
          lookup_scene_pin(pin_ids_by_layer, conn["from_layer_index"], conn["from_pin_index"])

        to_pin_id =
          lookup_scene_pin(pin_ids_by_layer, conn["to_layer_index"], conn["to_pin_index"])

        if RoutePoints.enough_points?(from_pin_id, to_pin_id, conn["waypoints"] || []) do
          entry =
            Map.merge(
              %{
                scene_id: scene_id,
                from_pin_id: from_pin_id,
                to_pin_id: to_pin_id,
                line_style: conn["line_style"] || "solid",
                line_width: conn["line_width"] || 2,
                color: conn["color"],
                label: conn["label"],
                bidirectional: Map.get(conn, "bidirectional", true),
                show_label: Map.get(conn, "show_label", true),
                waypoints: conn["waypoints"] || [],
                from_stop: Map.get(conn, "from_stop", true),
                to_stop: Map.get(conn, "to_stop", true),
                from_pause_ms: conn["from_pause_ms"],
                to_pause_ms: conn["to_pause_ms"]
              },
              MaterializationHelpers.timestamps(now)
            )

          {[entry | acc_entries], [conn | acc_snapshots]}
        else
          {acc_entries, acc_snapshots}
        end
      end)

    entries = Enum.reverse(entries)
    snapshots = Enum.reverse(snapshots)

    case MaterializationHelpers.insert_all_returning(repo, SceneConnection, entries, [:id]) do
      {:ok, inserted_connections} ->
        {:ok, MaterializationHelpers.build_id_map(snapshots, inserted_connections)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lookup_scene_pin(_pin_ids_by_layer, nil, nil), do: nil

  defp lookup_scene_pin(pin_ids_by_layer, layer_idx, pin_idx) do
    pin_ids_by_layer
    |> Map.get(layer_idx, [])
    |> Enum.at(pin_idx)
  end

  defp restorable_connection?(conn, pin_index_maps) do
    refs_valid? =
      restorable_pin_ref?(pin_index_maps, conn["from_layer_index"], conn["from_pin_index"]) and
        restorable_pin_ref?(pin_index_maps, conn["to_layer_index"], conn["to_pin_index"])

    if refs_valid? do
      from_pin_id = lookup_snapshot_pin(pin_index_maps, conn["from_layer_index"], conn["from_pin_index"])
      to_pin_id = lookup_snapshot_pin(pin_index_maps, conn["to_layer_index"], conn["to_pin_index"])

      RoutePoints.enough_points?(from_pin_id, to_pin_id, conn["waypoints"] || [])
    else
      false
    end
  end

  defp restorable_pin_ref?(_pin_index_maps, nil, nil), do: true

  defp restorable_pin_ref?(pin_index_maps, layer_idx, pin_idx) when is_integer(pin_idx) do
    case Map.get(pin_index_maps, layer_idx) do
      nil -> false
      layer -> pin_idx >= 0 and pin_idx < layer.count
    end
  end

  defp restorable_pin_ref?(_pin_index_maps, _layer_idx, _pin_idx), do: false

  defp lookup_snapshot_pin(_pin_index_maps, nil, nil), do: nil

  defp lookup_snapshot_pin(pin_index_maps, layer_idx, pin_idx) do
    pin_index_maps
    |> Map.fetch!(layer_idx)
    |> Map.fetch!(:map)
    |> Map.fetch!(pin_idx)
  end

  defp resolve_scene_background_asset(asset_id, snapshot, project_id, opts) do
    resolve_scene_asset(asset_id, snapshot, project_id, opts)
  end

  defp resolve_scene_asset(_asset_id, _snapshot, _project_id, opts) when not is_list(opts), do: nil

  defp resolve_scene_asset(asset_id, snapshot, project_id, opts) do
    case scene_asset_mode(opts) do
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

  defp scene_asset_mode(opts) do
    cond do
      mode = Keyword.get(opts, :asset_mode) ->
        mode

      MaterializationHelpers.preserve_external_refs?(opts) ->
        :reuse

      true ->
        :drop
    end
  end

  defp snapshot_default(snapshot, key, default), do: Map.get(snapshot, key) || default

  # ========== Diff Snapshots ==========

  @layer_compare_fields ~w(name is_default visible fog_enabled)
  @pin_compare_fields ~w(pin_type icon color opacity label shortcut hidden size flow_id tooltip sheet_id icon_asset_id condition condition_effect locked)
  @zone_compare_fields ~w(name shortcut hidden vertices fill_color border_color border_width border_style opacity target_type target_id tooltip action_type action_data label_mode label_font_size label_font_family label_font_weight label_font_style label_icon_asset_id condition condition_effect locked)
  @annotation_compare_fields ~w(text font_size color locked)
  @connection_compare_fields ~w(line_style line_width color label bidirectional show_label waypoints from_stop to_stop from_pause_ms to_pause_ms)

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    []
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "name",
      :property,
      dgettext("scenes", "Renamed scene")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "shortcut",
      :property,
      dgettext("scenes", "Changed shortcut")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "description",
      :property,
      dgettext("scenes", "Changed description")
    )
    |> DiffHelpers.check_field_group_change(
      old_snapshot,
      new_snapshot,
      ~w(width height),
      :property,
      dgettext("scenes", "Changed dimensions")
    )
    |> DiffHelpers.check_field_group_change(
      old_snapshot,
      new_snapshot,
      ~w(default_zoom default_center_x default_center_y),
      :property,
      dgettext("scenes", "Changed default view")
    )
    |> DiffHelpers.check_field_group_change(
      old_snapshot,
      new_snapshot,
      ~w(scale_unit scale_value),
      :property,
      dgettext("scenes", "Changed scale settings")
    )
    |> DiffHelpers.check_field_group_change(
      old_snapshot,
      new_snapshot,
      ~w(fog_color fog_opacity),
      :property,
      dgettext("scenes", "Changed fog design")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "background_asset_id",
      :property,
      dgettext("scenes", "Changed background")
    )
    |> diff_orphan_entities(old_snapshot, new_snapshot)
    |> diff_layers_and_connections(
      old_snapshot["layers"] || [],
      new_snapshot["layers"] || [],
      old_snapshot["orphan_pins"] || [],
      new_snapshot["orphan_pins"] || [],
      old_snapshot["connections"] || [],
      new_snapshot["connections"] || []
    )
    |> Enum.reverse()
  end

  defp diff_orphan_entities(changes, old_snapshot, new_snapshot) do
    root = scene_root_container()

    changes
    |> diff_nested(
      old_snapshot["orphan_pins"] || [],
      new_snapshot["orphan_pins"] || [],
      :pin,
      @pin_compare_fields,
      &pin_detail(&1, &2, root)
    )
    |> diff_nested(
      old_snapshot["orphan_zones"] || [],
      new_snapshot["orphan_zones"] || [],
      :zone,
      @zone_compare_fields,
      &zone_detail(&1, &2, root)
    )
    |> diff_nested(
      old_snapshot["orphan_annotations"] || [],
      new_snapshot["orphan_annotations"] || [],
      :annotation,
      @annotation_compare_fields,
      &annotation_detail(&1, &2, root)
    )
  end

  defp diff_layers_and_connections(
         changes,
         old_layers,
         new_layers,
         old_orphan_pins,
         new_orphan_pins,
         old_conns,
         new_conns
       ) do
    {matched, added, removed} =
      DiffHelpers.match_by_keys(old_layers, new_layers, [& &1["position"]])

    # Build pin index remapping from matched layers so that connection
    # comparison uses semantic pin identity, not raw positional indices.
    pin_index_remap =
      build_pin_index_remap(matched, old_layers, new_layers, old_orphan_pins, new_orphan_pins)

    changes
    |> append_items(added, :layer, :added, &layer_detail(:added, &1))
    |> append_items(removed, :layer, :removed, &layer_detail(:removed, &1))
    |> diff_matched_layers(matched)
    |> diff_connections(old_conns, new_conns, pin_index_remap)
  end

  defp build_pin_index_remap(matched_layers, old_layers, new_layers, old_orphan_pins, new_orphan_pins) do
    old_layer_index = old_layers |> Enum.with_index() |> Map.new()
    new_layer_index = new_layers |> Enum.with_index() |> Map.new()

    matched_layer_remap =
      Enum.reduce(matched_layers, %{}, fn {old_layer, new_layer}, remap ->
        old_layer_idx = Map.get(old_layer_index, old_layer)
        new_layer_idx = Map.get(new_layer_index, new_layer)

        old_pins = old_layer["pins"] || []
        new_pins = new_layer["pins"] || []

        old_pin_index = old_pins |> Enum.with_index() |> Map.new()
        new_pin_index = new_pins |> Enum.with_index() |> Map.new()

        {matched_pins, _added, _removed} =
          DiffHelpers.match_by_keys(old_pins, new_pins, [& &1["position"]])

        Enum.reduce(matched_pins, remap, fn {old_pin, new_pin}, acc ->
          old_pin_idx = Map.get(old_pin_index, old_pin)
          new_pin_idx = Map.get(new_pin_index, new_pin)

          Map.put(acc, {old_layer_idx, old_pin_idx}, {new_layer_idx, new_pin_idx})
        end)
      end)

    old_orphan_index = old_orphan_pins |> Enum.with_index() |> Map.new()
    new_orphan_index = new_orphan_pins |> Enum.with_index() |> Map.new()

    {matched_orphans, _added, _removed} =
      DiffHelpers.match_by_keys(old_orphan_pins, new_orphan_pins, [& &1["position"]])

    Enum.reduce(matched_orphans, matched_layer_remap, fn {old_pin, new_pin}, remap ->
      Map.put(
        remap,
        {-1, Map.get(old_orphan_index, old_pin)},
        {-1, Map.get(new_orphan_index, new_pin)}
      )
    end)
  end

  defp diff_matched_layers(changes, []), do: changes

  defp diff_matched_layers(changes, matched_pairs) do
    Enum.reduce(matched_pairs, changes, fn {old_layer, new_layer}, acc ->
      layer_props_changed =
        DiffHelpers.fields_differ?(old_layer, new_layer, @layer_compare_fields)

      acc
      |> maybe_add_layer_modified(layer_props_changed, new_layer)
      |> diff_nested(
        old_layer["pins"] || [],
        new_layer["pins"] || [],
        :pin,
        @pin_compare_fields,
        &pin_detail(&1, &2, new_layer)
      )
      |> diff_nested(
        old_layer["zones"] || [],
        new_layer["zones"] || [],
        :zone,
        @zone_compare_fields,
        &zone_detail(&1, &2, new_layer)
      )
      |> diff_nested(
        old_layer["annotations"] || [],
        new_layer["annotations"] || [],
        :annotation,
        @annotation_compare_fields,
        &annotation_detail(&1, &2, new_layer)
      )
    end)
  end

  defp maybe_add_layer_modified(changes, false, _layer), do: changes

  defp maybe_add_layer_modified(changes, true, layer) do
    name = layer["name"] || ""
    detail = dgettext("scenes", "Modified layer \"%{name}\"", name: name)
    [%{category: :layer, action: :modified, detail: detail} | changes]
  end

  defp diff_nested(changes, old_items, new_items, category, compare_fields, detail_fn) do
    {matched, added, removed} =
      DiffHelpers.match_by_keys(old_items, new_items, [& &1["position"]])

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, compare_fields)
      end)

    changes
    |> append_items(added, category, :added, &detail_fn.(:added, &1))
    |> append_items(removed, category, :removed, &detail_fn.(:removed, &1))
    |> append_modified_items(modified, category, &detail_fn.(:modified, &1))
  end

  defp diff_connections(changes, old_conns, new_conns, pin_index_remap) do
    # Remap old connections to new index space so that pin reordering
    # doesn't produce phantom connection adds/removes.
    # Connections referencing removed pins get unique sentinel indexes
    # so they won't falsely match new connections at the same raw index.
    remapped_old_conns =
      old_conns
      |> Enum.with_index()
      |> Enum.map(fn {conn, idx} ->
        conn
        |> Map.put("__diff_index", idx)
        |> remap_connection_endpoint("from", pin_index_remap, idx)
        |> remap_connection_endpoint("to", pin_index_remap, idx)
      end)

    indexed_new_conns =
      new_conns
      |> Enum.with_index()
      |> Enum.map(fn {conn, idx} -> Map.put(conn, "__diff_index", idx) end)

    original_id_key_fn = fn conn ->
      if conn["original_id"], do: {:original_id, conn["original_id"]}
    end

    endpoint_key_fn = fn conn ->
      {conn["from_layer_index"], conn["from_pin_index"], conn["to_layer_index"], conn["to_pin_index"]}
    end

    free_route_key_fn = fn conn ->
      if free_route?(conn), do: {:free_route, conn["__diff_index"]}
    end

    {matched, added, removed} =
      DiffHelpers.match_by_keys(remapped_old_conns, indexed_new_conns, [
        original_id_key_fn,
        free_route_key_fn,
        endpoint_key_fn
      ])

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, @connection_compare_fields)
      end)

    changes
    |> append_items(added, :connection, :added, fn _conn ->
      dgettext("scenes", "Added connection")
    end)
    |> append_items(removed, :connection, :removed, fn _conn ->
      dgettext("scenes", "Removed connection")
    end)
    |> append_modified_items(modified, :connection, fn _new ->
      dgettext("scenes", "Modified connection")
    end)
  end

  defp remap_connection_endpoint(conn, prefix, pin_index_remap, idx) do
    layer_key = "#{prefix}_layer_index"
    pin_key = "#{prefix}_pin_index"
    layer_idx = conn[layer_key]
    pin_idx = conn[pin_key]

    {new_layer_idx, new_pin_idx} = remap_optional_connection_endpoint(layer_idx, pin_idx, pin_index_remap, prefix, idx)

    conn
    |> Map.put(layer_key, new_layer_idx)
    |> Map.put(pin_key, new_pin_idx)
  end

  defp remap_optional_connection_endpoint(nil, nil, _pin_index_remap, _prefix, _idx), do: {nil, nil}

  defp remap_optional_connection_endpoint(layer_idx, pin_idx, pin_index_remap, prefix, idx) do
    Map.get(pin_index_remap, {layer_idx, pin_idx}, {{:removed, prefix, idx}, {:removed, prefix, idx}})
  end

  defp free_route?(conn) do
    is_nil(conn["from_layer_index"]) and is_nil(conn["from_pin_index"]) and
      is_nil(conn["to_layer_index"]) and is_nil(conn["to_pin_index"])
  end

  # Generic helpers for building change lists

  defp append_items(changes, [], _category, _action, _detail_fn), do: changes

  defp append_items(changes, items, category, action, detail_fn) do
    Enum.reduce(items, changes, fn item, acc ->
      [%{category: category, action: action, detail: detail_fn.(item)} | acc]
    end)
  end

  defp append_modified_items(changes, [], _category, _detail_fn), do: changes

  defp append_modified_items(changes, modified_pairs, category, detail_fn) do
    Enum.reduce(modified_pairs, changes, fn {_old, new}, acc ->
      [%{category: category, action: :modified, detail: detail_fn.(new)} | acc]
    end)
  end

  # Detail formatters

  defp layer_detail(:added, layer), do: dgettext("scenes", "Added layer \"%{name}\"", name: layer["name"] || "")

  defp layer_detail(:removed, layer), do: dgettext("scenes", "Removed layer \"%{name}\"", name: layer["name"] || "")

  defp pin_detail(action, pin, layer) do
    label = pin["label"] || ""
    layer_name = layer["name"] || ""

    case action do
      :added ->
        dgettext("scenes", ~s(Added pin "%{label}" in layer "%{layer}"),
          label: label,
          layer: layer_name
        )

      :removed ->
        dgettext("scenes", ~s(Removed pin "%{label}" in layer "%{layer}"),
          label: label,
          layer: layer_name
        )

      :modified ->
        dgettext("scenes", ~s(Modified pin "%{label}" in layer "%{layer}"),
          label: label,
          layer: layer_name
        )
    end
  end

  defp zone_detail(action, zone, layer) do
    name = zone["name"] || ""
    layer_name = layer["name"] || ""

    case action do
      :added ->
        dgettext("scenes", ~s(Added zone "%{name}" in layer "%{layer}"),
          name: name,
          layer: layer_name
        )

      :removed ->
        dgettext("scenes", ~s(Removed zone "%{name}" in layer "%{layer}"),
          name: name,
          layer: layer_name
        )

      :modified ->
        dgettext("scenes", ~s(Modified zone "%{name}" in layer "%{layer}"),
          name: name,
          layer: layer_name
        )
    end
  end

  defp annotation_detail(action, _annotation, layer) do
    layer_name = layer["name"] || ""

    case action do
      :added ->
        dgettext("scenes", "Added annotation in layer \"%{layer}\"", layer: layer_name)

      :removed ->
        dgettext("scenes", "Removed annotation in layer \"%{layer}\"", layer: layer_name)

      :modified ->
        dgettext("scenes", "Modified annotation in layer \"%{layer}\"", layer: layer_name)
    end
  end

  # ========== Scan References ==========

  @impl true
  def scan_references(snapshot) do
    refs = []

    refs =
      maybe_add_ref(
        refs,
        :asset,
        snapshot["background_asset_id"],
        dgettext("scenes", "Background image")
      )

    refs =
      (snapshot["layers"] || [])
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {layer, layer_idx}, acc ->
        acc
        |> scan_pin_refs(layer["pins"] || [], layer_idx)
        |> scan_zone_refs(layer["zones"] || [], layer_idx)
      end)
      |> scan_orphan_pin_refs(snapshot["orphan_pins"] || [])
      |> scan_orphan_zone_refs(snapshot["orphan_zones"] || [])

    refs
  end

  defp scan_pin_refs(refs, pins, layer_idx) do
    pins
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {pin, pin_idx}, acc ->
      prefix =
        dgettext("scenes", "Layer %{l}, Pin %{p}", l: layer_idx, p: pin_idx)

      acc
      |> maybe_add_ref(:sheet, pin["sheet_id"], prefix <> " — sheet")
      |> maybe_add_ref(:asset, pin["icon_asset_id"], prefix <> " — icon asset")
      |> maybe_add_ref(:flow, pin["flow_id"], prefix <> " — flow")
    end)
  end

  defp scan_zone_refs(refs, zones, layer_idx) do
    zones
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {zone, zone_idx}, acc ->
      prefix =
        dgettext("scenes", "Layer %{l}, Zone %{z}", l: layer_idx, z: zone_idx)

      acc
      |> maybe_add_target_ref(zone["target_type"], zone["target_id"], prefix <> " — target")
      |> maybe_add_ref(:asset, zone["label_icon_asset_id"], prefix <> " — label icon")
    end)
  end

  defp scan_orphan_pin_refs(refs, pins) do
    pins
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {pin, pin_idx}, acc ->
      prefix = dgettext("scenes", "Scene Pin %{p}", p: pin_idx)

      acc
      |> maybe_add_ref(:sheet, pin["sheet_id"], prefix <> " — sheet")
      |> maybe_add_ref(:asset, pin["icon_asset_id"], prefix <> " — icon asset")
      |> maybe_add_ref(:flow, pin["flow_id"], prefix <> " — flow")
    end)
  end

  defp scan_orphan_zone_refs(refs, zones) do
    zones
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {zone, zone_idx}, acc ->
      prefix = dgettext("scenes", "Scene Zone %{z}", z: zone_idx)

      acc
      |> maybe_add_target_ref(zone["target_type"], zone["target_id"], prefix <> " — target")
      |> maybe_add_ref(:asset, zone["label_icon_asset_id"], prefix <> " — label icon")
    end)
  end

  @target_type_mapping %{
    "sheet" => :sheet,
    "flow" => :flow,
    "scene" => :scene
  }

  defp maybe_add_target_ref(refs, target_type, target_id, context) do
    case Map.get(@target_type_mapping, target_type) do
      nil -> refs
      type -> maybe_add_ref(refs, type, target_id, context)
    end
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]

  defp resolve_scene_sheet_id(sheet_id, project_id, opts) do
    MaterializationHelpers.resolve_project_external_ref(
      sheet_id,
      Storyarn.Sheets.Sheet,
      :sheet,
      project_id,
      opts
    )
  end

  defp scene_root_container do
    %{"name" => dgettext("scenes", "Scene root")}
  end
end

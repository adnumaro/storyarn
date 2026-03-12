defmodule Storyarn.Versioning.Builders.SceneBuilder do
  @moduledoc """
  Snapshot builder for scenes.

  Captures scene metadata, layers (sorted by position), and per-layer
  zones, pins, and annotations. Connections reference pins by
  (layer_index, pin_index_within_layer) for portability.
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Ecto.Multi
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.Builders.AssetHashResolver

  alias Storyarn.Scenes.{
    Scene,
    SceneAnnotation,
    SceneConnection,
    SceneLayer,
    ScenePin,
    SceneZone
  }

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Scene{} = scene) do
    scene =
      Repo.preload(scene, [
        {:layers, [:zones, :pins]},
        :annotations,
        :connections
      ])

    sorted_layers = Enum.sort_by(scene.layers, &{&1.position, &1.id})

    # Group annotations by layer_id for snapshot building
    annotations_by_layer =
      scene.annotations
      |> Enum.group_by(& &1.layer_id)

    # Build pin ID → (layer_index, pin_index) map for connections
    pin_index_map = build_pin_index_map(sorted_layers)

    layer_snapshots = Enum.map(sorted_layers, &layer_to_snapshot(&1, annotations_by_layer))

    connection_snapshots =
      scene.connections
      |> Enum.filter(fn conn ->
        Map.has_key?(pin_index_map, conn.from_pin_id) and
          Map.has_key?(pin_index_map, conn.to_pin_id)
      end)
      |> Enum.sort_by(fn conn ->
        {layer_idx, pin_idx} = Map.get(pin_index_map, conn.from_pin_id)
        {layer_idx, pin_idx}
      end)
      |> Enum.map(&connection_to_snapshot(&1, pin_index_map))

    # Collect asset IDs from scene + pins
    pin_asset_ids =
      sorted_layers
      |> Enum.flat_map(fn layer -> Enum.map(layer.pins, & &1.icon_asset_id) end)

    asset_ids = [scene.background_asset_id | pin_asset_ids]
    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
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
      "background_asset_id" => scene.background_asset_id,
      "layers" => layer_snapshots,
      "connections" => connection_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
    }
  end

  defp build_pin_index_map(sorted_layers) do
    sorted_layers
    |> Enum.with_index()
    |> Enum.flat_map(fn {layer, layer_idx} ->
      layer.pins
      |> Enum.sort_by(&{&1.position, &1.id})
      |> Enum.with_index()
      |> Enum.map(fn {pin, pin_idx} -> {pin.id, {layer_idx, pin_idx}} end)
    end)
    |> Map.new()
  end

  defp layer_to_snapshot(%SceneLayer{} = layer, annotations_by_layer) do
    sorted_zones = Enum.sort_by(layer.zones, &{&1.position, &1.id})
    sorted_pins = Enum.sort_by(layer.pins, &{&1.position, &1.id})

    sorted_annotations =
      Map.get(annotations_by_layer, layer.id, [])
      |> Enum.sort_by(&{&1.position, &1.id})

    %{
      "name" => layer.name,
      "is_default" => layer.is_default,
      "position" => layer.position,
      "visible" => layer.visible,
      "fog_enabled" => layer.fog_enabled,
      "fog_color" => layer.fog_color,
      "fog_opacity" => layer.fog_opacity,
      "zones" => Enum.map(sorted_zones, &zone_to_snapshot/1),
      "pins" => Enum.map(sorted_pins, &pin_to_snapshot/1),
      "annotations" => Enum.map(sorted_annotations, &annotation_to_snapshot/1)
    }
  end

  defp zone_to_snapshot(%SceneZone{} = zone) do
    %{
      "name" => zone.name,
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
      "condition" => zone.condition,
      "condition_effect" => zone.condition_effect
    }
  end

  defp pin_to_snapshot(%ScenePin{} = pin) do
    %{
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "opacity" => pin.opacity,
      "label" => pin.label,
      "target_type" => pin.target_type,
      "target_id" => pin.target_id,
      "tooltip" => pin.tooltip,
      "size" => pin.size,
      "position" => pin.position,
      "locked" => pin.locked,
      "sheet_id" => pin.sheet_id,
      "icon_asset_id" => pin.icon_asset_id,
      "action_type" => pin.action_type,
      "action_data" => pin.action_data,
      "condition" => pin.condition,
      "condition_effect" => pin.condition_effect
    }
  end

  defp annotation_to_snapshot(%SceneAnnotation{} = annotation) do
    %{
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
    {from_layer_idx, from_pin_idx} = Map.fetch!(pin_index_map, conn.from_pin_id)
    {to_layer_idx, to_pin_idx} = Map.fetch!(pin_index_map, conn.to_pin_id)

    %{
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
      "waypoints" => conn.waypoints
    }
  end

  # ========== Restore Snapshot ==========

  @impl true
  def restore_snapshot(%Scene{} = scene, snapshot, _opts \\ []) do
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
        background_asset_id:
          AssetHashResolver.resolve_asset_fk(
            snapshot["background_asset_id"],
            snapshot,
            scene.project_id
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
      restore_layers(repo, scene.id, snapshot["layers"] || [], snapshot, scene.project_id)
    end)
    |> Multi.run(:restore_connections, fn repo, %{restore_layers: layer_data} ->
      restore_connections(repo, scene.id, snapshot["connections"] || [], layer_data)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{scene: updated_scene}} ->
        {:ok,
         Repo.preload(
           updated_scene,
           [:background_asset, :connections, :annotations, {:layers, [:zones, :pins]}],
           force: true
         )}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_layers(_repo, _scene_id, [], _snapshot, _project_id), do: {:ok, %{}}

  defp restore_layers(repo, scene_id, layers_data, snapshot, project_id) do
    now = TimeHelpers.now()

    layer_data =
      layers_data
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {layer_data, layer_idx}, acc ->
        {layer_id, pin_ids} =
          restore_single_layer(repo, scene_id, layer_data, layer_idx, now, snapshot, project_id)

        Map.put(acc, layer_idx, %{layer_id: layer_id, pin_ids: pin_ids})
      end)

    {:ok, layer_data}
  end

  defp restore_single_layer(repo, scene_id, layer_data, layer_idx, now, snapshot, project_id) do
    layer_id = insert_layer(repo, scene_id, layer_data, layer_idx, now)
    insert_layer_zones(repo, scene_id, layer_id, layer_data["zones"] || [], now)

    pin_ids =
      insert_layer_pins(
        repo,
        scene_id,
        layer_id,
        layer_data["pins"] || [],
        now,
        snapshot,
        project_id
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
      fog_color: layer_data["fog_color"] || "#000000",
      fog_opacity: layer_data["fog_opacity"] || 0.85,
      inserted_at: now,
      updated_at: now
    }

    {1, [%{id: layer_id}]} = repo.insert_all(SceneLayer, [attrs], returning: [:id])
    layer_id
  end

  defp insert_layer_zones(_repo, _scene_id, _layer_id, [], _now), do: :ok

  defp insert_layer_zones(repo, scene_id, layer_id, zones_data, now) do
    Enum.each(zones_data, fn zone_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        name: zone_data["name"],
        vertices: zone_data["vertices"],
        fill_color: zone_data["fill_color"],
        border_color: zone_data["border_color"],
        border_width: zone_data["border_width"] || 2,
        border_style: zone_data["border_style"] || "solid",
        opacity: zone_data["opacity"] || 0.3,
        target_type: zone_data["target_type"],
        target_id: zone_data["target_id"],
        tooltip: zone_data["tooltip"],
        position: zone_data["position"] || 0,
        locked: zone_data["locked"] || false,
        action_type: zone_data["action_type"] || "none",
        action_data: zone_data["action_data"] || %{},
        condition: zone_data["condition"],
        condition_effect: zone_data["condition_effect"] || "hide",
        inserted_at: now,
        updated_at: now
      }

      repo.insert_all(SceneZone, [attrs])
    end)
  end

  defp insert_layer_pins(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id), do: []

  defp insert_layer_pins(repo, scene_id, layer_id, pins_data, now, snapshot, project_id) do
    Enum.map(pins_data, fn pin_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        position_x: pin_data["position_x"],
        position_y: pin_data["position_y"],
        pin_type: pin_data["pin_type"] || "location",
        icon: pin_data["icon"],
        color: pin_data["color"],
        opacity: pin_data["opacity"] || 1.0,
        label: pin_data["label"],
        target_type: pin_data["target_type"],
        target_id: pin_data["target_id"],
        tooltip: pin_data["tooltip"],
        size: pin_data["size"] || "md",
        position: pin_data["position"] || 0,
        locked: pin_data["locked"] || false,
        sheet_id: resolve_fk(pin_data["sheet_id"], Storyarn.Sheets.Sheet),
        icon_asset_id:
          AssetHashResolver.resolve_asset_fk(
            pin_data["icon_asset_id"],
            snapshot,
            project_id
          ),
        action_type: pin_data["action_type"] || "none",
        action_data: pin_data["action_data"] || %{},
        condition: pin_data["condition"],
        condition_effect: pin_data["condition_effect"] || "hide",
        inserted_at: now,
        updated_at: now
      }

      {1, [%{id: pin_id}]} = repo.insert_all(ScenePin, [attrs], returning: [:id])
      pin_id
    end)
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

      repo.insert_all(SceneAnnotation, [attrs])
    end)
  end

  defp restore_connections(_repo, _scene_id, [], _layer_data), do: {:ok, 0}

  defp restore_connections(repo, scene_id, connections_data, layer_data) do
    now = TimeHelpers.now()

    # Build indexed maps for O(1) pin lookups
    pin_index_maps =
      Map.new(layer_data, fn {layer_idx, %{pin_ids: pin_ids}} ->
        indexed = pin_ids |> Enum.with_index() |> Map.new(fn {id, idx} -> {idx, id} end)
        {layer_idx, %{map: indexed, count: length(pin_ids)}}
      end)

    entries =
      connections_data
      |> Enum.filter(fn conn ->
        from = Map.get(pin_index_maps, conn["from_layer_index"])
        to = Map.get(pin_index_maps, conn["to_layer_index"])

        from != nil and to != nil and
          conn["from_pin_index"] >= 0 and
          conn["from_pin_index"] < from.count and
          conn["to_pin_index"] >= 0 and
          conn["to_pin_index"] < to.count
      end)
      |> Enum.map(fn conn ->
        from = Map.fetch!(pin_index_maps, conn["from_layer_index"])
        to = Map.fetch!(pin_index_maps, conn["to_layer_index"])

        %{
          scene_id: scene_id,
          from_pin_id: Map.fetch!(from.map, conn["from_pin_index"]),
          to_pin_id: Map.fetch!(to.map, conn["to_pin_index"]),
          line_style: conn["line_style"] || "solid",
          line_width: conn["line_width"] || 2,
          color: conn["color"],
          label: conn["label"],
          bidirectional: Map.get(conn, "bidirectional", true),
          show_label: Map.get(conn, "show_label", true),
          waypoints: conn["waypoints"] || [],
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = repo.insert_all(SceneConnection, entries)
    {:ok, count}
  end

  # ========== Diff Snapshots ==========

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    changes =
      []
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "name",
        dgettext("scenes", "Renamed scene")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "shortcut",
        dgettext("scenes", "Changed shortcut")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "description",
        dgettext("scenes", "Changed description")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "background_asset_id",
        dgettext("scenes", "Changed background")
      )
      |> append_layer_changes(old_snapshot["layers"] || [], new_snapshot["layers"] || [])
      |> append_connection_changes(
        old_snapshot["connections"] || [],
        new_snapshot["connections"] || []
      )

    format_change_summary(changes)
  end

  defp check_field_change(changes, old_snapshot, new_snapshot, field, message) do
    if old_snapshot[field] != new_snapshot[field] do
      [message | changes]
    else
      changes
    end
  end

  defp append_layer_changes(changes, old_layers, new_layers) do
    old_count = length(old_layers)
    new_count = length(new_layers)
    diff = new_count - old_count

    # Count total pins/zones across layers for more detail
    old_pins = old_layers |> Enum.flat_map(&(&1["pins"] || [])) |> length()
    new_pins = new_layers |> Enum.flat_map(&(&1["pins"] || [])) |> length()
    old_zones = old_layers |> Enum.flat_map(&(&1["zones"] || [])) |> length()
    new_zones = new_layers |> Enum.flat_map(&(&1["zones"] || [])) |> length()

    changes
    |> maybe_add_diff(diff, "layers",
      add_fn:
        &dngettext("scenes", "Added %{count} layer", "Added %{count} layers", &1, count: &1),
      remove_fn:
        &dngettext("scenes", "Removed %{count} layer", "Removed %{count} layers", &1, count: &1)
    )
    |> maybe_add_diff(new_pins - old_pins, "pins",
      add_fn: &dngettext("scenes", "Added %{count} pin", "Added %{count} pins", &1, count: &1),
      remove_fn:
        &dngettext("scenes", "Removed %{count} pin", "Removed %{count} pins", &1, count: &1)
    )
    |> maybe_add_diff(new_zones - old_zones, "zones",
      add_fn: &dngettext("scenes", "Added %{count} zone", "Added %{count} zones", &1, count: &1),
      remove_fn:
        &dngettext("scenes", "Removed %{count} zone", "Removed %{count} zones", &1, count: &1)
    )
  end

  defp append_connection_changes(changes, old_conns, new_conns) do
    diff = length(new_conns) - length(old_conns)

    maybe_add_diff(changes, diff, "connections",
      add_fn:
        &dngettext("scenes", "Added %{count} connection", "Added %{count} connections", &1,
          count: &1
        ),
      remove_fn:
        &dngettext("scenes", "Removed %{count} connection", "Removed %{count} connections", &1,
          count: &1
        )
    )
  end

  defp maybe_add_diff(changes, diff, _label, opts) do
    cond do
      diff > 0 -> [opts[:add_fn].(diff) | changes]
      diff < 0 -> [opts[:remove_fn].(abs(diff)) | changes]
      true -> changes
    end
  end

  defp format_change_summary([]), do: dgettext("scenes", "No changes detected")
  defp format_change_summary(changes), do: changes |> Enum.reverse() |> Enum.join(", ")

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
      |> maybe_add_target_ref(pin["target_type"], pin["target_id"], prefix <> " — target")
    end)
  end

  defp scan_zone_refs(refs, zones, layer_idx) do
    zones
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {zone, zone_idx}, acc ->
      prefix =
        dgettext("scenes", "Layer %{l}, Zone %{z}", l: layer_idx, z: zone_idx)

      maybe_add_target_ref(acc, zone["target_type"], zone["target_id"], prefix <> " — target")
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

  defp maybe_add_ref(refs, type, id, context),
    do: [%{type: type, id: id, context: context} | refs]

  # Returns the FK value only if the referenced record still exists, nil otherwise.
  defp resolve_fk(nil, _schema), do: nil

  defp resolve_fk(id, schema) do
    if Repo.exists?(from(e in schema, where: e.id == ^id)), do: id, else: nil
  end
end

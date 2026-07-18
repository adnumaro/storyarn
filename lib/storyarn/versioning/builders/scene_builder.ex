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
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Scenes.RoutePoints
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.MaterializationHelpers
  alias Storyarn.Versioning.RestorePolicy

  @scene_restore_root_fields ~w(
    original_id name shortcut description width height default_zoom
    default_center_x default_center_y scale_unit scale_value fog_color
    fog_opacity exploration_display_mode background_asset_id layers
    orphan_zones orphan_pins orphan_annotations connections asset_blob_hashes
    asset_metadata ambient_flows
  )
  @scene_restore_layer_fields ~w(
    original_id name is_default position visible fog_enabled zones pins annotations
  )
  @scene_restore_zone_fields ~w(
    original_id name shortcut hidden vertices fill_color border_color border_width
    border_style opacity target_type target_id tooltip position locked action_type
    action_data label_mode label_font_size label_font_family label_font_weight
    label_font_style label_icon_asset_id condition condition_effect is_walkable
  )
  @scene_restore_pin_fields ~w(
    original_id position_x position_y pin_type icon color opacity label shortcut
    hidden flow_id tooltip size position locked sheet_id icon_asset_id condition
    condition_effect is_playable is_leader patrol_mode patrol_speed patrol_pause_ms
  )
  @scene_restore_annotation_fields ~w(
    original_id text position_x position_y font_size color position locked
  )
  @scene_restore_connection_fields ~w(
    original_id from_pin_original_id to_pin_original_id from_layer_index
    from_pin_index to_layer_index to_pin_index line_style line_width color label
    bidirectional show_label waypoints from_stop to_stop from_pause_ms to_pause_ms
  )
  @scene_restore_ambient_flow_fields ~w(
    original_id flow_id trigger_type trigger_config priority enabled position
  )

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Scene{} = scene) do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          :ok = lock_scene_project_for_snapshot!(scene.project_id)

          scene
          |> lock_scene_for_snapshot!()
          |> do_build_snapshot()
        end,
        isolation: :repeatable_read
      )

    snapshot
  end

  defp lock_scene_project_for_snapshot!(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} ->
        :ok

      %Project{} ->
        raise ArgumentError, "cannot snapshot scene under inactive project #{project_id}"

      nil ->
        raise ArgumentError, "cannot snapshot scene under missing project #{project_id}"
    end
  end

  defp lock_scene_for_snapshot!(%Scene{id: scene_id, project_id: project_id}) do
    case Repo.one(from(scene in Scene, where: scene.id == ^scene_id, lock: "FOR UPDATE")) do
      %Scene{project_id: ^project_id, deleted_at: nil} = locked_scene ->
        locked_scene

      %Scene{project_id: ^project_id} ->
        raise ArgumentError, "cannot snapshot inactive scene #{scene_id}"

      %Scene{project_id: owner_project_id} ->
        raise ArgumentError,
              "scene #{scene_id} changed project ownership to #{owner_project_id} while building snapshot"

      nil ->
        raise Ecto.NoResultsError, queryable: Scene
    end
  end

  defp do_build_snapshot(%Scene{} = scene) do
    ensure_persisted_scene_layer_integrity!(scene.id)

    scene =
      Repo.preload(
        scene,
        [
          {:layers, [:zones, :pins]},
          :zones,
          :pins,
          :annotations,
          :connections,
          :ambient_flows
        ],
        force: true
      )

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
      |> Enum.sort_by(fn conn ->
        {layer_idx, pin_idx} = Map.get(pin_index_map, conn.from_pin_id, {999_999, conn.id})
        {layer_idx, pin_idx, conn.id}
      end)
      |> Enum.map(&connection_to_snapshot!(&1, pin_index_map))

    ambient_flow_snapshots =
      scene.ambient_flows
      |> Enum.sort_by(&{&1.position, &1.id})
      |> Enum.map(&ambient_flow_to_snapshot/1)

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

    {hash_map, metadata_map} =
      AssetHashResolver.resolve_hashes_for_project!(asset_ids, scene.project_id)

    snapshot = %{
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
      "ambient_flows" => ambient_flow_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
    }

    ensure_valid_built_scene_snapshot!(scene, snapshot)
  end

  defp ensure_persisted_scene_layer_integrity!(scene_id) do
    layer_ids =
      Repo.all(
        from(layer in SceneLayer,
          where: layer.scene_id == ^scene_id,
          select: layer.id
        )
      )

    case persisted_scene_layer_integrity_violation(Repo, scene_id, layer_ids) do
      nil ->
        :ok

      violation ->
        raise ArgumentError,
              "cannot snapshot scene with inconsistent layer ownership: #{inspect(violation)}"
    end
  end

  defp persisted_scene_layer_integrity_violation(repo, scene_id, layer_ids) do
    Enum.find_value(
      [
        {SceneZone, :scene_zone},
        {ScenePin, :scene_pin},
        {SceneAnnotation, :scene_annotation}
      ],
      fn {schema, label} ->
        case repo.one(
               from(row in schema,
                 where:
                   (row.scene_id == ^scene_id and not is_nil(row.layer_id) and
                      row.layer_id not in ^layer_ids) or
                     (row.scene_id != ^scene_id and row.layer_id in ^layer_ids),
                 order_by: [asc: row.id],
                 select: {row.id, row.scene_id, row.layer_id},
                 limit: 1
               )
             ) do
          nil -> nil
          {id, owner_scene_id, layer_id} -> {label, id, owner_scene_id, layer_id}
        end
      end
    )
  end

  defp ensure_valid_built_scene_snapshot!(scene, snapshot) do
    result =
      with {:ok, plan} <- validate_scene_snapshot_structure(snapshot) do
        validate_scene_external_reference_ownership(Repo, scene, snapshot, plan)
      end

    case result do
      :ok ->
        snapshot

      {:error, reason} ->
        raise ArgumentError,
              "cannot build an internally inconsistent scene snapshot: #{inspect(reason)}"
    end
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
      "is_leader" => pin.is_leader,
      "patrol_mode" => pin.patrol_mode,
      "patrol_speed" => pin.patrol_speed,
      "patrol_pause_ms" => pin.patrol_pause_ms
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

  defp connection_to_snapshot!(%SceneConnection{} = conn, pin_index_map) do
    ensure_snapshotable_connection!(conn, pin_index_map)

    {from_layer_idx, from_pin_idx} = optional_pin_index(pin_index_map, conn.from_pin_id)
    {to_layer_idx, to_pin_idx} = optional_pin_index(pin_index_map, conn.to_pin_id)

    %{
      "original_id" => conn.id,
      "from_pin_original_id" => conn.from_pin_id,
      "to_pin_original_id" => conn.to_pin_id,
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

  defp ambient_flow_to_snapshot(%SceneAmbientFlow{} = ambient_flow) do
    %{
      "original_id" => ambient_flow.id,
      "flow_id" => ambient_flow.flow_id,
      "trigger_type" => ambient_flow.trigger_type,
      "trigger_config" => ambient_flow.trigger_config,
      "priority" => ambient_flow.priority,
      "enabled" => ambient_flow.enabled,
      "position" => ambient_flow.position
    }
  end

  defp ensure_snapshotable_connection!(conn, pin_index_map) do
    cond do
      not RoutePoints.enough_points?(
        conn.from_pin_id,
        conn.to_pin_id,
        conn.waypoints
      ) ->
        raise ArgumentError,
              "cannot snapshot scene connection #{conn.id}: route has fewer than two points"

      not optional_pin_in_snapshot?(pin_index_map, conn.from_pin_id) ->
        raise ArgumentError,
              "cannot snapshot scene connection #{conn.id}: from_pin_id #{inspect(conn.from_pin_id)} is not in the scene snapshot"

      not optional_pin_in_snapshot?(pin_index_map, conn.to_pin_id) ->
        raise ArgumentError,
              "cannot snapshot scene connection #{conn.id}: to_pin_id #{inspect(conn.to_pin_id)} is not in the scene snapshot"

      true ->
        :ok
    end
  end

  defp optional_pin_in_snapshot?(_pin_index_map, nil), do: true
  defp optional_pin_in_snapshot?(pin_index_map, pin_id), do: Map.has_key?(pin_index_map, pin_id)

  defp optional_pin_index(_pin_index_map, nil), do: {nil, nil}
  defp optional_pin_index(pin_index_map, pin_id), do: Map.fetch!(pin_index_map, pin_id)

  # ========== Restore Snapshot ==========

  @impl true
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    with :ok <- validate_portable_scene_snapshot(snapshot) do
      run_scene_instantiation(project_id, snapshot, opts)
    end
  end

  defp run_scene_instantiation(project_id, snapshot, opts) do
    opts
    |> MaterializationHelpers.with_asset_copy_tracker(fn tracked_opts ->
      AssetMaterializationScope.run(tracked_opts, fn scoped_opts ->
        execute_scene_instantiation_transaction(project_id, snapshot, scoped_opts)
      end)
    end)
    |> case do
      {:ok, {scene, id_maps}} -> {:ok, scene, id_maps}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_scene_instantiation_transaction(project_id, snapshot, opts) do
    Repo.transaction(
      fn -> instantiate_scene_snapshot(project_id, snapshot, opts) end,
      timeout: :infinity
    )
  end

  defp instantiate_scene_snapshot(project_id, snapshot, opts) do
    case lock_scene_materialization_project(Repo, project_id) do
      {:ok, _project} ->
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
             materialization_opts = put_materialized_scene_root_map(opts, snapshot, scene_id),
             {:ok, layer_id_map} <-
               insert_scene_layers(Repo, scene_id, snapshot["layers"] || [], now),
             {:ok, nested_results} <-
               insert_scene_layer_children(
                 Repo,
                 scene_id,
                 snapshot["layers"] || [],
                 layer_id_map,
                 snapshot,
                 project_id,
                 now,
                 materialization_opts
               ),
             {:ok, orphan_results} <-
               insert_scene_orphan_children(
                 Repo,
                 scene_id,
                 snapshot,
                 project_id,
                 now,
                 materialization_opts
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
               ),
             {:ok, ambient_flow_id_map} <-
               insert_scene_ambient_flows(
                 Repo,
                 scene_id,
                 snapshot["ambient_flows"] || [],
                 project_id,
                 now,
                 materialization_opts
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
                [ambient_flows: :flow],
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
            annotation: Map.merge(nested_results.annotation_id_map, orphan_results.annotation_id_map),
            ambient_flow: ambient_flow_id_map
          }

          finalize_instantiated_scene(scene, id_maps, materialization_opts)
        else
          {:error, reason} -> Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp put_materialized_scene_root_map(opts, snapshot, scene_id) do
    external_id_maps = Keyword.get(opts, :external_id_maps, %{})

    scene_id_map =
      external_id_maps
      |> Map.get(:scene, %{})
      |> Map.put(snapshot["original_id"], scene_id)

    Keyword.put(opts, :external_id_maps, Map.put(external_id_maps, :scene, scene_id_map))
  end

  defp finalize_instantiated_scene(scene, id_maps, opts) do
    case rebuild_instantiated_scene_references(scene, opts) do
      :ok -> {scene, id_maps}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_scene_materialization_project(repo, project_id) do
    case repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, {:project_not_active, project_id}}
      nil -> {:error, {:project_not_found, project_id}}
    end
  end

  defp rebuild_instantiated_scene_references(scene, opts) do
    if Keyword.get(opts, :rebuild_references, true) do
      with :ok <-
             reconcile_reference_items(
               scene.pins,
               &update_scene_pin_references(&1, scene.project_id)
             ) do
        reconcile_reference_items(
          scene.zones,
          &update_scene_zone_references(&1, scene.project_id)
        )
      end
    else
      :ok
    end
  end

  @impl true
  def restore_snapshot(%Scene{} = scene, snapshot, opts \\ []) do
    with :ok <-
           RestorePolicy.ensure_builder_enabled(
             "scene",
             Keyword.get(opts, :restore_action)
           ),
         :ok <- validate_portable_scene_snapshot(snapshot) do
      opts
      |> MaterializationHelpers.with_asset_copy_tracker(&run_scene_restore_materialization(scene, snapshot, &1))
      |> finalize_scene_restore()
    end
  end

  defp run_scene_restore_materialization(scene, snapshot, opts) do
    AssetMaterializationScope.run(opts, fn scoped_opts ->
      execute_scene_restore_transaction(scene, snapshot, scoped_opts)
    end)
  end

  defp execute_scene_restore_transaction(scene, snapshot, opts) do
    Multi.new()
    |> Multi.run(:lock_project, fn repo, _changes ->
      lock_scene_materialization_project(repo, scene.project_id)
    end)
    |> Multi.run(:lock_scene, fn repo, %{lock_project: _project} ->
      lock_scene_for_restore(repo, scene)
    end)
    |> Multi.run(:lock_external_references, fn repo,
                                               %{
                                                 lock_scene: locked_scene
                                               } ->
      lock_scene_external_references(repo, locked_scene, snapshot)
    end)
    |> Multi.run(:lock_restore_scope, fn repo,
                                         %{
                                           lock_scene: locked_scene,
                                           lock_external_references: _references
                                         } ->
      lock_scene_restore_scope(repo, locked_scene.id)
    end)
    |> Multi.run(:validate_snapshot, fn repo,
                                        %{
                                          lock_scene: locked_scene,
                                          lock_restore_scope: _scope,
                                          lock_external_references: _references
                                        } ->
      validate_scene_restore_snapshot(repo, locked_scene, snapshot)
    end)
    |> Multi.update(:scene, fn %{lock_scene: locked_scene} ->
      Scene.update_changeset(locked_scene, %{
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
        exploration_display_mode: snapshot_default(snapshot, "exploration_display_mode", "fit"),
        background_asset_id:
          resolve_scene_asset(
            snapshot["background_asset_id"],
            snapshot,
            locked_scene.project_id,
            opts
          )
      })
    end)
    |> Multi.run(:restore_children, fn repo,
                                       %{
                                         lock_scene: locked_scene,
                                         validate_snapshot: plan
                                       } ->
      reconcile_scene_children(repo, locked_scene, snapshot, plan, opts)
    end)
    |> Multi.run(:reconcile_references, fn _repo,
                                           %{
                                             lock_scene: locked_scene,
                                             validate_snapshot: plan,
                                             restore_children: restored
                                           } ->
      reconcile_scene_references(locked_scene.project_id, plan, restored)
    end)
    |> Repo.transaction(timeout: :infinity)
  end

  defp finalize_scene_restore({:ok, %{scene: updated_scene}}) do
    {:ok,
     Repo.preload(
       updated_scene,
       [
         :background_asset,
         :connections,
         :annotations,
         :zones,
         [ambient_flows: :flow],
         [pins: [:icon_asset, sheet: [avatars: :asset]]],
         {:layers, [:zones, :pins]}
       ],
       force: true
     )}
  end

  defp finalize_scene_restore({:error, _op, reason, _changes}), do: {:error, reason}
  defp finalize_scene_restore({:error, reason}), do: {:error, reason}

  defp lock_scene_for_restore(repo, %Scene{id: scene_id, project_id: project_id}) do
    case repo.one(
           from(scene in Scene,
             where: scene.id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %Scene{project_id: ^project_id, deleted_at: nil} = locked_scene ->
        {:ok, locked_scene}

      %Scene{project_id: ^project_id} ->
        {:error, {:scene_not_active, scene_id}}

      %Scene{project_id: actual_project_id} ->
        {:error, {:scene_project_mismatch, scene_id, project_id, actual_project_id}}

      nil ->
        {:error, {:scene_not_found, scene_id}}
    end
  end

  defp lock_scene_restore_scope(repo, scene_id) do
    layer_ids = lock_scene_owned_rows(repo, SceneLayer, scene_id)

    with {:ok, zone_ids} <-
           lock_layer_scoped_scene_rows(repo, SceneZone, :scene_zone, scene_id, layer_ids),
         {:ok, pin_ids} <-
           lock_layer_scoped_scene_rows(repo, ScenePin, :scene_pin, scene_id, layer_ids),
         {:ok, annotation_ids} <-
           lock_layer_scoped_scene_rows(
             repo,
             SceneAnnotation,
             :scene_annotation,
             scene_id,
             layer_ids
           ) do
      {:ok,
       %{
         SceneLayer => layer_ids,
         SceneZone => zone_ids,
         ScenePin => pin_ids,
         SceneAnnotation => annotation_ids,
         SceneConnection => lock_scene_owned_rows(repo, SceneConnection, scene_id),
         SceneAmbientFlow => lock_scene_owned_rows(repo, SceneAmbientFlow, scene_id)
       }}
    end
  end

  defp lock_scene_owned_rows(repo, schema, scene_id) do
    repo.all(
      from(row in schema,
        where: row.scene_id == ^scene_id,
        order_by: [asc: row.id],
        lock: "FOR UPDATE",
        select: row.id
      )
    )
  end

  defp lock_layer_scoped_scene_rows(repo, schema, label, scene_id, layer_ids) do
    rows =
      repo.all(
        from(row in schema,
          where: row.scene_id == ^scene_id or row.layer_id in ^layer_ids,
          order_by: [asc: row.id],
          lock: "FOR UPDATE",
          select: {row.id, row.scene_id, row.layer_id}
        )
      )

    case Enum.find(rows, fn {_id, owner_scene_id, layer_id} ->
           (owner_scene_id == scene_id and not is_nil(layer_id) and
              layer_id not in layer_ids) or
             (owner_scene_id != scene_id and layer_id in layer_ids)
         end) do
      nil ->
        {:ok,
         rows
         |> Enum.filter(fn {_id, owner_scene_id, _layer_id} -> owner_scene_id == scene_id end)
         |> Enum.map(&elem(&1, 0))}

      {id, owner_scene_id, layer_id} ->
        {:error, {:scene_layer_ownership_mismatch, label, id, owner_scene_id, layer_id, scene_id}}
    end
  end

  defp lock_scene_external_references(repo, scene, snapshot) do
    with {:ok, plan} <- validate_scene_snapshot_structure(snapshot) do
      references = scene_snapshot_reference_ids(plan, snapshot)

      owners_by_schema =
        Map.new(
          [
            {Flow, references.flow_ids},
            {Sheet, references.sheet_ids},
            {Scene, references.scene_ids}
          ],
          fn {schema, ids} ->
            owners =
              from(row in schema,
                where: row.id in ^Enum.sort(ids) and is_nil(row.deleted_at),
                order_by: [asc: row.id],
                lock: "FOR UPDATE",
                select: {row.id, row.project_id}
              )
              |> repo.all()
              |> Map.new()

            {schema, owners}
          end
        )

      asset_owners =
        from(asset in Asset,
          where: asset.id in ^Enum.sort(references.asset_ids),
          order_by: [asc: asset.id],
          lock: "FOR UPDATE",
          select: {asset.id, asset.project_id}
        )
        |> repo.all()
        |> Map.new()

      with :ok <-
             validate_scene_external_reference_ownership_from_locked(
               scene,
               snapshot,
               plan,
               references,
               owners_by_schema,
               asset_owners
             ) do
        {:ok, references}
      end
    end
  end

  defp validate_scene_restore_snapshot(repo, %Scene{} = scene, snapshot) when is_map(snapshot) do
    with :ok <- validate_scene_root_id(scene, snapshot),
         {:ok, plan} <- validate_scene_snapshot_structure(snapshot),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             SceneLayer,
             plan.layer_ids,
             scene.id,
             :scene_layer
           ),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             SceneZone,
             plan.zone_ids,
             scene.id,
             :scene_zone
           ),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             ScenePin,
             plan.pin_ids,
             scene.id,
             :scene_pin
           ),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             SceneAnnotation,
             plan.annotation_ids,
             scene.id,
             :scene_annotation
           ),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             SceneConnection,
             plan.connection_ids,
             scene.id,
             :scene_connection
           ),
         :ok <-
           validate_ids_belong_to_scene(
             repo,
             SceneAmbientFlow,
             plan.ambient_flow_ids,
             scene.id,
             :scene_ambient_flow
           ),
         :ok <- validate_scene_external_reference_ownership(repo, scene, snapshot, plan) do
      {:ok,
       Map.merge(plan, %{
         removed_zone_ids: removed_scene_child_ids(repo, SceneZone, scene.id, plan.zone_ids),
         removed_pin_ids: removed_scene_child_ids(repo, ScenePin, scene.id, plan.pin_ids)
       })}
    end
  end

  defp validate_scene_restore_snapshot(_repo, _scene, snapshot), do: {:error, {:invalid_scene_snapshot, snapshot}}

  defp validate_portable_scene_snapshot(snapshot) do
    case validate_scene_snapshot_structure(snapshot) do
      {:ok, _plan} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_scene_snapshot_structure(snapshot) when is_map(snapshot) do
    with {:ok, data} <- collect_scene_restore_data(snapshot),
         :ok <-
           validate_required_scene_fields(
             snapshot,
             @scene_restore_root_fields,
             :scene,
             snapshot["original_id"]
           ),
         :ok <- validate_scene_snapshot_root_original_id(snapshot["original_id"]),
         :ok <- validate_scene_snapshot_metadata(snapshot),
         :ok <- validate_scene_root_payload_types(snapshot),
         :ok <- validate_scene_root_payload(snapshot),
         :ok <- validate_scene_restore_fields(data),
         {:ok, layer_ids} <- validate_original_ids(data.layers, :scene_layer),
         {:ok, zone_ids} <- validate_original_ids(data.zones, :scene_zone),
         {:ok, pin_ids} <- validate_original_ids(data.pins, :scene_pin),
         {:ok, annotation_ids} <-
           validate_original_ids(data.annotations, :scene_annotation),
         {:ok, connection_ids} <-
           validate_original_ids(data.connections, :scene_connection),
         {:ok, ambient_flow_ids} <-
           validate_original_ids(data.ambient_flows, :scene_ambient_flow),
         :ok <- validate_scene_layer_invariants(data.layers),
         :ok <- validate_scene_raw_child_types(data),
         :ok <- validate_scene_zone_target_contracts(data.zones),
         :ok <- validate_scene_zone_collection_contracts(data.zones),
         :ok <- validate_scene_child_payloads(data, snapshot["original_id"]),
         :ok <- validate_scene_ambient_flow_payloads(data.ambient_flows, snapshot["original_id"]),
         :ok <-
           validate_scene_connection_snapshots(
             data.connections,
             pin_ids,
             snapshot_pin_ids_by_index(snapshot)
           ),
         :ok <- validate_scene_snapshot_uniqueness(data) do
      {:ok,
       Map.merge(data, %{
         layer_ids: layer_ids,
         zone_ids: zone_ids,
         pin_ids: pin_ids,
         annotation_ids: annotation_ids,
         connection_ids: connection_ids,
         ambient_flow_ids: ambient_flow_ids
       })}
    end
  end

  defp validate_scene_snapshot_structure(snapshot), do: {:error, {:invalid_scene_snapshot, snapshot}}

  defp validate_scene_snapshot_root_original_id(id) when is_integer(id) and id > 0, do: :ok

  defp validate_scene_snapshot_root_original_id(id), do: {:error, {:invalid_snapshot_original_id, :scene, id}}

  defp validate_scene_restore_fields(data) do
    with :ok <-
           validate_scene_entry_fields(
             data.layers,
             @scene_restore_layer_fields,
             :scene_layer
           ),
         :ok <-
           validate_scene_entry_fields(
             data.zones,
             @scene_restore_zone_fields,
             :scene_zone
           ),
         :ok <-
           validate_scene_entry_fields(
             data.pins,
             @scene_restore_pin_fields,
             :scene_pin
           ),
         :ok <-
           validate_scene_entry_fields(
             data.annotations,
             @scene_restore_annotation_fields,
             :scene_annotation
           ),
         :ok <-
           validate_scene_entry_fields(
             data.connections,
             @scene_restore_connection_fields,
             :scene_connection
           ) do
      validate_scene_entry_fields(
        data.ambient_flows,
        @scene_restore_ambient_flow_fields,
        :scene_ambient_flow
      )
    end
  end

  defp validate_scene_entry_fields(entries, required_fields, label) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      data = restore_entry_data(entry)

      case validate_required_scene_fields(
             data,
             required_fields,
             label,
             data["original_id"]
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_required_scene_fields(data, required_fields, label, id) do
    case Enum.find(required_fields, &(not Map.has_key?(data, &1))) do
      nil -> :ok
      field -> {:error, {:missing_scene_snapshot_field, label, id, field}}
    end
  end

  defp validate_scene_snapshot_metadata(snapshot) do
    if is_map(snapshot["asset_blob_hashes"]) and
         is_map(snapshot["asset_metadata"]) do
      :ok
    else
      {:error, :invalid_scene_snapshot_asset_metadata}
    end
  end

  defp validate_scene_root_payload_types(snapshot) do
    checks = [
      {"name", non_empty_string?(snapshot["name"])},
      {"shortcut", optional_string?(snapshot["shortcut"])},
      {"description", optional_string?(snapshot["description"])},
      {"width", is_nil(snapshot["width"]) or positive_integer?(snapshot["width"])},
      {"height", is_nil(snapshot["height"]) or positive_integer?(snapshot["height"])},
      {"default_zoom", positive_number?(snapshot["default_zoom"])},
      {"default_center_x", percentage_number?(snapshot["default_center_x"])},
      {"default_center_y", percentage_number?(snapshot["default_center_y"])},
      {"scale_unit", optional_string?(snapshot["scale_unit"])},
      {"scale_value", is_nil(snapshot["scale_value"]) or positive_number?(snapshot["scale_value"])},
      {"fog_color", optional_string?(snapshot["fog_color"])},
      {"fog_opacity", unit_interval_number?(snapshot["fog_opacity"])},
      {"exploration_display_mode", is_binary(snapshot["exploration_display_mode"])},
      {"background_asset_id", optional_positive_integer?(snapshot["background_asset_id"])},
      {"asset_blob_hashes", is_map(snapshot["asset_blob_hashes"])},
      {"asset_metadata", is_map(snapshot["asset_metadata"])}
    ]

    validate_scene_raw_checks(:scene, snapshot["original_id"], snapshot, checks)
  end

  defp validate_scene_root_payload(snapshot) do
    attrs = %{
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
      fog_color: snapshot["fog_color"],
      fog_opacity: snapshot["fog_opacity"],
      exploration_display_mode: snapshot["exploration_display_mode"],
      background_asset_id: snapshot["background_asset_id"]
    }

    changeset = Scene.create_changeset(%Scene{project_id: 1}, attrs)

    if changeset.valid? do
      :ok
    else
      {:error,
       {:invalid_scene_root_snapshot, snapshot["original_id"],
        Ecto.Changeset.traverse_errors(changeset, &format_scene_changeset_error/1)}}
    end
  end

  defp validate_scene_layer_invariants([]), do: {:error, :scene_snapshot_requires_at_least_one_layer}

  defp validate_scene_layer_invariants(layers) do
    case Enum.count(layers, &(&1["is_default"] == true)) do
      1 -> :ok
      count -> {:error, {:invalid_scene_default_layer_count, count}}
    end
  end

  defp validate_scene_raw_child_types(data) do
    validators = [
      {data.layers, :scene_layer, &scene_layer_raw_checks/1},
      {data.zones, :scene_zone, &scene_zone_raw_checks/1},
      {data.pins, :scene_pin, &scene_pin_raw_checks/1},
      {data.annotations, :scene_annotation, &scene_annotation_raw_checks/1},
      {data.connections, :scene_connection, &scene_connection_raw_checks/1},
      {data.ambient_flows, :scene_ambient_flow, &scene_ambient_flow_raw_checks/1}
    ]

    Enum.reduce_while(validators, :ok, fn {entries, label, checks_fun}, :ok ->
      case validate_scene_raw_entries(entries, label, checks_fun) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_raw_entries(entries, label, checks_fun) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      data = restore_entry_data(entry)

      case validate_scene_raw_checks(label, data["original_id"], data, checks_fun.(data)) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_raw_checks(label, id, data, checks) do
    case Enum.find(checks, fn {_field, valid?} -> not valid? end) do
      nil ->
        :ok

      {field, false} ->
        {:error, {:invalid_scene_snapshot_field, label, id, field, data[field]}}
    end
  end

  defp scene_layer_raw_checks(layer) do
    [
      {"name", is_binary(layer["name"])},
      {"is_default", is_boolean(layer["is_default"])},
      {"position", is_integer(layer["position"])},
      {"visible", is_boolean(layer["visible"])},
      {"fog_enabled", is_boolean(layer["fog_enabled"])}
    ]
  end

  defp scene_zone_raw_checks(zone) do
    [
      {"name", is_binary(zone["name"])},
      {"shortcut", optional_string?(zone["shortcut"])},
      {"hidden", is_boolean(zone["hidden"])},
      {"vertices", is_list(zone["vertices"])},
      {"fill_color", optional_string?(zone["fill_color"])},
      {"border_color", optional_string?(zone["border_color"])},
      {"border_width", is_integer(zone["border_width"])},
      {"border_style", is_binary(zone["border_style"])},
      {"opacity", unit_interval_number?(zone["opacity"])},
      {"target_type", optional_string?(zone["target_type"])},
      {"target_id", optional_positive_integer?(zone["target_id"])},
      {"tooltip", optional_string?(zone["tooltip"])},
      {"position", is_integer(zone["position"])},
      {"locked", is_boolean(zone["locked"])},
      {"action_type", is_binary(zone["action_type"])},
      {"action_data", is_map(zone["action_data"])},
      {"label_mode", is_binary(zone["label_mode"])},
      {"label_font_size", is_integer(zone["label_font_size"])},
      {"label_font_family", is_binary(zone["label_font_family"])},
      {"label_font_weight", is_binary(zone["label_font_weight"])},
      {"label_font_style", is_binary(zone["label_font_style"])},
      {"label_icon_asset_id", optional_positive_integer?(zone["label_icon_asset_id"])},
      {"condition", is_nil(zone["condition"]) or is_map(zone["condition"])},
      {"condition_effect", is_binary(zone["condition_effect"])},
      {"is_walkable", is_boolean(zone["is_walkable"])}
    ]
  end

  defp validate_scene_zone_target_contracts(zones) do
    Enum.reduce_while(zones, :ok, fn entry, :ok ->
      zone = restore_entry_data(entry)

      case validate_scene_zone_target_contract(zone) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_zone_target_contract(zone) do
    normalized_action_type = zone |> zone_behavior_attrs() |> Map.fetch!(:action_type)
    target_type = zone["target_type"]
    target_id = zone["target_id"]

    valid? =
      case {normalized_action_type, target_type, target_id} do
        {"action", nil, nil} -> true
        {"action", type, id} -> type in ["flow", "scene"] and positive_integer?(id)
        {_other_action_type, nil, nil} -> true
        {_other_action_type, _type, _id} -> false
      end

    if valid? do
      :ok
    else
      {:error, {:invalid_scene_zone_target_contract, zone["original_id"], normalized_action_type, target_type, target_id}}
    end
  end

  defp validate_scene_zone_collection_contracts(zones) do
    Enum.reduce_while(zones, :ok, fn entry, :ok ->
      zone = restore_entry_data(entry)

      case validate_scene_zone_collection_contract(zone) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_zone_collection_contract(%{
         "original_id" => zone_id,
         "action_type" => "collection",
         "action_data" => %{"items" => items}
       })
       when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn
      {item, index}, {:ok, seen_ids} when is_map(item) ->
        case validate_scene_collection_item(zone_id, item, index, seen_ids) do
          {:ok, normalized_item_id} ->
            {:cont, {:ok, MapSet.put(seen_ids, normalized_item_id)}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      {item, index}, _acc ->
        {:halt, {:error, {:invalid_scene_zone_collection_item, zone_id, index, :not_a_map, item}}}
    end)
    |> case do
      {:ok, _seen_ids} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_scene_zone_collection_contract(%{"original_id" => zone_id, "action_type" => "collection"} = zone) do
    {:error, {:invalid_scene_zone_collection, zone_id, zone["action_data"]}}
  end

  defp validate_scene_zone_collection_contract(_zone), do: :ok

  defp validate_scene_collection_item(zone_id, item, index, seen_ids) do
    item_id = item["id"]

    case cast_scene_collection_item_id(item_id) do
      {:ok, normalized_item_id} ->
        validate_scene_collection_item_fields(
          zone_id,
          item,
          index,
          seen_ids,
          normalized_item_id
        )

      :error ->
        {:error, {:invalid_scene_zone_collection_item, zone_id, index, :invalid_id, item_id}}
    end
  end

  defp validate_scene_collection_item_fields(zone_id, item, index, seen_ids, normalized_item_id) do
    cond do
      MapSet.member?(seen_ids, normalized_item_id) ->
        {:error, {:invalid_scene_zone_collection_item, zone_id, index, :duplicate_id, item["id"]}}

      not optional_positive_integer?(item["sheet_id"]) ->
        {:error, {:invalid_scene_zone_collection_item, zone_id, index, :invalid_sheet_id, item["sheet_id"]}}

      true ->
        {:ok, normalized_item_id}
    end
  end

  defp cast_scene_collection_item_id(item_id) when is_binary(item_id), do: Ecto.UUID.cast(item_id)

  defp cast_scene_collection_item_id(_item_id), do: :error

  defp scene_pin_raw_checks(pin) do
    [
      {"position_x", number?(pin["position_x"])},
      {"position_y", number?(pin["position_y"])},
      {"pin_type", is_binary(pin["pin_type"])},
      {"icon", optional_string?(pin["icon"])},
      {"color", optional_string?(pin["color"])},
      {"opacity", unit_interval_number?(pin["opacity"])},
      {"label", optional_string?(pin["label"])},
      {"shortcut", optional_string?(pin["shortcut"])},
      {"hidden", is_boolean(pin["hidden"])},
      {"flow_id", optional_positive_integer?(pin["flow_id"])},
      {"tooltip", optional_string?(pin["tooltip"])},
      {"size", is_binary(pin["size"])},
      {"position", is_integer(pin["position"])},
      {"locked", is_boolean(pin["locked"])},
      {"sheet_id", optional_positive_integer?(pin["sheet_id"])},
      {"icon_asset_id", optional_positive_integer?(pin["icon_asset_id"])},
      {"condition", is_nil(pin["condition"]) or is_map(pin["condition"])},
      {"condition_effect", is_binary(pin["condition_effect"])},
      {"is_playable", is_boolean(pin["is_playable"])},
      {"is_leader", is_boolean(pin["is_leader"])},
      {"patrol_mode", is_binary(pin["patrol_mode"])},
      {"patrol_speed", number?(pin["patrol_speed"])},
      {"patrol_pause_ms", is_integer(pin["patrol_pause_ms"])}
    ]
  end

  defp scene_annotation_raw_checks(annotation) do
    [
      {"text", is_binary(annotation["text"])},
      {"position_x", number?(annotation["position_x"])},
      {"position_y", number?(annotation["position_y"])},
      {"font_size", is_binary(annotation["font_size"])},
      {"color", optional_string?(annotation["color"])},
      {"position", is_integer(annotation["position"])},
      {"locked", is_boolean(annotation["locked"])}
    ]
  end

  defp scene_connection_raw_checks(connection) do
    [
      {"from_pin_original_id", optional_positive_integer?(connection["from_pin_original_id"])},
      {"to_pin_original_id", optional_positive_integer?(connection["to_pin_original_id"])},
      {"from_layer_index", optional_scene_layer_index?(connection["from_layer_index"])},
      {"from_pin_index", optional_non_negative_integer?(connection["from_pin_index"])},
      {"to_layer_index", optional_scene_layer_index?(connection["to_layer_index"])},
      {"to_pin_index", optional_non_negative_integer?(connection["to_pin_index"])},
      {"line_style", is_binary(connection["line_style"])},
      {"line_width", is_integer(connection["line_width"])},
      {"color", optional_string?(connection["color"])},
      {"label", optional_string?(connection["label"])},
      {"bidirectional", is_boolean(connection["bidirectional"])},
      {"show_label", is_boolean(connection["show_label"])},
      {"waypoints", is_list(connection["waypoints"])},
      {"from_stop", is_boolean(connection["from_stop"])},
      {"to_stop", is_boolean(connection["to_stop"])},
      {"from_pause_ms", optional_non_negative_integer?(connection["from_pause_ms"])},
      {"to_pause_ms", optional_non_negative_integer?(connection["to_pause_ms"])}
    ]
  end

  defp scene_ambient_flow_raw_checks(ambient_flow) do
    [
      {"flow_id", positive_integer?(ambient_flow["flow_id"])},
      {"trigger_type", is_binary(ambient_flow["trigger_type"])},
      {"trigger_config", is_map(ambient_flow["trigger_config"])},
      {"priority", is_integer(ambient_flow["priority"])},
      {"enabled", is_boolean(ambient_flow["enabled"])},
      {"position", is_integer(ambient_flow["position"])}
    ]
  end

  defp number?(value), do: is_integer(value) or is_float(value)
  defp positive_number?(value), do: number?(value) and value > 0
  defp percentage_number?(value), do: number?(value) and value >= 0 and value <= 100
  defp unit_interval_number?(value), do: number?(value) and value >= 0 and value <= 1
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
  defp optional_positive_integer?(value), do: is_nil(value) or positive_integer?(value)
  defp optional_non_negative_integer?(value), do: is_nil(value) or non_negative_integer?(value)
  defp optional_scene_layer_index?(value), do: is_nil(value) or (is_integer(value) and value >= -1)
  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_string?(value), do: is_nil(value) or is_binary(value)

  defp validate_scene_root_id(%Scene{id: scene_id}, %{"original_id" => scene_id}) when is_integer(scene_id), do: :ok

  defp validate_scene_root_id(%Scene{id: scene_id}, snapshot),
    do: {:error, {:scene_snapshot_root_mismatch, scene_id, snapshot["original_id"]}}

  defp collect_scene_restore_data(snapshot) do
    with {:ok, layers} <- snapshot_map_list(snapshot, "layers"),
         {:ok, orphan_zones} <- snapshot_map_list(snapshot, "orphan_zones"),
         {:ok, orphan_pins} <- snapshot_map_list(snapshot, "orphan_pins"),
         {:ok, orphan_annotations} <-
           snapshot_map_list(snapshot, "orphan_annotations"),
         {:ok, connections} <- snapshot_map_list(snapshot, "connections"),
         {:ok, ambient_flows} <- snapshot_map_list(snapshot, "ambient_flows"),
         {:ok, layered_zones} <- collect_layer_children(layers, "zones"),
         {:ok, layered_pins} <- collect_layer_children(layers, "pins"),
         {:ok, layered_annotations} <-
           collect_layer_children(layers, "annotations") do
      {:ok,
       %{
         layers: layers,
         zones: layered_zones ++ Enum.map(orphan_zones, &{&1, nil}),
         pins: layered_pins ++ Enum.map(orphan_pins, &{&1, nil}),
         annotations: layered_annotations ++ Enum.map(orphan_annotations, &{&1, nil}),
         connections: connections,
         ambient_flows: ambient_flows
       }}
    end
  end

  defp snapshot_map_list(snapshot, key) do
    case Map.fetch(snapshot, key) do
      {:ok, list} when is_list(list) ->
        if Enum.all?(list, &is_map/1),
          do: {:ok, list},
          else: {:error, {:invalid_scene_snapshot_collection, key}}

      {:ok, _other} ->
        {:error, {:invalid_scene_snapshot_collection, key}}

      :error ->
        {:error, {:missing_scene_snapshot_collection, key}}
    end
  end

  defp collect_layer_children(layers, key) do
    Enum.reduce_while(layers, {:ok, []}, fn layer, {:ok, acc} ->
      case snapshot_map_list(layer, key) do
        {:ok, children} ->
          entries = Enum.map(children, &{&1, layer["original_id"]})
          {:cont, {:ok, acc ++ entries}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp validate_original_ids(entries, label) do
    entries
    |> Enum.reduce_while({:ok, MapSet.new(), []}, fn entry, {:ok, seen, ids} ->
      data = restore_entry_data(entry)
      id = data["original_id"]

      cond do
        not (is_integer(id) and id > 0) ->
          {:halt, {:error, {:invalid_snapshot_original_id, label, id}}}

        MapSet.member?(seen, id) ->
          {:halt, {:error, {:duplicate_snapshot_original_id, label, id}}}

        true ->
          {:cont, {:ok, MapSet.put(seen, id), [id | ids]}}
      end
    end)
    |> case do
      {:ok, _seen, ids} -> {:ok, Enum.reverse(ids)}
      {:error, _reason} = error -> error
    end
  end

  defp restore_entry_data({data, _parent_id}), do: data
  defp restore_entry_data(data), do: data

  defp validate_ids_belong_to_scene(_repo, _schema, [], _scene_id, _label), do: :ok

  defp validate_ids_belong_to_scene(repo, schema, ids, scene_id, label) do
    conflicting_id =
      repo.one(
        from(row in schema,
          where: row.id in ^ids and row.scene_id != ^scene_id,
          select: row.id,
          limit: 1
        )
      )

    if conflicting_id,
      do: {:error, {:snapshot_original_id_ownership_mismatch, label, conflicting_id, scene_id}},
      else: :ok
  end

  defp snapshot_pin_ids_by_index(snapshot) do
    layered_pin_ids =
      snapshot["layers"]
      |> Enum.with_index()
      |> Enum.flat_map(&layer_pin_ids_by_index/1)

    orphan_pin_ids =
      snapshot["orphan_pins"]
      |> Enum.with_index()
      |> Enum.map(fn {pin, pin_index} -> {{-1, pin_index}, pin["original_id"]} end)

    Map.new(layered_pin_ids ++ orphan_pin_ids)
  end

  defp layer_pin_ids_by_index({layer, layer_index}) do
    layer["pins"]
    |> Enum.with_index()
    |> Enum.map(fn {pin, pin_index} ->
      {{layer_index, pin_index}, pin["original_id"]}
    end)
  end

  defp validate_scene_connection_snapshots(connections, pin_ids, pin_ids_by_index) do
    pin_ids = MapSet.new(pin_ids)

    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      case validate_scene_connection_snapshot(connection, pin_ids, pin_ids_by_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_connection_snapshot(connection, pin_ids, pin_ids_by_index) do
    with {:ok, from_pin_id} <-
           fetch_scene_connection_endpoint(connection, "from_pin_original_id"),
         {:ok, to_pin_id} <-
           fetch_scene_connection_endpoint(connection, "to_pin_original_id"),
         :ok <- validate_scene_connection_endpoint(from_pin_id, pin_ids),
         :ok <- validate_scene_connection_endpoint(to_pin_id, pin_ids),
         :ok <-
           validate_scene_connection_endpoint_index(
             connection,
             :from,
             from_pin_id,
             pin_ids_by_index
           ),
         :ok <-
           validate_scene_connection_endpoint_index(
             connection,
             :to,
             to_pin_id,
             pin_ids_by_index
           ),
         :ok <- validate_scene_connection_waypoints(connection),
         true <-
           RoutePoints.enough_points?(
             from_pin_id,
             to_pin_id,
             connection["waypoints"] || []
           ) do
      changeset =
        SceneConnection.create_changeset(
          %SceneConnection{},
          connection_restore_attrs(connection, from_pin_id, to_pin_id)
        )

      if changeset.valid?,
        do: :ok,
        else: {:error, {:invalid_scene_connection_snapshot, connection["original_id"], changeset.errors}}
    else
      false ->
        {:error, {:invalid_scene_connection_route, connection["original_id"]}}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_scene_connection_waypoints(%{"waypoints" => waypoints}) when is_list(waypoints), do: :ok

  defp validate_scene_connection_waypoints(connection) do
    {:error, {:invalid_scene_connection_waypoints, connection["original_id"], connection["waypoints"]}}
  end

  defp fetch_scene_connection_endpoint(connection, key) do
    case Map.fetch(connection, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, id} when is_integer(id) and id > 0 -> {:ok, id}
      {:ok, value} -> {:error, {:invalid_scene_connection_endpoint, key, value}}
      :error -> {:error, {:missing_scene_connection_endpoint, key}}
    end
  end

  defp validate_scene_connection_endpoint(nil, _pin_ids), do: :ok

  defp validate_scene_connection_endpoint(pin_id, pin_ids) do
    if MapSet.member?(pin_ids, pin_id),
      do: :ok,
      else: {:error, {:scene_connection_pin_not_in_snapshot, pin_id}}
  end

  defp validate_scene_connection_endpoint_index(connection, endpoint, pin_id, pin_ids_by_index) do
    {layer_key, pin_key} = scene_connection_endpoint_index_keys(endpoint)
    layer_index = connection[layer_key]
    pin_index = connection[pin_key]
    indexed_pin_id = Map.get(pin_ids_by_index, {layer_index, pin_index})

    if scene_connection_endpoint_index_matches?(
         pin_id,
         layer_index,
         pin_index,
         indexed_pin_id
       ) do
      :ok
    else
      {:error,
       {:scene_connection_endpoint_index_mismatch, connection["original_id"], endpoint, pin_id, layer_index, pin_index,
        indexed_pin_id}}
    end
  end

  defp scene_connection_endpoint_index_keys(:from), do: {"from_layer_index", "from_pin_index"}

  defp scene_connection_endpoint_index_keys(:to), do: {"to_layer_index", "to_pin_index"}

  defp scene_connection_endpoint_index_matches?(nil, nil, nil, nil), do: true
  defp scene_connection_endpoint_index_matches?(nil, _layer_index, _pin_index, _indexed_pin_id), do: false

  defp scene_connection_endpoint_index_matches?(pin_id, _layer_index, _pin_index, indexed_pin_id),
    do: pin_id == indexed_pin_id

  defp validate_scene_child_payloads(data, scene_id) do
    validators = [
      {data.layers, :scene_layer, &scene_layer_restore_changeset(&1, scene_id)},
      {data.zones, :scene_zone, &scene_zone_restore_changeset(&1, scene_id)},
      {data.pins, :scene_pin, &scene_pin_restore_changeset(&1, scene_id)},
      {data.annotations, :scene_annotation, &scene_annotation_restore_changeset(&1, scene_id)}
    ]

    Enum.reduce_while(validators, :ok, fn {entries, label, changeset_fun}, :ok ->
      case validate_scene_child_entries(entries, label, changeset_fun) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_ambient_flow_payloads(ambient_flows, scene_id) do
    with :ok <-
           validate_unique_non_nil(
             Enum.map(ambient_flows, & &1["flow_id"]),
             :scene_ambient_flow_flow_id
           ) do
      validate_scene_ambient_flow_entries(ambient_flows, scene_id)
    end
  end

  defp validate_scene_ambient_flow_entries(ambient_flows, scene_id) do
    Enum.reduce_while(ambient_flows, :ok, fn ambient_flow, :ok ->
      case validate_scene_ambient_flow_payload(ambient_flow, scene_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scene_ambient_flow_payload(ambient_flow, scene_id) do
    changeset =
      SceneAmbientFlow.changeset(
        %SceneAmbientFlow{scene_id: scene_id},
        ambient_flow_restore_attrs(ambient_flow)
      )

    validation_errors =
      changeset
      |> Ecto.Changeset.traverse_errors(&format_scene_changeset_error/1)
      |> add_ambient_flow_type_errors(ambient_flow)

    normalized_config = Ecto.Changeset.get_field(changeset, :trigger_config)

    cond do
      validation_errors != %{} ->
        {:error, {:invalid_scene_child_snapshot, :scene_ambient_flow, ambient_flow["original_id"], validation_errors}}

      normalized_config != ambient_flow["trigger_config"] ->
        {:error,
         {:invalid_scene_ambient_flow_trigger_config, ambient_flow["original_id"], ambient_flow["trigger_config"]}}

      true ->
        :ok
    end
  end

  defp add_ambient_flow_type_errors(errors, ambient_flow) do
    []
    |> maybe_add_ambient_flow_type_error(
      "flow_id",
      is_integer(ambient_flow["flow_id"]) and ambient_flow["flow_id"] > 0
    )
    |> maybe_add_ambient_flow_type_error(
      "priority",
      is_integer(ambient_flow["priority"]) and ambient_flow["priority"] >= 0
    )
    |> maybe_add_ambient_flow_type_error("enabled", is_boolean(ambient_flow["enabled"]))
    |> maybe_add_ambient_flow_type_error(
      "position",
      is_integer(ambient_flow["position"]) and ambient_flow["position"] >= 0
    )
    |> Enum.reduce(errors, fn field, acc ->
      Map.put(acc, field, ["has invalid type or value"])
    end)
  end

  defp maybe_add_ambient_flow_type_error(fields, _field, true), do: fields
  defp maybe_add_ambient_flow_type_error(fields, field, false), do: [field | fields]

  defp validate_scene_ambient_flow_ownership(repo, ambient_flows, scene) do
    flow_ids = Enum.map(ambient_flows, & &1["flow_id"])

    projects_by_flow_id =
      Flow
      |> where([flow], flow.id in ^flow_ids and is_nil(flow.deleted_at))
      |> select([flow], {flow.id, flow.project_id})
      |> repo.all()
      |> Map.new()

    validate_scene_ambient_flow_owners(projects_by_flow_id, ambient_flows, scene)
  end

  defp validate_scene_ambient_flow_owners(projects_by_flow_id, ambient_flows, scene) do
    flow_ids = Enum.map(ambient_flows, & &1["flow_id"])

    case Enum.find(flow_ids, &(Map.get(projects_by_flow_id, &1) != scene.project_id)) do
      nil ->
        :ok

      flow_id ->
        case Map.fetch(projects_by_flow_id, flow_id) do
          :error ->
            {:error, {:scene_ambient_flow_flow_not_found, flow_id}}

          {:ok, actual_project_id} ->
            {:error, {:scene_ambient_flow_flow_project_mismatch, flow_id, scene.project_id, actual_project_id}}
        end
    end
  end

  defp validate_scene_external_reference_ownership_from_locked(
         scene,
         snapshot,
         plan,
         references,
         owners_by_schema,
         asset_owners
       ) do
    with true <- references == scene_snapshot_reference_ids(plan, snapshot),
         :ok <-
           validate_scene_ambient_flow_owners(
             Map.fetch!(owners_by_schema, Flow),
             plan.ambient_flows,
             scene
           ),
         :ok <-
           validate_scene_project_owned_reference_owners(
             Map.fetch!(owners_by_schema, Flow),
             references.flow_ids,
             scene.project_id,
             :flow
           ),
         :ok <-
           validate_scene_project_owned_reference_owners(
             Map.fetch!(owners_by_schema, Sheet),
             references.sheet_ids,
             scene.project_id,
             :sheet
           ),
         :ok <-
           validate_scene_project_owned_reference_owners(
             Map.fetch!(owners_by_schema, Scene),
             references.scene_ids,
             scene.project_id,
             :scene
           ) do
      validate_scene_asset_reference_owners(
        asset_owners,
        references.asset_ids,
        scene.project_id,
        snapshot
      )
    else
      false -> {:error, :scene_locked_reference_set_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp validate_scene_external_reference_ownership(repo, scene, snapshot, plan) do
    references = scene_snapshot_reference_ids(plan, snapshot)

    with :ok <- validate_scene_ambient_flow_ownership(repo, plan.ambient_flows, scene),
         :ok <-
           validate_scene_project_owned_references(
             repo,
             Flow,
             references.flow_ids,
             scene.project_id,
             :flow
           ),
         :ok <-
           validate_scene_project_owned_references(
             repo,
             Sheet,
             references.sheet_ids,
             scene.project_id,
             :sheet
           ),
         :ok <-
           validate_scene_project_owned_references(
             repo,
             Scene,
             references.scene_ids,
             scene.project_id,
             :scene
           ) do
      validate_scene_asset_references(
        repo,
        references.asset_ids,
        scene.project_id,
        snapshot
      )
    end
  end

  defp scene_snapshot_reference_ids(plan, snapshot) do
    pin_flow_ids = Enum.map(plan.pins, fn {pin, _layer_id} -> pin["flow_id"] end)
    pin_sheet_ids = Enum.map(plan.pins, fn {pin, _layer_id} -> pin["sheet_id"] end)

    zone_collection_sheet_ids =
      Enum.flat_map(plan.zones, fn {zone, _layer_id} ->
        scene_zone_collection_sheet_ids(zone)
      end)

    zone_flow_ids =
      plan.zones
      |> Enum.filter(fn {zone, _layer_id} -> zone["target_type"] == "flow" end)
      |> Enum.map(fn {zone, _layer_id} -> zone["target_id"] end)

    zone_scene_ids =
      plan.zones
      |> Enum.filter(fn {zone, _layer_id} -> zone["target_type"] == "scene" end)
      |> Enum.map(fn {zone, _layer_id} -> zone["target_id"] end)

    ambient_flow_ids = Enum.map(plan.ambient_flows, & &1["flow_id"])

    zone_asset_ids =
      Enum.map(plan.zones, fn {zone, _layer_id} -> zone["label_icon_asset_id"] end)

    pin_asset_ids =
      Enum.map(plan.pins, fn {pin, _layer_id} -> pin["icon_asset_id"] end)

    %{
      flow_ids: compact_scene_reference_ids(pin_flow_ids ++ zone_flow_ids ++ ambient_flow_ids),
      sheet_ids: compact_scene_reference_ids(pin_sheet_ids ++ zone_collection_sheet_ids),
      scene_ids: compact_scene_reference_ids(zone_scene_ids),
      asset_ids: compact_scene_reference_ids([snapshot["background_asset_id"] | zone_asset_ids ++ pin_asset_ids])
    }
  end

  defp scene_zone_collection_sheet_ids(%{"action_type" => "collection", "action_data" => %{"items" => items}})
       when is_list(items) do
    Enum.map(items, & &1["sheet_id"])
  end

  defp scene_zone_collection_sheet_ids(_zone), do: []

  defp compact_scene_reference_ids(ids), do: ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp validate_scene_project_owned_references(repo, schema, ids, project_id, label) do
    owners =
      schema
      |> where([row], row.id in ^ids and is_nil(row.deleted_at))
      |> select([row], {row.id, row.project_id})
      |> repo.all()
      |> Map.new()

    validate_scene_project_owned_reference_owners(owners, ids, project_id, label)
  end

  defp validate_scene_project_owned_reference_owners(owners, ids, project_id, label) do
    case Enum.find(ids, &(Map.get(owners, &1) != project_id)) do
      nil ->
        :ok

      id ->
        case Map.fetch(owners, id) do
          :error ->
            {:error, {:scene_reference_not_found, label, id}}

          {:ok, owner_project_id} ->
            {:error, {:scene_reference_project_mismatch, label, id, project_id, owner_project_id}}
        end
    end
  end

  defp validate_scene_asset_references(repo, asset_ids, project_id, snapshot) do
    owners =
      Asset
      |> where([asset], asset.id in ^asset_ids)
      |> select([asset], {asset.id, asset.project_id})
      |> repo.all()
      |> Map.new()

    validate_scene_asset_reference_owners(owners, asset_ids, project_id, snapshot)
  end

  defp validate_scene_asset_reference_owners(owners, asset_ids, project_id, snapshot) do
    Enum.reduce_while(asset_ids, :ok, fn asset_id, :ok ->
      case Map.fetch(owners, asset_id) do
        {:ok, ^project_id} ->
          {:cont, :ok}

        {:ok, owner_project_id} ->
          {:halt, {:error, {:scene_reference_project_mismatch, :asset, asset_id, project_id, owner_project_id}}}

        :error ->
          validate_missing_scene_asset_reference(snapshot, asset_id)
      end
    end)
  end

  defp validate_missing_scene_asset_reference(snapshot, asset_id) do
    if scene_snapshot_asset_materializable?(snapshot, asset_id) do
      {:cont, :ok}
    else
      {:halt, {:error, {:scene_asset_not_materializable, asset_id}}}
    end
  end

  defp scene_snapshot_asset_materializable?(snapshot, asset_id) do
    id = to_string(asset_id)
    metadata = get_in(snapshot, ["asset_metadata", id])

    is_binary(get_in(snapshot, ["asset_blob_hashes", id])) and
      is_map(metadata) and
      is_binary(metadata["filename"]) and
      is_binary(metadata["content_type"])
  end

  defp validate_scene_child_entries(entries, label, changeset_fun) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      data = restore_entry_data(entry)
      changeset = changeset_fun.(entry)

      if changeset.valid? do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          {:invalid_scene_child_snapshot, label, data["original_id"],
           Ecto.Changeset.traverse_errors(
             changeset,
             &format_scene_changeset_error/1
           )}}}
      end
    end)
  end

  defp scene_layer_restore_changeset(layer, scene_id) do
    SceneLayer.create_changeset(
      %SceneLayer{scene_id: scene_id},
      %{
        name: layer["name"],
        is_default: Map.get(layer, "is_default", false),
        position: Map.get(layer, "position", 0),
        visible: Map.get(layer, "visible", true),
        fog_enabled: Map.get(layer, "fog_enabled", false)
      }
    )
  end

  defp scene_zone_restore_changeset({zone, layer_id}, scene_id) do
    attrs =
      zone
      |> zone_restore_attrs()
      |> Map.merge(%{
        layer_id: layer_id,
        label_icon_asset_id: zone["label_icon_asset_id"]
      })

    SceneZone.create_changeset(%SceneZone{scene_id: scene_id}, attrs)
  end

  defp scene_pin_restore_changeset({pin, layer_id}, scene_id) do
    attrs =
      pin
      |> pin_base_attrs()
      |> Map.merge(%{
        layer_id: layer_id,
        sheet_id: pin["sheet_id"],
        icon_asset_id: pin["icon_asset_id"]
      })

    ScenePin.create_changeset(%ScenePin{scene_id: scene_id}, attrs)
  end

  defp scene_annotation_restore_changeset({annotation, layer_id}, scene_id) do
    SceneAnnotation.create_changeset(
      %SceneAnnotation{scene_id: scene_id},
      annotation_restore_attrs(annotation, layer_id)
    )
  end

  defp format_scene_changeset_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, formatted ->
      replacement = if is_binary(value), do: value, else: inspect(value)
      String.replace(formatted, "%{#{key}}", replacement)
    end)
  end

  defp validate_scene_snapshot_uniqueness(data) do
    with :ok <-
           validate_unique_non_nil(
             Enum.map(data.pins, fn {pin, _layer_id} -> pin["shortcut"] end),
             :scene_pin_shortcut
           ),
         :ok <-
           validate_unique_non_nil(
             Enum.map(data.zones, fn {zone, _layer_id} -> zone["shortcut"] end),
             :scene_zone_shortcut
           ),
         true <-
           Enum.count(data.pins, fn {pin, _layer_id} ->
             pin["is_leader"] == true
           end) <= 1 do
      :ok
    else
      false -> {:error, :multiple_scene_leaders_in_snapshot}
      {:error, _reason} = error -> error
    end
  end

  defp validate_unique_non_nil(values, label) do
    values = Enum.reject(values, &is_nil/1)

    if length(values) == MapSet.size(MapSet.new(values)),
      do: :ok,
      else: {:error, {:duplicate_scene_snapshot_value, label}}
  end

  defp removed_scene_child_ids(repo, schema, scene_id, target_ids) do
    current_ids =
      repo.all(from(row in schema, where: row.scene_id == ^scene_id, select: row.id))

    current_ids -- target_ids
  end

  defp reconcile_scene_children(repo, scene, snapshot, plan, opts) do
    delete_scene_children_absent_from_snapshot(repo, scene.id, plan)
    neutralize_scene_unique_fields(repo, scene.id)

    with {:ok, layer_data} <-
           restore_layers(
             repo,
             scene.id,
             snapshot["layers"] || [],
             snapshot,
             scene.project_id,
             opts
           ),
         {:ok, orphan_data} <-
           restore_orphan_entities(
             repo,
             scene.id,
             snapshot,
             scene.project_id,
             opts
           ),
         {:ok, _connection_count} <-
           restore_connections(
             repo,
             scene.id,
             snapshot["connections"] || [],
             Map.put(layer_data, -1, %{pin_ids: orphan_data.pin_ids})
           ),
         :ok <-
           reconcile_scene_ambient_flows(
             repo,
             scene.id,
             snapshot["ambient_flows"] || []
           ) do
      {:ok, %{pin_ids: plan.pin_ids, zone_ids: plan.zone_ids}}
    end
  end

  defp delete_scene_children_absent_from_snapshot(repo, scene_id, plan) do
    delete_absent_scene_rows(
      repo,
      SceneConnection,
      scene_id,
      plan.connection_ids
    )

    delete_absent_scene_rows(
      repo,
      SceneAnnotation,
      scene_id,
      plan.annotation_ids
    )

    delete_absent_scene_rows(repo, ScenePin, scene_id, plan.pin_ids)
    delete_absent_scene_rows(repo, SceneZone, scene_id, plan.zone_ids)
    delete_absent_scene_rows(repo, SceneLayer, scene_id, plan.layer_ids)
  end

  defp delete_absent_scene_rows(repo, schema, scene_id, []) do
    repo.delete_all(from(row in schema, where: row.scene_id == ^scene_id))
  end

  defp delete_absent_scene_rows(repo, schema, scene_id, target_ids) do
    repo.delete_all(
      from(row in schema,
        where: row.scene_id == ^scene_id and row.id not in ^target_ids
      )
    )
  end

  defp neutralize_scene_unique_fields(repo, scene_id) do
    repo.update_all(
      from(pin in ScenePin, where: pin.scene_id == ^scene_id),
      set: [shortcut: nil, is_leader: false]
    )

    repo.update_all(
      from(zone in SceneZone, where: zone.scene_id == ^scene_id),
      set: [shortcut: nil]
    )
  end

  defp reconcile_scene_references(project_id, plan, restored) do
    with :ok <-
           reconcile_reference_items(
             plan.removed_pin_ids,
             &delete_scene_pin_references/1
           ),
         :ok <-
           reconcile_reference_items(
             plan.removed_zone_ids,
             &delete_scene_zone_references/1
           ),
         :ok <-
           reconcile_reference_items(
             scene_rows_by_id(restored.pin_ids, ScenePin),
             &update_scene_pin_references(&1, project_id)
           ),
         :ok <-
           reconcile_reference_items(
             scene_rows_by_id(restored.zone_ids, SceneZone),
             &update_scene_zone_references(&1, project_id)
           ) do
      {:ok, :reconciled}
    end
  end

  defp update_scene_pin_references(pin, project_id) do
    with :ok <-
           References.update_scene_pin_entity_references(
             pin,
             project_id: project_id
           ) do
      References.update_scene_pin_variable_references(pin,
        project_id: project_id
      )
    end
  end

  defp update_scene_zone_references(zone, project_id) do
    with :ok <-
           References.update_scene_zone_entity_references(
             zone,
             project_id: project_id
           ) do
      References.update_scene_zone_variable_references(zone,
        project_id: project_id
      )
    end
  end

  defp delete_scene_pin_references(pin_id) do
    with :ok <-
           normalize_reference_delete_result(References.delete_scene_pin_entity_references(pin_id)) do
      References.delete_scene_pin_variable_references(pin_id)
    end
  end

  defp delete_scene_zone_references(zone_id) do
    with :ok <-
           normalize_reference_delete_result(References.delete_scene_zone_entity_references(zone_id)) do
      References.delete_scene_zone_variable_references(zone_id)
    end
  end

  defp reconcile_reference_items(items, reconcile_fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case reconcile_fun.(item) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
        result -> {:halt, {:error, {:unexpected_reference_reconcile_result, result}}}
      end
    end)
  end

  defp normalize_reference_delete_result(:ok), do: :ok

  defp normalize_reference_delete_result({count, nil}) when is_integer(count) and count >= 0, do: :ok

  defp normalize_reference_delete_result({:error, _reason} = error), do: error

  defp normalize_reference_delete_result(result), do: {:error, {:unexpected_reference_delete_result, result}}

  defp scene_rows_by_id([], _schema), do: []

  defp scene_rows_by_id(ids, schema) do
    Repo.all(from(row in schema, where: row.id in ^ids))
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
      id: layer_data["original_id"],
      scene_id: scene_id,
      name: layer_data["name"],
      is_default: Map.get(layer_data, "is_default", false),
      position: Map.get(layer_data, "position", layer_idx),
      visible: Map.get(layer_data, "visible", true),
      fog_enabled: Map.get(layer_data, "fog_enabled", false),
      inserted_at: now,
      updated_at: now
    }

    case upsert_restore_rows(repo, SceneLayer, [attrs]) do
      {1, _} -> layer_data["original_id"]
      {0, _} -> raise "Failed to upsert scene layer during restore"
    end
  end

  defp insert_layer_zones(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: :ok

  defp insert_layer_zones(repo, scene_id, layer_id, zones_data, now, snapshot, project_id, opts) do
    Enum.each(zones_data, fn zone_data ->
      attrs =
        zone_data
        |> build_zone_attrs(
          scene_id,
          layer_id,
          now,
          snapshot,
          project_id,
          opts
        )
        |> Map.put(:id, zone_data["original_id"])

      insert_single!(repo, SceneZone, attrs, "scene zone")
    end)
  end

  defp build_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    zone_data
    |> zone_restore_attrs()
    |> Map.merge(%{
      scene_id: scene_id,
      layer_id: layer_id,
      label_icon_asset_id: resolve_scene_asset(zone_data["label_icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp zone_restore_attrs(d) do
    %{
      name: d["name"],
      shortcut: d["shortcut"],
      hidden: Map.get(d, "hidden", false),
      vertices: d["vertices"],
      fill_color: d["fill_color"],
      border_color: d["border_color"],
      border_width: Map.get(d, "border_width", 2),
      border_style: Map.get(d, "border_style", "solid"),
      opacity: Map.get(d, "opacity", 0.3),
      target_type: d["target_type"],
      target_id: d["target_id"],
      tooltip: d["tooltip"],
      position: Map.get(d, "position", 0),
      locked: Map.get(d, "locked", false),
      action_type: Map.get(d, "action_type", "action"),
      action_data: Map.get(d, "action_data", %{"assignments" => []}),
      label_mode: Map.get(d, "label_mode", "text"),
      label_font_size: Map.get(d, "label_font_size", 12),
      label_font_family: Map.get(d, "label_font_family", "system"),
      label_font_weight: Map.get(d, "label_font_weight", "600"),
      label_font_style: Map.get(d, "label_font_style", "normal"),
      condition: d["condition"],
      condition_effect: Map.get(d, "condition_effect", "hide"),
      is_walkable: Map.get(d, "is_walkable", false)
    }
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
      border_width: Map.get(d, "border_width", 2),
      border_style: Map.get(d, "border_style", "solid"),
      opacity: Map.get(d, "opacity", 0.3),
      position: Map.get(d, "position", 0),
      locked: Map.get(d, "locked", false)
    }
  end

  defp zone_label_defaults(d) do
    %{
      label_mode: Map.get(d, "label_mode", "text"),
      label_font_size: Map.get(d, "label_font_size", 12),
      label_font_family: Map.get(d, "label_font_family", "system"),
      label_font_weight: Map.get(d, "label_font_weight", "600"),
      label_font_style: Map.get(d, "label_font_style", "normal"),
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
    case upsert_restore_rows(repo, schema, [attrs]) do
      {1, _} -> :ok
      {0, _} -> raise "Failed to upsert #{label} during restore"
    end
  end

  defp insert_layer_pins(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: []

  defp insert_layer_pins(repo, scene_id, layer_id, pins_data, now, snapshot, project_id, opts) do
    Enum.map(pins_data, fn pin_data ->
      attrs =
        pin_data
        |> build_pin_attrs(
          scene_id,
          layer_id,
          now,
          snapshot,
          project_id,
          opts
        )
        |> Map.put(:id, pin_data["original_id"])

      case upsert_restore_rows(repo, ScenePin, [attrs]) do
        {1, _} -> pin_data["original_id"]
        {0, _} -> raise "Failed to upsert scene pin during restore"
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
        hidden: Map.get(d, "hidden", false),
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
        pin_type: Map.get(d, "pin_type", "location"),
        opacity: Map.get(d, "opacity", 1.0),
        size: Map.get(d, "size", "md"),
        position: Map.get(d, "position", 0),
        locked: Map.get(d, "locked", false),
        patrol_mode: Map.get(d, "patrol_mode", "none"),
        patrol_speed: Map.get(d, "patrol_speed", 1.0),
        patrol_pause_ms: Map.get(d, "patrol_pause_ms", 0)
      },
      pin_action_defaults(d)
    )
  end

  defp pin_action_defaults(d) do
    %{
      condition_effect: Map.get(d, "condition_effect", "hide"),
      is_playable: Map.get(d, "is_playable", false),
      is_leader: Map.get(d, "is_leader", false)
    }
  end

  defp insert_layer_annotations(_repo, _scene_id, _layer_id, [], _now), do: :ok

  defp insert_layer_annotations(repo, scene_id, layer_id, annotations_data, now) do
    Enum.each(annotations_data, fn ann_data ->
      attrs =
        ann_data
        |> annotation_restore_attrs(layer_id)
        |> Map.merge(%{
          id: ann_data["original_id"],
          scene_id: scene_id,
          inserted_at: now,
          updated_at: now
        })

      insert_single!(repo, SceneAnnotation, attrs, "scene annotation")
    end)
  end

  defp annotation_restore_attrs(annotation, layer_id) do
    %{
      layer_id: layer_id,
      text: annotation["text"],
      position_x: annotation["position_x"],
      position_y: annotation["position_y"],
      font_size: Map.get(annotation, "font_size", "md"),
      color: annotation["color"],
      position: Map.get(annotation, "position", 0),
      locked: Map.get(annotation, "locked", false)
    }
  end

  defp restore_connections(_repo, _scene_id, [], _layer_data), do: {:ok, 0}

  defp restore_connections(repo, scene_id, connections_data, _layer_data) do
    now = MaterializationHelpers.now()

    entries =
      Enum.map(connections_data, fn conn ->
        conn
        |> connection_restore_attrs(
          conn["from_pin_original_id"],
          conn["to_pin_original_id"]
        )
        |> Map.merge(%{
          id: conn["original_id"],
          scene_id: scene_id,
          inserted_at: now,
          updated_at: now
        })
      end)

    {count, _} = upsert_restore_rows(repo, SceneConnection, entries)
    {:ok, count}
  end

  defp connection_restore_attrs(conn, from_pin_id, to_pin_id) do
    %{
      from_pin_id: from_pin_id,
      to_pin_id: to_pin_id,
      line_style: Map.get(conn, "line_style", "solid"),
      line_width: Map.get(conn, "line_width", 2),
      color: conn["color"],
      label: conn["label"],
      bidirectional: Map.get(conn, "bidirectional", true),
      show_label: Map.get(conn, "show_label", true),
      waypoints: Map.get(conn, "waypoints", []),
      from_stop: Map.get(conn, "from_stop", true),
      to_stop: Map.get(conn, "to_stop", true),
      from_pause_ms: conn["from_pause_ms"],
      to_pause_ms: conn["to_pause_ms"]
    }
  end

  defp reconcile_scene_ambient_flows(repo, scene_id, ambient_flows) do
    repo.delete_all(
      from(ambient_flow in SceneAmbientFlow,
        where: ambient_flow.scene_id == ^scene_id
      )
    )

    now = MaterializationHelpers.now()

    entries =
      Enum.map(ambient_flows, fn ambient_flow ->
        ambient_flow
        |> ambient_flow_restore_attrs()
        |> Map.merge(%{
          id: ambient_flow["original_id"],
          scene_id: scene_id,
          inserted_at: now,
          updated_at: now
        })
      end)

    MaterializationHelpers.insert_all(repo, SceneAmbientFlow, entries)
  end

  defp ambient_flow_restore_attrs(ambient_flow) do
    %{
      flow_id: ambient_flow["flow_id"],
      trigger_type: ambient_flow["trigger_type"],
      trigger_config: ambient_flow["trigger_config"],
      priority: ambient_flow["priority"],
      enabled: ambient_flow["enabled"],
      position: ambient_flow["position"]
    }
  end

  defp upsert_restore_rows(_repo, _schema, []), do: {0, nil}

  defp upsert_restore_rows(repo, schema, entries) do
    Enum.each(entries, &upsert_restore_row(repo, schema, &1))

    {length(entries), nil}
  end

  defp upsert_restore_row(repo, schema, entry) do
    id = Map.fetch!(entry, :id)
    scene_id = Map.fetch!(entry, :scene_id)

    updates =
      entry
      |> Map.drop([:id, :scene_id, :inserted_at])
      |> Map.to_list()

    case repo.update_all(
           from(row in schema,
             where: row.id == ^id and row.scene_id == ^scene_id
           ),
           set: updates
         ) do
      {1, _} -> :ok
      {0, _} -> insert_restore_row!(repo, schema, entry)
    end
  end

  defp insert_restore_row!(repo, schema, entry) do
    case repo.insert_all(schema, [entry]) do
      {1, _} -> :ok
      {count, _} -> raise "Expected one restored #{inspect(schema)} row, got #{count}"
    end
  end

  defp insert_scene_layers(_repo, _scene_id, [], _now), do: {:ok, %{}}

  defp insert_scene_layers(repo, scene_id, layers_data, now) do
    layers_data
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {layer_data, layer_idx}, {:ok, id_map} ->
      attrs =
        Map.merge(
          %{
            scene_id: scene_id,
            name: layer_data["name"],
            is_default: Map.get(layer_data, "is_default", false),
            position: Map.get(layer_data, "position", layer_idx),
            visible: Map.get(layer_data, "visible", true),
            fog_enabled: Map.get(layer_data, "fog_enabled", false)
          },
          MaterializationHelpers.timestamps(now)
        )

      case MaterializationHelpers.insert_one_returning_id(repo, SceneLayer, attrs) do
        {:ok, id} ->
          {:cont, {:ok, Map.put(id_map, layer_data["original_id"], id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_scene_layer_children(repo, scene_id, layers_data, layer_id_map, snapshot, project_id, now, opts) do
    layers_data
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, %{zone_id_map: %{}, pin_id_map: %{}, annotation_id_map: %{}, pin_ids_by_layer: %{}}},
      fn {layer_data, layer_idx}, {:ok, acc} ->
        layer_id = Map.fetch!(layer_id_map, layer_data["original_id"])

        with {:ok, zone_inserted} <-
               insert_layer_zones_with_ids(
                 repo,
                 scene_id,
                 layer_id,
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
                 layer_id,
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
                 layer_id,
                 layer_data["annotations"] || [],
                 now
               ) do
          updated =
            acc
            |> Map.update!(
              :zone_id_map,
              &Map.merge(&1, zone_inserted)
            )
            |> Map.update!(
              :pin_id_map,
              &Map.merge(&1, pin_inserted)
            )
            |> Map.update!(
              :annotation_id_map,
              &Map.merge(&1, annotation_inserted)
            )
            |> put_layer_pin_ids(layer_idx, layer_data["pins"] || [], pin_inserted)

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
         zone_id_map: zone_inserted,
         pin_id_map: pin_inserted,
         annotation_id_map: annotation_inserted,
         pin_ids:
           Enum.map(
             snapshot["orphan_pins"] || [],
             &Map.fetch!(pin_inserted, &1["original_id"])
           )
       }}
    end
  end

  defp put_layer_pin_ids(results, layer_idx, pins_data, pin_id_map) do
    pin_ids = Enum.map(pins_data, &Map.fetch!(pin_id_map, &1["original_id"]))
    Map.update!(results, :pin_ids_by_layer, &Map.put(&1, layer_idx, pin_ids))
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

  defp insert_layer_zones_with_ids(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: {:ok, %{}}

  defp insert_layer_zones_with_ids(repo, scene_id, layer_id, zones_data, now, snapshot, project_id, opts) do
    with :ok <- validate_scene_zone_target_contracts(zones_data) do
      insert_scene_snapshot_rows(repo, SceneZone, zones_data, fn zone_data ->
        build_materialized_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts)
      end)
    end
  end

  defp build_materialized_zone_attrs(zone_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    attrs = zone_base_attrs(zone_data)
    {target_type, target_id} = resolve_materialized_zone_target(attrs, zone_data, project_id, opts)

    with {:ok, action_data} <-
           resolve_materialized_zone_action_data(
             attrs,
             zone_data,
             project_id,
             opts
           ) do
      {:ok,
       Map.merge(attrs, %{
         scene_id: scene_id,
         layer_id: layer_id,
         target_type: target_type,
         target_id: target_id,
         action_data: action_data,
         label_icon_asset_id:
           resolve_scene_asset(
             zone_data["label_icon_asset_id"],
             snapshot,
             project_id,
             opts
           ),
         inserted_at: now,
         updated_at: now
       })}
    end
  end

  defp resolve_materialized_zone_action_data(
         %{action_type: "collection", action_data: %{"items" => items}} = attrs,
         zone_data,
         project_id,
         opts
       ) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, remapped_items} ->
      source_sheet_id = item["sheet_id"]
      resolved_sheet_id = resolve_scene_sheet_id(source_sheet_id, project_id, opts)

      if is_nil(source_sheet_id) or not is_nil(resolved_sheet_id) do
        remapped_item = Map.put(item, "sheet_id", resolved_sheet_id)
        {:cont, {:ok, [remapped_item | remapped_items]}}
      else
        {:halt,
         {:error, {:unresolved_scene_zone_collection_sheet, zone_data["original_id"], index, item["id"], source_sheet_id}}}
      end
    end)
    |> case do
      {:ok, remapped_items} ->
        {:ok, Map.put(attrs.action_data, "items", Enum.reverse(remapped_items))}

      {:error, _reason} = error ->
        error
    end
  end

  defp resolve_materialized_zone_action_data(attrs, _zone_data, _project_id, _opts), do: {:ok, attrs.action_data}

  defp resolve_materialized_zone_target(%{action_type: "action"}, zone_data, project_id, opts) do
    case normalize_zone_target(zone_data["target_type"], zone_data["target_id"]) do
      {target_type, target_id} when target_type in ["flow", "scene"] ->
        schema = if target_type == "flow", do: Flow, else: Scene
        map_key = if target_type == "flow", do: :flow, else: :scene

        case MaterializationHelpers.resolve_project_external_ref(
               target_id,
               schema,
               map_key,
               project_id,
               opts
             ) do
          nil -> {nil, nil}
          resolved_id -> {target_type, resolved_id}
        end

      {nil, nil} ->
        {nil, nil}
    end
  end

  defp resolve_materialized_zone_target(attrs, _zone_data, _project_id, _opts), do: {attrs.target_type, attrs.target_id}

  defp insert_layer_pins_with_ids(_repo, _scene_id, _layer_id, [], _now, _snapshot, _project_id, _opts), do: {:ok, %{}}

  defp insert_layer_pins_with_ids(repo, scene_id, layer_id, pins_data, now, snapshot, project_id, opts) do
    insert_scene_snapshot_rows(repo, ScenePin, pins_data, fn pin_data ->
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
  end

  defp build_materialized_pin_attrs(pin_data, scene_id, layer_id, now, snapshot, project_id, opts) do
    pin_data
    |> pin_base_attrs()
    |> Map.merge(%{
      scene_id: scene_id,
      layer_id: layer_id,
      flow_id:
        MaterializationHelpers.resolve_project_external_ref(
          pin_data["flow_id"],
          Flow,
          :flow,
          project_id,
          opts
        ),
      sheet_id: resolve_scene_sheet_id(pin_data["sheet_id"], project_id, opts),
      icon_asset_id: resolve_scene_asset(pin_data["icon_asset_id"], snapshot, project_id, opts),
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_layer_annotations_with_ids(_repo, _scene_id, _layer_id, [], _now), do: {:ok, %{}}

  defp insert_layer_annotations_with_ids(repo, scene_id, layer_id, annotations_data, now) do
    insert_scene_snapshot_rows(repo, SceneAnnotation, annotations_data, fn ann_data ->
      Map.merge(
        %{
          scene_id: scene_id,
          layer_id: layer_id,
          text: ann_data["text"],
          position_x: ann_data["position_x"],
          position_y: ann_data["position_y"],
          font_size: Map.get(ann_data, "font_size", "md"),
          color: ann_data["color"],
          position: Map.get(ann_data, "position", 0),
          locked: Map.get(ann_data, "locked", false)
        },
        MaterializationHelpers.timestamps(now)
      )
    end)
  end

  defp insert_scene_snapshot_rows(repo, schema, snapshots, attrs_fun) do
    Enum.reduce_while(snapshots, {:ok, %{}}, fn snapshot, {:ok, id_map} ->
      with {:ok, attrs} <- normalize_scene_snapshot_row_attrs(attrs_fun.(snapshot)),
           {:ok, id} <-
             MaterializationHelpers.insert_one_returning_id(repo, schema, attrs) do
        {:cont, {:ok, Map.put(id_map, snapshot["original_id"], id)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_scene_snapshot_row_attrs({:ok, attrs}) when is_map(attrs), do: {:ok, attrs}

  defp normalize_scene_snapshot_row_attrs({:error, _reason} = error), do: error
  defp normalize_scene_snapshot_row_attrs(attrs) when is_map(attrs), do: {:ok, attrs}

  defp insert_scene_connections(_repo, _scene_id, [], _pin_ids_by_layer, _now), do: {:ok, %{}}

  defp insert_scene_connections(repo, scene_id, connections_data, pin_ids_by_layer, now) do
    insert_scene_snapshot_rows(repo, SceneConnection, connections_data, fn conn ->
      from_pin_id =
        lookup_scene_pin(pin_ids_by_layer, conn["from_layer_index"], conn["from_pin_index"])

      to_pin_id =
        lookup_scene_pin(pin_ids_by_layer, conn["to_layer_index"], conn["to_pin_index"])

      Map.merge(
        %{
          scene_id: scene_id,
          from_pin_id: from_pin_id,
          to_pin_id: to_pin_id,
          line_style: Map.get(conn, "line_style", "solid"),
          line_width: Map.get(conn, "line_width", 2),
          color: conn["color"],
          label: conn["label"],
          bidirectional: Map.get(conn, "bidirectional", true),
          show_label: Map.get(conn, "show_label", true),
          waypoints: Map.get(conn, "waypoints", []),
          from_stop: Map.get(conn, "from_stop", true),
          to_stop: Map.get(conn, "to_stop", true),
          from_pause_ms: conn["from_pause_ms"],
          to_pause_ms: conn["to_pause_ms"]
        },
        MaterializationHelpers.timestamps(now)
      )
    end)
  end

  defp insert_scene_ambient_flows(repo, scene_id, ambient_flows, project_id, now, opts) do
    with {:ok, pairs} <-
           build_materialized_ambient_flow_entries(
             repo,
             scene_id,
             ambient_flows,
             project_id,
             now,
             opts
           ) do
      insert_materialized_ambient_flow_pairs(repo, pairs)
    end
  end

  defp insert_materialized_ambient_flow_pairs(repo, pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {snapshot, attrs}, {:ok, id_map} ->
      case MaterializationHelpers.insert_one_returning_id(repo, SceneAmbientFlow, attrs) do
        {:ok, id} ->
          {:cont, {:ok, Map.put(id_map, snapshot["original_id"], id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_materialized_ambient_flow_entries(repo, scene_id, ambient_flows, project_id, now, opts) do
    ambient_flows
    |> Enum.reduce_while({:ok, []}, fn ambient_flow, {:ok, pairs} ->
      case resolve_materialized_ambient_flow_id(
             repo,
             ambient_flow["flow_id"],
             project_id,
             opts
           ) do
        {:ok, nil} ->
          {:cont, {:ok, pairs}}

        {:ok, flow_id} ->
          entry =
            ambient_flow
            |> ambient_flow_restore_attrs()
            |> Map.put(:flow_id, flow_id)
            |> Map.merge(%{
              scene_id: scene_id,
              inserted_at: now,
              updated_at: now
            })

          {:cont, {:ok, [{ambient_flow, entry} | pairs]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pairs} ->
        {:ok, Enum.reverse(pairs)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_materialized_ambient_flow_id(repo, source_flow_id, project_id, opts) do
    flow_id =
      MaterializationHelpers.resolve_project_external_ref(
        source_flow_id,
        Flow,
        :flow,
        project_id,
        opts
      )

    cond do
      is_nil(flow_id) ->
        {:ok, nil}

      repo.exists?(
        from(flow in Flow,
          where: flow.id == ^flow_id and flow.project_id == ^project_id
        )
      ) ->
        {:ok, flow_id}

      true ->
        {:error, {:materialized_scene_ambient_flow_project_mismatch, source_flow_id, flow_id, project_id}}
    end
  end

  defp lookup_scene_pin(_pin_ids_by_layer, nil, nil), do: nil

  defp lookup_scene_pin(pin_ids_by_layer, layer_idx, pin_idx) do
    pin_ids_by_layer
    |> Map.get(layer_idx, [])
    |> Enum.at(pin_idx)
  end

  defp resolve_scene_background_asset(asset_id, snapshot, project_id, opts) do
    resolve_scene_asset(asset_id, snapshot, project_id, opts)
  end

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
    case Keyword.get(opts, :asset_mode, :reuse) do
      :drop -> :drop
      :copy -> :copy
      _mode -> :reuse
    end
  end

  defp snapshot_default(snapshot, key, default), do: Map.get(snapshot, key, default)

  # ========== Diff Snapshots ==========

  @layer_compare_fields ~w(name is_default visible fog_enabled)
  @pin_compare_fields ~w(pin_type icon color opacity label shortcut hidden size flow_id tooltip sheet_id icon_asset_id condition condition_effect locked patrol_mode patrol_speed patrol_pause_ms)
  @zone_compare_fields ~w(name shortcut hidden vertices fill_color border_color border_width border_style opacity target_type target_id tooltip action_type action_data label_mode label_font_size label_font_family label_font_weight label_font_style label_icon_asset_id condition condition_effect locked)
  @annotation_compare_fields ~w(text font_size color locked)
  @connection_compare_fields ~w(line_style line_width color label bidirectional show_label waypoints from_stop to_stop from_pause_ms to_pause_ms)
  @ambient_flow_compare_fields ~w(
    flow_id trigger_type trigger_config priority enabled position
  )

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
      "exploration_display_mode",
      :property,
      dgettext("scenes", "Changed exploration display")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "background_asset_id",
      :property,
      dgettext("scenes", "Changed background")
    )
    |> diff_ambient_flows(
      old_snapshot["ambient_flows"] || [],
      new_snapshot["ambient_flows"] || []
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

  defp diff_ambient_flows(changes, old_ambient_flows, new_ambient_flows) do
    identity = fn ambient_flow ->
      cond do
        ambient_flow["original_id"] ->
          {:original_id, ambient_flow["original_id"]}

        ambient_flow["flow_id"] ->
          {:flow_id, ambient_flow["flow_id"]}

        true ->
          nil
      end
    end

    {matched, added, removed} =
      DiffHelpers.match_by_keys(
        old_ambient_flows,
        new_ambient_flows,
        [identity]
      )

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, @ambient_flow_compare_fields)
      end)

    changes
    |> append_items(added, :ambient_flow, :added, fn ambient_flow ->
      dgettext("scenes", "Added ambient flow %{flow_id}", flow_id: ambient_flow["flow_id"])
    end)
    |> append_items(removed, :ambient_flow, :removed, fn ambient_flow ->
      dgettext("scenes", "Removed ambient flow %{flow_id}", flow_id: ambient_flow["flow_id"])
    end)
    |> append_modified_items(modified, :ambient_flow, fn ambient_flow ->
      dgettext("scenes", "Modified ambient flow %{flow_id}", flow_id: ambient_flow["flow_id"])
    end)
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
      |> scan_ambient_flow_refs(snapshot["ambient_flows"] || [])

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
      |> scan_zone_collection_sheet_refs(zone, prefix)
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
      |> scan_zone_collection_sheet_refs(zone, prefix)
    end)
  end

  defp scan_zone_collection_sheet_refs(
         refs,
         %{"action_type" => "collection", "action_data" => %{"items" => items}},
         prefix
       )
       when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{"sheet_id" => sheet_id}, item_index}, acc ->
        maybe_add_ref(
          acc,
          :sheet,
          sheet_id,
          prefix <>
            dgettext(
              "scenes",
              " — collection item %{item} sheet",
              item: item_index
            )
        )

      {_item, _item_index}, acc ->
        acc
    end)
  end

  defp scan_zone_collection_sheet_refs(refs, _zone, _prefix), do: refs

  defp scan_ambient_flow_refs(refs, ambient_flows) do
    ambient_flows
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {ambient_flow, index}, acc ->
      maybe_add_ref(
        acc,
        :flow,
        ambient_flow["flow_id"],
        dgettext("scenes", "Ambient flow %{index}", index: index)
      )
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
      Sheet,
      :sheet,
      project_id,
      opts
    )
  end

  defp scene_root_container do
    %{"name" => dgettext("scenes", "Scene root")}
  end
end

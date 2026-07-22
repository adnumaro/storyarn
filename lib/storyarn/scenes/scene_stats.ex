defmodule Storyarn.Scenes.SceneStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.HealthChecker
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets.Sheet

  # ===========================================================================
  # Stats
  # ===========================================================================

  @doc """
  Returns per-scene zone, pin, and connection counts in a single query.
  Returns `%{scene_id => %{zone_count, pin_count, connection_count}}`.
  """
  def scene_stats_for_project(project_id) do
    from(s in Scene,
      left_join: z in SceneZone,
      on: z.scene_id == s.id,
      left_join: p in ScenePin,
      on: p.scene_id == s.id,
      left_join: c in SceneConnection,
      on: c.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: s.id,
      select:
        {s.id,
         %{
           zone_count: count(z.id, :distinct),
           pin_count: count(p.id, :distinct),
           connection_count: count(c.id, :distinct)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the count of scenes that have a background image.
  Returns an integer.
  """
  def scenes_with_background_count(project_id) do
    Repo.one(
      from(s in Scene,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and not is_nil(s.background_asset_id),
        select: count(s.id)
      )
    )
  end

  # ===========================================================================
  # Dashboard Health Overview
  # ===========================================================================

  @doc """
  Returns the project-wide overview subset of canonical scene health findings.

  The editor runs the full checker for one scene. The dashboard uses bounded,
  aggregate queries for the highest-signal project overview findings while
  reusing `HealthChecker` codes, shape, and severities.
  """
  def list_dashboard_health_findings(project_id) do
    missing_shortcut_findings(project_id) ++
      missing_background_findings(project_id) ++
      empty_scene_findings(project_id) ++
      missing_layer_findings(project_id) ++
      invalid_layer_findings(project_id) ++
      invalid_connection_endpoint_findings(project_id) ++
      stale_pin_reference_findings(project_id) ++
      stale_zone_target_findings(project_id) ++
      stale_ambient_flow_findings(project_id)
  end

  defp empty_scene_findings(project_id) do
    from(s in Scene,
      left_join: z in SceneZone,
      on: z.scene_id == s.id,
      left_join: p in ScenePin,
      on: p.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: [s.id, s.name],
      having: count(z.id) == 0 and count(p.id) == 0,
      select: %{scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
    |> findings(:empty_scene)
  end

  defp missing_background_findings(project_id) do
    from(s in Scene,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.background_asset_id),
      select: %{scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
    |> findings(:missing_background)
  end

  defp missing_shortcut_findings(project_id) do
    from(s in Scene,
      where:
        s.project_id == ^project_id and is_nil(s.deleted_at) and
          (is_nil(s.shortcut) or fragment("btrim(?) = ''", s.shortcut)),
      select: %{scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
    |> findings(:missing_scene_shortcut)
  end

  defp missing_layer_findings(project_id) do
    from(s in Scene,
      left_join: layer in SceneLayer,
      on: layer.scene_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      group_by: [s.id, s.name],
      having: count(layer.id) == 0,
      select: %{scene_id: s.id, scene_name: s.name}
    )
    |> Repo.all()
    |> findings(:missing_scene_layer)
  end

  defp invalid_layer_findings(project_id) do
    invalid_pin_layer_findings(project_id) ++
      invalid_zone_layer_findings(project_id) ++
      invalid_annotation_layer_findings(project_id)
  end

  defp invalid_pin_layer_findings(project_id) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: pin.scene_id == scene.id,
      left_join: layer in SceneLayer,
      on: layer.id == pin.layer_id and layer.scene_id == scene.id,
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(pin.layer_id) and is_nil(layer.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: pin.id,
        entity_type: "pin",
        entity_label: pin.label
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:invalid_layer_reference)
  end

  defp invalid_zone_layer_findings(project_id) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: zone.scene_id == scene.id,
      left_join: layer in SceneLayer,
      on: layer.id == zone.layer_id and layer.scene_id == scene.id,
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(zone.layer_id) and is_nil(layer.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: zone.id,
        entity_type: "zone",
        entity_label: zone.name
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:invalid_layer_reference)
  end

  defp invalid_annotation_layer_findings(project_id) do
    from(annotation in SceneAnnotation,
      join: scene in Scene,
      on: annotation.scene_id == scene.id,
      left_join: layer in SceneLayer,
      on: layer.id == annotation.layer_id and layer.scene_id == scene.id,
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(annotation.layer_id) and is_nil(layer.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: annotation.id,
        entity_type: "annotation",
        entity_label: annotation.text
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:invalid_layer_reference)
  end

  defp invalid_connection_endpoint_findings(project_id) do
    invalid_endpoint = invalid_connection_endpoint_filter()

    from(connection in SceneConnection,
      join: scene in Scene,
      on: connection.scene_id == scene.id,
      left_join: from_pin in ScenePin,
      on: from_pin.id == connection.from_pin_id and from_pin.scene_id == scene.id,
      left_join: to_pin in ScenePin,
      on: to_pin.id == connection.to_pin_id and to_pin.scene_id == scene.id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ^invalid_endpoint,
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: connection.id,
        entity_type: "connection",
        entity_label: connection.label
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:invalid_connection_endpoint)
  end

  defp invalid_connection_endpoint_filter do
    dynamic(
      [connection, _scene, from_pin, to_pin],
      (not is_nil(connection.from_pin_id) and is_nil(from_pin.id)) or
        (not is_nil(connection.to_pin_id) and is_nil(to_pin.id)) or
        (not is_nil(connection.from_pin_id) and connection.from_pin_id == connection.to_pin_id)
    )
  end

  defp stale_pin_reference_findings(project_id) do
    stale_pin_sheet_findings(project_id) ++ stale_pin_flow_findings(project_id)
  end

  defp stale_pin_sheet_findings(project_id) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: pin.scene_id == scene.id,
      left_join: sheet in Sheet,
      on: sheet.id == pin.sheet_id and sheet.project_id == scene.project_id and is_nil(sheet.deleted_at),
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(pin.sheet_id) and is_nil(sheet.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: pin.id,
        entity_type: "pin",
        entity_label: pin.label
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:stale_pin_sheet_reference)
  end

  defp stale_pin_flow_findings(project_id) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: pin.scene_id == scene.id,
      left_join: flow in Flow,
      on: flow.id == pin.flow_id and flow.project_id == scene.project_id and is_nil(flow.deleted_at),
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(pin.flow_id) and is_nil(flow.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: pin.id,
        entity_type: "pin",
        entity_label: pin.label
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:stale_pin_flow_reference)
  end

  defp stale_zone_target_findings(project_id) do
    stale_zone_flow_findings(project_id) ++ stale_zone_scene_findings(project_id)
  end

  defp stale_zone_flow_findings(project_id) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: zone.scene_id == scene.id,
      left_join: flow in Flow,
      on: flow.id == zone.target_id and flow.project_id == scene.project_id and is_nil(flow.deleted_at),
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          zone.target_type == "flow" and not is_nil(zone.target_id) and is_nil(flow.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: zone.id,
        entity_type: "zone",
        entity_label: zone.name,
        target_type: "flow"
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:stale_zone_target)
  end

  defp stale_zone_scene_findings(project_id) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: zone.scene_id == scene.id,
      left_join: target in Scene,
      on: target.id == zone.target_id and target.project_id == scene.project_id and is_nil(target.deleted_at),
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          zone.target_type == "scene" and not is_nil(zone.target_id) and is_nil(target.id),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: zone.id,
        entity_type: "zone",
        entity_label: zone.name,
        target_type: "scene"
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:stale_zone_target)
  end

  defp stale_ambient_flow_findings(project_id) do
    from(ambient in SceneAmbientFlow,
      join: scene in Scene,
      on: ambient.scene_id == scene.id,
      left_join: flow in Flow,
      on: flow.id == ambient.flow_id and flow.project_id == scene.project_id and is_nil(flow.deleted_at),
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and ambient.enabled == true and
          (is_nil(ambient.flow_id) or is_nil(flow.id)),
      select: %{
        scene_id: scene.id,
        scene_name: scene.name,
        entity_id: ambient.id,
        entity_type: "ambient_flow",
        entity_label: nil
      },
      limit: 50
    )
    |> Repo.all()
    |> findings(:stale_ambient_flow_reference)
  end

  defp findings(rows, code) do
    Enum.map(rows, fn row ->
      details =
        row
        |> Map.take([:scene_name, :entity_label, :target_type])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      HealthChecker.finding(code, %{
        scene_id: row.scene_id,
        entity_type: Map.get(row, :entity_type, "scene"),
        entity_id: Map.get(row, :entity_id),
        details: details
      })
    end)
  end
end

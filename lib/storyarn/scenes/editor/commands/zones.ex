defmodule Storyarn.Scenes.Editor.Commands.Zones do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo
  alias Storyarn.Scenes.Editor.Commands.Positions
  alias Storyarn.Scenes.Editor.Commands.ReferenceIntegrity
  alias Storyarn.Scenes.Editor.Commands.Scenes
  alias Storyarn.Scenes.Editor.Commands.Shortcuts
  alias Storyarn.Scenes.References
  alias Storyarn.Scenes.SceneZone

  # A zone's shortcut is a referenceable variable, so create/update/delete change
  # the vocabulary every health surface type-checks against — not just the zone
  # count. Vertices are also health inputs (`invalid_zone_geometry` and
  # `element_outside_canvas`), so the optimized drag path must invalidate too.
  def create_zone(scene_id, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    scene_id
    |> ReferenceIntegrity.with_active_scene_lock(
      [project_lock: :update],
      fn scene ->
        zone = %SceneZone{scene_id: scene.id}

        with :ok <-
               Positions.lock_requested_layer_for_scene(scene.id, attrs),
             {:ok, attrs} <-
               ReferenceIntegrity.lock_zone_references(
                 scene,
                 zone,
                 attrs
               ) do
          attrs = maybe_generate_zone_shortcut(attrs, scene.id, nil)
          position = Positions.next_position(SceneZone, scene.id)

          zone
          |> SceneZone.create_changeset(Map.put(attrs, "position", position))
          |> persist_zone_with_references(scene.project_id)
        end
      end
    )
    |> Scenes.broadcast_scene_dashboard_result(scene_id)
  end

  def update_zone(%SceneZone{} = zone, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    zone.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(
      [project_lock: :update],
      fn scene ->
        with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
             :ok <-
               Positions.lock_requested_layer_for_scene(
                 scene.id,
                 attrs,
                 locked_zone.layer_id
               ),
             {:ok, attrs} <-
               ReferenceIntegrity.lock_zone_references(
                 scene,
                 locked_zone,
                 attrs
               ) do
          locked_zone
          |> SceneZone.update_changeset(maybe_regenerate_zone_shortcut(locked_zone, attrs))
          |> persist_zone_with_references(scene.project_id)
        end
      end
    )
    |> Scenes.broadcast_scene_dashboard_result(zone.scene_id)
  end

  @doc """
  Updates only vertices (optimized for drag operations).
  """
  def update_zone_vertices(%SceneZone{} = zone, attrs) do
    zone.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(
      [project_lock: :update],
      fn scene ->
        with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
             {:ok, _attrs} <-
               ReferenceIntegrity.lock_zone_references(
                 scene,
                 locked_zone,
                 %{}
               ),
             {:ok, updated_zone} <-
               locked_zone
               |> SceneZone.update_vertices_changeset(attrs)
               |> Repo.update() do
          {:ok, {updated_zone, scene.project_id}}
        end
      end
    )
    |> Scenes.broadcast_scene_dashboard_project_result()
  end

  def delete_zone(%SceneZone{} = zone) do
    zone.scene_id
    |> ReferenceIntegrity.with_active_scene_lock(fn scene ->
      with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
           :ok <- delete_zone_references(locked_zone.id) do
        Repo.delete(locked_zone)
      end
    end)
    |> Scenes.broadcast_scene_dashboard_result(zone.scene_id)
  end

  def change_zone(%SceneZone{} = zone, attrs \\ %{}) do
    SceneZone.update_changeset(zone, attrs)
  end

  # Generate shortcut from name on create if name present and no shortcut in attrs
  defp maybe_generate_zone_shortcut(attrs, scene_id, exclude_id) do
    name = attrs["name"]
    shortcut = attrs["shortcut"]

    if is_binary(name) && name != "" && is_nil(shortcut) do
      Map.put(attrs, "shortcut", Shortcuts.generate_zone(name, scene_id, exclude_id))
    else
      attrs
    end
  end

  # Regenerate shortcut on update when name changes
  defp maybe_regenerate_zone_shortcut(zone, attrs) do
    attrs = MapAccess.stringify_keys(attrs)
    new_name = attrs["name"]

    cond do
      # Name is changing → regenerate shortcut
      is_binary(new_name) && new_name != "" && new_name != zone.name ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_zone(new_name, zone.scene_id, zone.id)
        )

      # No shortcut exists but name does → generate
      is_nil(zone.shortcut) && is_binary(zone.name) && zone.name != "" &&
          !Map.has_key?(attrs, "name") ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_zone(zone.name, zone.scene_id, zone.id)
        )

      true ->
        attrs
    end
  end

  defp lock_zone_for_scene(zone_id, scene_id) do
    case Repo.one(
           from(zone in SceneZone,
             where: zone.id == ^zone_id and zone.scene_id == ^scene_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SceneZone{} = zone -> {:ok, zone}
      nil -> {:error, :zone_not_found}
    end
  end

  defp persist_zone_with_references(changeset, project_id) do
    with {:ok, zone} <- Repo.insert_or_update(changeset),
         :ok <-
           References.update_zone_entity_references(
             zone,
             project_id: project_id
           ),
         :ok <-
           References.update_zone_variable_references(
             zone,
             project_id: project_id
           ) do
      {:ok, zone}
    end
  end

  defp delete_zone_references(zone_id) do
    with {count, nil} when is_integer(count) <-
           References.delete_zone_entity_references(zone_id),
         :ok <- References.delete_zone_variable_references(zone_id) do
      :ok
    else
      result -> {:error, {:zone_reference_delete_failed, zone_id, result}}
    end
  end
end

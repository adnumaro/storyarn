defmodule Storyarn.Scenes.ZoneCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneReferenceIntegrity
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shortcuts

  @doc """
  Lists zones for a map, with optional layer_id filter.
  """
  def list_zones(scene_id, opts \\ []) do
    query =
      from(z in SceneZone,
        where: z.scene_id == ^scene_id,
        order_by: [asc: z.position]
      )

    query =
      case Keyword.get(opts, :layer_id) do
        nil -> query
        layer_id -> where(query, [z], z.layer_id == ^layer_id)
      end

    query
    |> preload([:label_icon_asset])
    |> Repo.all()
  end

  def get_zone(zone_id) do
    SceneZone
    |> Repo.get(zone_id)
    |> Repo.preload(:label_icon_asset)
  end

  def get_zone!(zone_id) do
    SceneZone
    |> Repo.get!(zone_id)
    |> Repo.preload(:label_icon_asset)
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_zone(scene_id, zone_id) do
    Repo.one(from(z in SceneZone, where: z.scene_id == ^scene_id and z.id == ^zone_id, preload: [:label_icon_asset]))
  end

  @doc """
  Gets a zone by ID, scoped to a specific map. Raises if not found.
  """
  def get_zone!(scene_id, zone_id) do
    Repo.one!(from(z in SceneZone, where: z.scene_id == ^scene_id and z.id == ^zone_id, preload: [:label_icon_asset]))
  end

  def create_zone(scene_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(
      scene_id,
      [project_lock: :update],
      fn scene ->
        zone = %SceneZone{scene_id: scene.id}

        with :ok <-
               PositionUtils.lock_requested_layer_for_scene(scene.id, attrs),
             {:ok, attrs} <-
               SceneReferenceIntegrity.lock_zone_references(
                 scene,
                 zone,
                 attrs
               ) do
          attrs = maybe_generate_zone_shortcut(attrs, scene.id, nil)
          position = PositionUtils.next_position(SceneZone, scene.id)

          zone
          |> SceneZone.create_changeset(Map.put(attrs, "position", position))
          |> persist_zone_with_references(scene.project_id)
        end
      end
    )
  end

  def update_zone(%SceneZone{} = zone, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    SceneReferenceIntegrity.with_active_scene_lock(
      zone.scene_id,
      [project_lock: :update],
      fn scene ->
        with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
             :ok <-
               PositionUtils.lock_requested_layer_for_scene(
                 scene.id,
                 attrs,
                 locked_zone.layer_id
               ),
             {:ok, attrs} <-
               SceneReferenceIntegrity.lock_zone_references(
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
  end

  @doc """
  Updates only vertices (optimized for drag operations).
  """
  def update_zone_vertices(%SceneZone{} = zone, attrs) do
    SceneReferenceIntegrity.with_active_scene_lock(
      zone.scene_id,
      [project_lock: :update],
      fn scene ->
        with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
             {:ok, _attrs} <-
               SceneReferenceIntegrity.lock_zone_references(
                 scene,
                 locked_zone,
                 %{}
               ) do
          locked_zone
          |> SceneZone.update_vertices_changeset(attrs)
          |> Repo.update()
        end
      end
    )
  end

  def delete_zone(%SceneZone{} = zone) do
    SceneReferenceIntegrity.with_active_scene_lock(zone.scene_id, fn scene ->
      with {:ok, locked_zone} <- lock_zone_for_scene(zone.id, scene.id),
           :ok <- delete_zone_references(locked_zone.id) do
        Repo.delete(locked_zone)
      end
    end)
  end

  def change_zone(%SceneZone{} = zone, attrs \\ %{}) do
    SceneZone.update_changeset(zone, attrs)
  end

  @doc """
  Lists zones that perform an explicit player action, ordered by position.
  """
  def list_actionable_zones(scene_id) do
    Repo.all(
      from(z in SceneZone,
        where: z.scene_id == ^scene_id and z.action_type in ["action", "collection"],
        order_by: [asc: z.position]
      )
    )
  end

  @doc """
  Finds the zone on a given map that targets a specific child map.
  Returns `nil` if no linking zone is found.
  """
  def get_zone_linking_to_scene(parent_scene_id, child_scene_id) do
    Repo.one(
      from(z in SceneZone,
        where: z.scene_id == ^parent_scene_id and z.target_type == "scene" and z.target_id == ^child_scene_id,
        limit: 1
      )
    )
  end

  # Generate shortcut from name on create if name present and no shortcut in attrs
  defp maybe_generate_zone_shortcut(attrs, scene_id, exclude_id) do
    name = attrs["name"]
    shortcut = attrs["shortcut"]

    if is_binary(name) && name != "" && is_nil(shortcut) do
      Map.put(attrs, "shortcut", Shortcuts.generate_zone_shortcut(name, scene_id, exclude_id))
    else
      attrs
    end
  end

  # Regenerate shortcut on update when name changes
  defp maybe_regenerate_zone_shortcut(zone, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    new_name = attrs["name"]

    cond do
      # Name is changing → regenerate shortcut
      is_binary(new_name) && new_name != "" && new_name != zone.name ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_zone_shortcut(new_name, zone.scene_id, zone.id)
        )

      # No shortcut exists but name does → generate
      is_nil(zone.shortcut) && is_binary(zone.name) && zone.name != "" &&
          !Map.has_key?(attrs, "name") ->
        Map.put(
          attrs,
          "shortcut",
          Shortcuts.generate_zone_shortcut(zone.name, zone.scene_id, zone.id)
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
           References.update_scene_zone_entity_references(
             zone,
             project_id: project_id
           ),
         :ok <-
           References.update_scene_zone_variable_references(
             zone,
             project_id: project_id
           ) do
      {:ok, zone}
    end
  end

  defp delete_zone_references(zone_id) do
    with {count, nil} when is_integer(count) <-
           References.delete_scene_zone_entity_references(zone_id),
         :ok <- References.delete_scene_zone_variable_references(zone_id) do
      :ok
    else
      result -> {:error, {:zone_reference_delete_failed, zone_id, result}}
    end
  end
end

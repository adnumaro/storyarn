defmodule Storyarn.GlobalSearch.SceneSearch do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.GlobalSearch.Persistence.SceneAnnotationRecord
  alias Storyarn.GlobalSearch.Persistence.SceneConnectionRecord
  alias Storyarn.GlobalSearch.Persistence.SceneLayerRecord
  alias Storyarn.GlobalSearch.Persistence.ScenePinRecord
  alias Storyarn.GlobalSearch.Persistence.SceneRecord
  alias Storyarn.GlobalSearch.Persistence.SceneZoneRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers

  @default_limit 20
  @max_deep_limit 50
  @max_deep_offset 10_000

  @spec get(integer(), integer()) :: SceneRecord.t() | nil
  def get(project_id, scene_id) do
    Repo.one(
      from(scene in SceneRecord,
        where:
          scene.id == ^scene_id and scene.project_id == ^project_id and
            is_nil(scene.deleted_at)
      )
    )
  end

  @spec search_in_projects([integer()], String.t(), keyword()) :: [SceneRecord.t()]
  def search_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_limit)
    query = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query == "" ->
        Repo.all(
          from(scene in SceneRecord,
            where: scene.project_id in ^project_ids and is_nil(scene.deleted_at),
            order_by: [desc: scene.updated_at, desc: scene.id],
            limit: ^limit
          ),
          log: false
        )

      true ->
        pattern = "%#{SearchHelpers.sanitize_like_query(query)}%"

        Repo.all(
          from(scene in SceneRecord,
            where: scene.project_id in ^project_ids and is_nil(scene.deleted_at),
            where: ilike(scene.name, ^pattern) or ilike(scene.shortcut, ^pattern),
            order_by: [asc: scene.name],
            limit: ^limit
          ),
          log: false
        )
    end
  end

  @spec search_deep(integer(), String.t(), keyword()) :: [SceneRecord.t()]
  def search_deep(project_id, query, opts \\ []) when is_binary(query) do
    limit = normalize_deep_limit(Keyword.get(opts, :limit, @default_limit))
    offset = normalize_deep_offset(Keyword.get(opts, :offset, 0))
    query = String.trim(query)

    if query == "" do
      Repo.all(
        from(scene in SceneRecord,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          order_by: [desc: scene.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      pattern = "%#{SearchHelpers.sanitize_like_query(query)}%"
      run_deep_search(project_id, pattern, limit, offset)
    end
  end

  defp run_deep_search(project_id, pattern, limit, offset) do
    Repo.all(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        where:
          ilike(scene.name, ^pattern) or
            ilike(scene.shortcut, ^pattern) or
            ilike(scene.description, ^pattern) or
            scene.id in subquery(scene_ids_matching_layers(project_id, pattern)) or
            scene.id in subquery(scene_ids_matching_pins(project_id, pattern)) or
            scene.id in subquery(scene_ids_matching_zones(project_id, pattern)) or
            scene.id in subquery(scene_ids_matching_annotations(project_id, pattern)) or
            scene.id in subquery(scene_ids_matching_connections(project_id, pattern)),
        order_by: [asc: scene.name, asc: scene.id],
        limit: ^limit,
        offset: ^offset
      ),
      log: false
    )
  end

  defp scene_ids_matching_layers(project_id, pattern) do
    from(layer in SceneLayerRecord,
      join: scene in SceneRecord,
      on: scene.id == layer.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(layer.name, ^pattern),
      select: layer.scene_id
    )
  end

  defp scene_ids_matching_pins(project_id, pattern) do
    from(pin in ScenePinRecord,
      join: scene in SceneRecord,
      on: scene.id == pin.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where:
        ilike(pin.label, ^pattern) or
          ilike(pin.shortcut, ^pattern) or
          ilike(pin.tooltip, ^pattern),
      select: pin.scene_id
    )
  end

  defp scene_ids_matching_zones(project_id, pattern) do
    from(zone in SceneZoneRecord,
      join: scene in SceneRecord,
      on: scene.id == zone.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where:
        ilike(zone.name, ^pattern) or
          ilike(zone.shortcut, ^pattern) or
          ilike(zone.tooltip, ^pattern),
      select: zone.scene_id
    )
  end

  defp scene_ids_matching_annotations(project_id, pattern) do
    from(annotation in SceneAnnotationRecord,
      join: scene in SceneRecord,
      on: scene.id == annotation.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(annotation.text, ^pattern),
      select: annotation.scene_id
    )
  end

  defp scene_ids_matching_connections(project_id, pattern) do
    from(connection in SceneConnectionRecord,
      join: scene in SceneRecord,
      on: scene.id == connection.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      where: ilike(connection.label, ^pattern),
      select: connection.scene_id
    )
  end

  defp normalize_deep_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_deep_limit)
  defp normalize_deep_limit(_limit), do: @default_limit

  defp normalize_deep_offset(offset) when is_integer(offset), do: offset |> max(0) |> min(@max_deep_offset)
  defp normalize_deep_offset(_offset), do: 0
end

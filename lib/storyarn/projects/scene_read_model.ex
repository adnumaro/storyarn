defmodule Storyarn.Projects.SceneReadModel do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Repo

  def list_active(project_id) do
    Repo.all(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [asc: scene.position, asc: scene.name, asc: scene.id]
      )
    )
  end

  def list_for_export(project_id, opts \\ []) do
    filter_ids = Keyword.get(opts, :filter_ids, :all)

    query =
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        preload: [:layers, :pins, :zones, :connections, :annotations],
        order_by: [asc: scene.position, asc: scene.name]
      )

    query
    |> maybe_filter_ids(filter_ids)
    |> Repo.all()
  end

  def count(project_id) do
    Repo.aggregate(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
      ),
      :count
    )
  end

  def get_brief(project_id, scene_id) do
    Repo.one(
      from(scene in SceneRecord,
        where:
          scene.project_id == ^project_id and scene.id == ^scene_id and
            is_nil(scene.deleted_at)
      )
    )
  end

  def get_including_deleted(project_id, scene_id) do
    Repo.one(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and scene.id == ^scene_id,
        preload: [:layers, :zones, :pins, connections: [:from_pin, :to_pin]]
      )
    )
  end

  def detect_shortcut_conflicts(_project_id, []), do: []

  def detect_shortcut_conflicts(project_id, shortcuts) do
    Repo.all(
      from(scene in SceneRecord,
        where:
          scene.project_id == ^project_id and scene.shortcut in ^shortcuts and
            is_nil(scene.deleted_at),
        select: scene.shortcut
      )
    )
  end

  def list_shortcuts(project_id) do
    from(scene in SceneRecord,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      select: scene.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp maybe_filter_ids(query, :all), do: query
  defp maybe_filter_ids(query, ids) when is_list(ids), do: where(query, [scene], scene.id in ^ids)
end

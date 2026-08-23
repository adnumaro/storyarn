defmodule Storyarn.Projects.SceneImportPersistence do
  @moduledoc "Project-owned writer used only by project import/reconstitution."

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.SceneAnnotationRecord
  alias Storyarn.Projects.Persistence.SceneConnectionRecord
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SceneZoneRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  def import_scene(project_id, attrs) do
    %SceneRecord{project_id: project_id}
    |> SceneRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def import_layer(scene_id, attrs) do
    %SceneLayerRecord{scene_id: scene_id}
    |> SceneLayerRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def import_pin(scene_id, attrs) do
    %ScenePinRecord{scene_id: scene_id}
    |> ScenePinRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def import_zone(scene_id, attrs) do
    %SceneZoneRecord{scene_id: scene_id}
    |> SceneZoneRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def bulk_insert_connections(attrs_list), do: bulk_insert(SceneConnectionRecord, attrs_list)
  def bulk_insert_annotations(attrs_list), do: bulk_insert(SceneAnnotationRecord, attrs_list)

  def soft_delete_by_shortcut(project_id, shortcut) do
    Repo.update_all(
      from(scene in SceneRecord,
        where:
          scene.project_id == ^project_id and scene.shortcut == ^shortcut and
            is_nil(scene.deleted_at)
      ),
      set: [deleted_at: TimeHelpers.now()]
    )
  end

  def link_parent(%SceneRecord{} = scene, parent_id) do
    scene
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end

  def link_pin_flow_id(pin_id, flow_id) do
    ScenePinRecord
    |> Repo.get!(pin_id)
    |> Ecto.Changeset.change(%{flow_id: flow_id})
    |> Repo.update!()
  end

  def link_zone_target(zone_id, target_type, target_id) do
    SceneZoneRecord
    |> Repo.get!(zone_id)
    |> SceneZoneRecord.update_changeset(%{target_type: target_type, target_id: target_id})
    |> Repo.update!()
  end

  defp bulk_insert(schema, attrs_list, chunk_size \\ 500) do
    attrs_list
    |> Enum.chunk_every(chunk_size)
    |> Enum.flat_map(fn chunk ->
      {_count, inserted} = Repo.insert_all(schema, chunk, returning: [:id])
      inserted
    end)
  end
end

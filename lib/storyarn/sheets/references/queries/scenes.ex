defmodule Storyarn.Sheets.References.Queries.Scenes do
  @moduledoc """
  Sheet-oriented Scene backlink and appearance reads.

  These queries translate References-local Scene projections into the source
  labels used by Sheet backlinks; no Scene domain model crosses the boundary.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.References.Data.EntityReferenceRecord
  alias Storyarn.Sheets.References.Data.ScenePinRecord
  alias Storyarn.Sheets.References.Data.SceneRecord
  alias Storyarn.Sheets.References.Data.SceneZoneRecord

  @doc false
  def project_id(scene_id) do
    Repo.one(from(scene in SceneRecord, where: scene.id == ^scene_id, select: scene.project_id))
  end

  @doc false
  def pin_backlinks(target_type, target_id, project_id) do
    from(reference in EntityReferenceRecord,
      join: pin in ScenePinRecord,
      on: reference.source_type == "scene_pin" and reference.source_id == pin.id,
      join: scene in SceneRecord,
      on: pin.scene_id == scene.id,
      where: reference.target_type == ^target_type and reference.target_id == ^target_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      select: %{
        id: reference.id,
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        pin_label: pin.label,
        scene_id: scene.id,
        scene_name: scene.name
      },
      order_by: [desc: reference.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&backlink(&1, "scene_pin", "pin", &1.pin_label))
  end

  @doc false
  def zone_backlinks(target_type, target_id, project_id) do
    from(reference in EntityReferenceRecord,
      join: zone in SceneZoneRecord,
      on: reference.source_type == "scene_zone" and reference.source_id == zone.id,
      join: scene in SceneRecord,
      on: zone.scene_id == scene.id,
      where: reference.target_type == ^target_type and reference.target_id == ^target_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
      select: %{
        id: reference.id,
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        zone_name: zone.name,
        scene_id: scene.id,
        scene_name: scene.name
      },
      order_by: [desc: reference.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&backlink(&1, "scene_zone", "zone", &1.zone_name))
  end

  @doc false
  def list_sheet_appearances(sheet_id) do
    Repo.all(
      from(zone in SceneZoneRecord,
        join: scene in SceneRecord,
        on: zone.scene_id == scene.id,
        where: zone.target_type == "sheet" and zone.target_id == ^sheet_id,
        select: %{
          element_type: "zone",
          element_name: zone.name,
          scene_id: scene.id,
          scene_name: scene.name
        }
      )
    )
  end

  defp backlink(reference, source_type, element_type, element_label) do
    %{
      id: reference.id,
      source_type: source_type,
      source_id: reference.source_id,
      context: reference.context,
      inserted_at: reference.inserted_at,
      source_info: %{
        type: :scene,
        scene_id: reference.scene_id,
        scene_name: reference.scene_name,
        element_type: element_type,
        element_label: element_label
      }
    }
  end
end

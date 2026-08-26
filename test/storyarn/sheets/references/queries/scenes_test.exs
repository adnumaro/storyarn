defmodule Storyarn.Sheets.References.Queries.ScenesTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets.References.Data.EntityReferenceRecord
  alias Storyarn.Sheets.References.Data.SceneRecord
  alias Storyarn.Sheets.References.Queries.Scenes, as: SceneQueries

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    scene = scene_fixture(project, %{name: "Consumer-owned scene"})

    %{project: project, scene: scene, sheet: sheet}
  end

  test "reads Scene identity and pin Sheet references from local records", %{
    project: project,
    scene: scene,
    sheet: sheet
  } do
    pin_fixture(scene, %{"sheet_id" => sheet.id})

    assert SceneQueries.project_id(scene.id) == project.id
  end

  test "preserves the legacy zone-only appearances contract without active-Scene filtering", %{
    scene: scene,
    sheet: sheet
  } do
    zone = zone_fixture(scene, %{"name" => "Archive entrance"})
    pin_fixture(scene, %{"sheet_id" => sheet.id, "label" => "Ignored pin"})

    Repo.update_all(
      from(zone_record in "scene_zones", where: zone_record.id == ^zone.id),
      set: [target_type: "sheet", target_id: sheet.id]
    )

    Repo.update_all(
      from(scene_record in SceneRecord, where: scene_record.id == ^scene.id),
      set: [deleted_at: ~U[2026-01-01 00:00:00Z]]
    )

    assert SceneQueries.list_sheet_appearances(sheet.id) == [
             %{
               element_type: "zone",
               element_name: "Archive entrance",
               scene_id: scene.id,
               scene_name: "Consumer-owned scene"
             }
           ]
  end

  test "enriches Scene backlinks and excludes sources in deleted Scenes", %{
    project: project,
    scene: scene,
    sheet: sheet
  } do
    pin = pin_fixture(scene, %{"label" => "North gate"})
    zone = zone_fixture(scene, %{"name" => "Inner ward"})

    insert_reference!("scene_pin", pin.id, sheet.id, "pin")
    insert_reference!("scene_zone", zone.id, sheet.id, "zone")

    assert [pin_backlink] = SceneQueries.pin_backlinks("sheet", sheet.id, project.id)

    assert pin_backlink.source_info == %{
             type: :scene,
             scene_id: scene.id,
             scene_name: scene.name,
             element_type: "pin",
             element_label: "North gate"
           }

    assert [zone_backlink] = SceneQueries.zone_backlinks("sheet", sheet.id, project.id)
    assert zone_backlink.source_info.element_label == "Inner ward"

    Repo.update_all(
      from(scene_record in SceneRecord, where: scene_record.id == ^scene.id),
      set: [deleted_at: ~U[2026-01-01 00:00:00Z]]
    )

    assert SceneQueries.pin_backlinks("sheet", sheet.id, project.id) == []
    assert SceneQueries.zone_backlinks("sheet", sheet.id, project.id) == []
  end

  defp insert_reference!(source_type, source_id, target_id, context) do
    %EntityReferenceRecord{}
    |> EntityReferenceRecord.changeset(%{
      source_type: source_type,
      source_id: source_id,
      target_type: "sheet",
      target_id: target_id,
      context: context
    })
    |> Repo.insert!()
  end
end

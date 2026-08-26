defmodule Storyarn.Scenes.References.Commands.EntityProjectionTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.References.Commands.EntityProjection, as: EntityReferenceTracker
  alias Storyarn.Scenes.References.Data.EntityReferenceRecord
  alias Storyarn.Sheets.Sheet

  test "owns shortcutless Sheet references extracted from Scene zones" do
    project = project_fixture()
    scene = scene_fixture(project)
    sheet = sheet_fixture(project, %{name: "Shortcutless target"})
    block = block_fixture(sheet, %{type: "number", variable_name: "hp"})

    Repo.update_all(from(current in Sheet, where: current.id == ^sheet.id),
      set: [shortcut: nil]
    )

    namespace = Integer.to_string(sheet.id)

    cases = [
      {"display", %{"variable_ref" => "#{namespace}.#{block.variable_name}"}, "display"},
      {"action",
       %{
         "assignments" => [
           %{
             "id" => Ecto.UUID.generate(),
             "sheet" => namespace,
             "variable" => block.variable_name,
             "operator" => "set",
             "value_type" => "literal",
             "value" => "1"
           }
         ]
       }, "assignment"}
    ]

    for {action_type, action_data, context} <- cases do
      zone = zone_fixture(scene)

      assert {:ok, updated_zone} =
               Scenes.update_zone(zone, %{
                 "action_type" => action_type,
                 "action_data" => action_data
               })

      assert Repo.exists?(
               from(reference in EntityReferenceRecord,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^updated_zone.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^sheet.id and
                     reference.context == ^context
               )
             )
    end
  end

  test "deduplicates read and write backlinks to the same Sheet" do
    project = project_fixture()
    scene = scene_fixture(project)
    sheet = sheet_fixture(project, %{shortcut: "hero"})

    zone =
      zone_fixture(scene, %{
        "action_type" => "action",
        "action_data" => %{
          "assignments" => [
            %{
              "sheet" => "hero",
              "variable" => "health",
              "operator" => "set",
              "value_type" => "variable_ref",
              "value_sheet" => "hero",
              "value_variable" => "maximum_health"
            }
          ]
        }
      })

    references =
      Repo.all(
        from reference in EntityReferenceRecord,
          where:
            reference.source_type == "scene_zone" and
              reference.source_id == ^zone.id and
              reference.target_type == "sheet" and
              reference.target_id == ^sheet.id
      )

    assert [%EntityReferenceRecord{context: "assignment"}] = references
  end

  test "ignores values outside the Scene pin and zone contracts" do
    assert :ok = EntityReferenceTracker.update_pin_references("not a pin")
    assert :ok = EntityReferenceTracker.update_zone_references("not a zone")
  end
end

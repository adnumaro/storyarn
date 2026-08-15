defmodule Storyarn.Scenes.NumericVariableNamespaceStaleTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes.AmbientFlowCrud
  alias Storyarn.Scenes.PinCrud
  alias Storyarn.Scenes.SceneCrud
  alias Storyarn.Scenes.ZoneCrud
  alias Storyarn.Sheets.Sheet

  test "shortcutless sheet references remain current for scene pins, zones, and ambient flows" do
    project = project_fixture()
    scene = scene_fixture(project)
    flow = flow_fixture(project)
    sheet = sheet_fixture(project, %{name: "Shortcutless"})
    block = block_fixture(sheet, %{type: "number", variable_name: "health"})

    Repo.update_all(from(s in Sheet, where: s.id == ^sheet.id), set: [shortcut: nil])
    namespace = Integer.to_string(sheet.id)

    pin = pin_fixture(scene)

    assert {:ok, pin} =
             PinCrud.update_pin(pin, %{
               "condition" => variable_condition(namespace, block.variable_name)
             })

    zone = zone_fixture(scene)

    assert {:ok, zone} =
             ZoneCrud.update_zone(zone, %{
               "action_type" => "action",
               "action_data" => %{
                 "assignments" => [variable_assignment(namespace, block.variable_name)]
               }
             })

    assert {:ok, ambient_flow} =
             AmbientFlowCrud.create_ambient_flow(scene.id, %{
               "flow_id" => flow.id,
               "trigger_type" => "on_event",
               "trigger_config" => %{
                 "variable_ref" => "#{namespace}.#{block.variable_name}"
               }
             })

    assert [%{pin_id: pin_id, stale: false}] =
             SceneCrud.check_stale_scene_pin_variable_references(block.id, project.id)

    assert [%{zone_id: zone_id, stale: false}] =
             SceneCrud.check_stale_scene_zone_variable_references(block.id, project.id)

    assert [%{ambient_flow_id: ambient_flow_id, stale: false}] =
             SceneCrud.check_stale_scene_ambient_flow_variable_references(block.id, project.id)

    assert pin_id == pin.id
    assert zone_id == zone.id
    assert ambient_flow_id == ambient_flow.id
  end

  defp variable_condition(sheet_namespace, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_namespace,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end

  defp variable_assignment(sheet_namespace, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_namespace,
      "variable" => variable_name,
      "operator" => "set",
      "value_type" => "literal",
      "value" => "1"
    }
  end
end

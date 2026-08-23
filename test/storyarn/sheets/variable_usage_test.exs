defmodule Storyarn.Sheets.VariableUsageTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.References.VariableReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

    block =
      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "placeholder" => "0"}
      })

    %{project: project, flow: flow, sheet: sheet, block: block}
  end

  test "reads grouped usage and batched staleness from the shared projection", ctx do
    node =
      node_fixture(ctx.flow, %{
        type: "instruction",
        data: %{
          "assignments" => [
            %{
              "id" => "assign_1",
              "sheet" => ctx.sheet.shortcut,
              "variable" => ctx.block.variable_name,
              "operator" => "set",
              "value" => "100",
              "value_type" => "literal"
            }
          ]
        }
      })

    assert :ok = VariableReferenceTracker.update_references(node)
    assert Sheets.count_variable_usage(ctx.block.id) == %{"write" => 1}

    assert [%{source_type: "flow_node", stale: false}] =
             Sheets.check_stale_variable_references(ctx.block.id, ctx.project.id)

    assert {:ok, _sheet} = Sheets.update_sheet(ctx.sheet, %{shortcut: "mc.renamed"})

    assert [%{source_type: "flow_node", stale: true}] =
             Sheets.check_stale_variable_references(ctx.block.id, ctx.project.id)

    assert Sheets.count_stale_variable_references(
             [ctx.block.id, -1],
             ctx.project.id
           ) == %{ctx.block.id => 1}
  end

  test "resolves scene-owned usage without routing the read through Scenes", ctx do
    condition = %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "condition_block",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "condition_rule",
              "sheet" => ctx.sheet.shortcut,
              "variable" => ctx.block.variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }

    assignment = %{
      "id" => "assignment",
      "sheet" => ctx.sheet.shortcut,
      "variable" => ctx.block.variable_name,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }

    scene = scene_fixture(ctx.project, %{name: "Town Square"})
    pin = pin_fixture(scene, %{"label" => "Gate", "condition" => condition})

    zone =
      zone_fixture(scene, %{
        "name" => "Fountain",
        "action_type" => "action",
        "action_data" => %{"assignments" => [assignment]}
      })

    assert {:ok, ambient_flow} =
             Scenes.create_ambient_flow(scene.id, %{
               "flow_id" => ctx.flow.id,
               "trigger_type" => "on_event",
               "trigger_config" => %{
                 "variable_ref" => "#{ctx.sheet.shortcut}.#{ctx.block.variable_name}"
               }
             })

    usage = Sheets.check_stale_variable_references(ctx.block.id, ctx.project.id)

    assert Enum.any?(usage, &match?(%{source_type: "scene_pin", pin_id: id} when id == pin.id, &1))
    assert Enum.any?(usage, &match?(%{source_type: "scene_zone", zone_id: id} when id == zone.id, &1))

    assert Enum.any?(
             usage,
             &match?(
               %{source_type: "scene_ambient_flow", ambient_flow_id: id}
               when id == ambient_flow.id,
               &1
             )
           )

    assert Enum.all?(usage, &(&1.stale == false))
  end

  test "shortcutless Sheet references remain current for every Scene source" do
    project = project_fixture()
    scene = scene_fixture(project)
    flow = flow_fixture(project)
    sheet = sheet_fixture(project, %{name: "Shortcutless"})
    block = block_fixture(sheet, %{type: "number", variable_name: "health"})

    Repo.update_all(from(record in Sheet, where: record.id == ^sheet.id), set: [shortcut: nil])
    namespace = Integer.to_string(sheet.id)

    pin = pin_fixture(scene)

    assert {:ok, pin} =
             Scenes.update_pin(pin, %{
               "condition" => variable_condition(namespace, block.variable_name)
             })

    zone = zone_fixture(scene)

    assert {:ok, zone} =
             Scenes.update_zone(zone, %{
               "action_type" => "action",
               "action_data" => %{
                 "assignments" => [variable_assignment(namespace, block.variable_name)]
               }
             })

    assert {:ok, ambient_flow} =
             Scenes.create_ambient_flow(scene.id, %{
               "flow_id" => flow.id,
               "trigger_type" => "on_event",
               "trigger_config" => %{
                 "variable_ref" => "#{namespace}.#{block.variable_name}"
               }
             })

    usage = Sheets.check_stale_variable_references(block.id, project.id)

    assert Enum.any?(usage, &match?(%{pin_id: id, stale: false} when id == pin.id, &1))
    assert Enum.any?(usage, &match?(%{zone_id: id, stale: false} when id == zone.id, &1))

    assert Enum.any?(
             usage,
             &match?(%{ambient_flow_id: id, stale: false} when id == ambient_flow.id, &1)
           )
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

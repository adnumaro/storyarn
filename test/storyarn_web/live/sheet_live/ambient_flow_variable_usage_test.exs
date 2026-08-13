defmodule StoryarnWeb.SheetLive.AmbientFlowVariableUsageTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes

  setup :register_and_log_in_user

  test "references props serialize Scene ambient-flow and pin reads without Flow-only fields", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Hero profile", shortcut: "hero.profile"})

    block =
      block_fixture(sheet, %{
        type: "number",
        variable_name: "health",
        config: %{"label" => "Health"}
      })

    scene = scene_fixture(project, %{name: "Moonlit Courtyard"})
    flow = flow_fixture(project, %{name: "Night ambience"})

    {:ok, _ambient_flow} =
      Scenes.create_ambient_flow(scene.id, %{
        "flow_id" => flow.id,
        "trigger_type" => "on_event",
        "trigger_config" => %{"variable_ref" => "hero.profile.health"}
      })

    pin =
      pin_fixture(scene, %{
        "label" => "North gate",
        "condition" => variable_condition(sheet.shortcut, block.variable_name)
      })

    url =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    {:ok, view, _html} = live(conn, url)
    await_async(view)
    render_click(view, "switch_tab", %{"tab" => "references"})
    await_async(view)

    vue =
      LiveVue.Test.get_vue(
        view,
        name: "live/sheet/show/SheetSurface"
      )

    [usage] = vue.props["panels"]["references"]["variableUsage"]
    reads_by_type = Map.new(usage["reads"], &{&1["sourceType"], &1})

    assert reads_by_type["scene_ambient_flow"] == %{
             "sourceType" => "scene_ambient_flow",
             "sceneId" => scene.id,
             "sceneName" => scene.name,
             "flowName" => flow.name,
             "stale" => false
           }

    assert reads_by_type["scene_pin"] == %{
             "sourceType" => "scene_pin",
             "sceneId" => scene.id,
             "sceneName" => scene.name,
             "pinLabel" => pin.label,
             "stale" => false
           }
  end

  defp variable_condition(sheet_shortcut, variable_name) do
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
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end
end

defmodule Storyarn.References.AmbientFlowVariableUsageTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.GlobalSearch
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Hero profile", shortcut: "hero.profile"})

    block =
      block_fixture(sheet, %{
        type: "number",
        variable_name: "health",
        config: %{"label" => "Health"}
      })

    scene = scene_fixture(project, %{name: "Moonlit Courtyard"})
    flow = flow_fixture(project, %{name: "Night ambience"})

    {:ok, ambient_flow} =
      Scenes.create_ambient_flow(scene.id, %{
        "flow_id" => flow.id,
        "trigger_type" => "on_event",
        "trigger_config" => %{"variable_ref" => "hero.profile.health"}
      })

    [definition] =
      project.id
      |> Sheets.search_variable_definitions({:qualified, "hero.profile.health"})
      |> Map.fetch!(:items)

    %{
      user: user,
      scope: user_scope_fixture(user),
      project: project,
      sheet: sheet,
      block: block,
      scene: scene,
      flow: flow,
      ambient_flow: ambient_flow,
      definition: definition
    }
  end

  test "normalized usages include an ambient event owned by its active Scene", context do
    assert %{items: [usage], truncated: false} =
             References.list_variable_usages(
               context.project.id,
               context.definition
             )

    assert usage.source_type == :scene_ambient_flow
    assert usage.source_id == context.ambient_flow.id
    assert usage.source_kind == "ambient_event"
    assert usage.source_label == context.flow.name
    assert usage.container_type == :scene
    assert usage.container_id == context.scene.id
    assert usage.container_name == context.scene.name
    assert usage.kind == "read"
    assert usage.semantic == :read
    refute usage.stale
  end

  test "legacy get and stale reads support dotted Sheet shortcuts and active Scene filtering", context do
    assert [usage] =
             Scenes.get_scene_ambient_flow_variable_usage(
               context.block.id,
               context.project.id
             )

    assert usage.source_type == "scene_ambient_flow"
    assert usage.ambient_flow_id == context.ambient_flow.id
    assert usage.ambient_flow_name == context.flow.name
    assert usage.scene_id == context.scene.id

    assert [fresh] =
             Scenes.check_stale_scene_ambient_flow_variable_references(
               context.block.id,
               context.project.id
             )

    refute fresh.stale

    {:ok, _renamed_sheet} =
      Sheets.update_sheet(context.sheet, %{shortcut: "protagonist.profile"})

    assert [stale] =
             Scenes.check_stale_scene_ambient_flow_variable_references(
               context.block.id,
               context.project.id
             )

    assert stale.stale
    assert stale.source_sheet == "hero.profile"
    assert stale.source_variable == "health"

    {:ok, _deleted_scene} = Scenes.delete_scene(context.scene)

    assert [] =
             Scenes.get_scene_ambient_flow_variable_usage(
               context.block.id,
               context.project.id
             )

    assert [] =
             Scenes.check_stale_scene_ambient_flow_variable_references(
               context.block.id,
               context.project.id
             )
  end

  test "global variable search navigates an ambient usage to its Scene without a fake focus", context do
    assert {:ok, page} =
             GlobalSearch.advanced_project_search(
               context.scope,
               context.project.id,
               "$hero.profile.health"
             )

    assert usage =
             Enum.find(page.items, fn hit ->
               hit.meta[:source_type] == :scene_ambient_flow
             end)

    assert usage.group == :read
    assert usage.kind == :read
    assert usage.label == context.flow.name
    assert usage.context == context.scene.name

    assert usage.action == %{
             kind: :navigate,
             destination: %{
               type: :scene,
               id: context.scene.id,
               focus: nil
             }
           }
  end

  test "legacy usage and stale reads exclude a malformed cross-project ambient Flow", context do
    foreign_project = project_fixture(context.user)
    foreign_flow = flow_fixture(foreign_project, %{name: "Foreign ambience"})

    malformed_ambient =
      context.ambient_flow
      |> Ecto.Changeset.change(flow_id: foreign_flow.id)
      |> Repo.update!()

    assert malformed_ambient.scene_id == context.scene.id
    assert malformed_ambient.flow_id == foreign_flow.id

    assert [] =
             Scenes.get_scene_ambient_flow_variable_usage(
               context.block.id,
               context.project.id
             )

    assert [] =
             Scenes.check_stale_scene_ambient_flow_variable_references(
               context.block.id,
               context.project.id
             )
  end
end

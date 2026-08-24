defmodule Storyarn.Scenes.VariableCatalogTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Scenes.VariableCatalog

  test "builds the Scene health vocabulary from consumer-owned database records" do
    project = project_fixture()
    sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

    block =
      block_fixture(sheet, %{
        type: "number",
        variable_name: "health",
        config: %{"label" => "Health", "min" => 0, "max" => 100},
        value: %{"content" => 75}
      })

    scene = scene_fixture(project)

    pin =
      pin_fixture(scene, %{
        "shortcut" => "party.leader",
        "hidden" => true,
        "is_playable" => true,
        "is_leader" => true
      })

    zone = zone_fixture(scene, %{"shortcut" => "front-gate", "hidden" => true})

    variables = VariableCatalog.list_referenceable(project.id)
    sheet_id = sheet.id
    block_id = block.id
    pin_id = pin.id
    zone_id = zone.id

    assert %{
             sheet_id: ^sheet_id,
             block_id: ^block_id,
             sheet_shortcut: "hero",
             variable_name: "health",
             block_type: "number",
             constraints: %{"min" => 0, "max" => 100}
           } = Enum.find(variables, &(&1.block_id == block.id))

    assert %{
             source_type: "pin",
             source_id: ^pin_id,
             sheet_shortcut: "party.leader",
             variable_name: "is_leader",
             block_type: "boolean",
             value: %{"content" => true}
           } =
             Enum.find(
               variables,
               &(Map.get(&1, :source_type) == "pin" and &1.source_id == pin.id and
                   &1.variable_name == "is_leader")
             )

    assert %{
             source_type: "zone",
             source_id: ^zone_id,
             sheet_shortcut: "front-gate",
             variable_name: "hidden",
             block_type: "boolean",
             value: %{"content" => true}
           } =
             Enum.find(
               variables,
               &(Map.get(&1, :source_type) == "zone" and &1.source_id == zone.id)
             )
  end

  test "excludes soft-deleted sheets and scenes from the vocabulary" do
    project = project_fixture()
    sheet = sheet_fixture(project, %{shortcut: "retired"})
    block = block_fixture(sheet, %{type: "number", variable_name: "score"})
    scene = scene_fixture(project)
    pin = pin_fixture(scene, %{"shortcut" => "retired-pin"})

    deleted_at = Storyarn.Platform.Shared.TimeHelpers.now()
    Repo.update!(Ecto.Changeset.change(sheet, deleted_at: deleted_at))
    Repo.update!(Ecto.Changeset.change(scene, deleted_at: deleted_at))

    variables = VariableCatalog.list_referenceable(project.id)

    refute Enum.any?(variables, &(&1.block_id == block.id))
    refute Enum.any?(variables, &(Map.get(&1, :source_type) == "pin" and &1.source_id == pin.id))
  end
end

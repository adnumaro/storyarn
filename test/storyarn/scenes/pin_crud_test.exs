defmodule Storyarn.Scenes.PinCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Scenes.PinCrud
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Sheets.EntityReference

  defp create_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # change_pin/1-2 (lines 117-118, completely uncovered)
  # =============================================================================

  describe "change_pin/1-2" do
    test "returns a changeset for a pin with no attrs" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      changeset = PinCrud.change_pin(pin)
      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns a changeset for a pin with attrs" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      changeset = PinCrud.change_pin(pin, %{"label" => "New Label"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :label) == "New Label"
    end
  end

  # =============================================================================
  # list_pins/1 without explicit opts (line 15, default args dispatch)
  # =============================================================================

  describe "list_pins/1 default args" do
    test "list_pins with single arity calls the default opts" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      _pin = pin_fixture(scene)

      # Calling with 1 arg exercises the default args dispatch (line 15)
      pins = PinCrud.list_pins(scene.id)
      assert length(pins) == 1
    end
  end

  describe "reference integrity" do
    test "reloads a stale pin under the scene lock before replacing its references" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project, %{shortcut: "character.hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      pin = pin_fixture(scene)
      stale_pin = pin
      condition = variable_condition(sheet.shortcut, block.variable_name)

      assert {:ok, _updated_pin} =
               PinCrud.update_pin(pin, %{
                 "flow_id" => flow.id,
                 "condition" => condition
               })

      assert {:ok, updated_pin} =
               PinCrud.update_pin(stale_pin, %{"label" => "Renamed from stale state"})

      assert updated_pin.flow_id == flow.id
      assert updated_pin.condition == condition

      persisted_pin = Repo.get!(ScenePin, pin.id)
      assert persisted_pin.flow_id == flow.id
      assert persisted_pin.condition == condition

      assert [
               %EntityReference{
                 target_type: "flow",
                 target_id: target_id,
                 context: "target"
               }
             ] =
               Repo.all(
                 from(reference in EntityReference,
                   where:
                     reference.source_type == "scene_pin" and
                       reference.source_id == ^pin.id
                 )
               )

      assert target_id == flow.id

      assert [
               %VariableReference{
                 block_id: block_id,
                 kind: "read"
               }
             ] =
               Repo.all(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "scene_pin" and
                       reference.source_id == ^pin.id
                 )
               )

      assert block_id == block.id
    end
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

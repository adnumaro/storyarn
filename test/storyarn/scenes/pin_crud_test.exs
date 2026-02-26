defmodule Storyarn.Scenes.PinCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Scenes.PinCrud

  import Storyarn.AccountsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

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
end

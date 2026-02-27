defmodule Storyarn.ShortcutsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shortcuts

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.FlowsFixtures

  defp create_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "generate_sheet_shortcut/2" do
    test "generates shortcutified name" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_sheet_shortcut("My Sheet", project.id)
      assert shortcut == "my-sheet"
    end

    test "appends numeric suffix on collision" do
      %{project: project} = create_project()

      # Create a sheet that will occupy the base shortcut
      sheet_fixture(project, %{name: "Inventory"})

      # Generating for the same name should produce a suffix
      shortcut = Shortcuts.generate_sheet_shortcut("Inventory", project.id)
      assert shortcut == "inventory-1"
    end

    test "exclude_id allows reusing own shortcut on update" do
      %{project: project} = create_project()

      sheet = sheet_fixture(project, %{name: "Inventory"})

      # With exclude_id, the sheet's own shortcut is not considered a collision
      shortcut = Shortcuts.generate_sheet_shortcut("Inventory", project.id, sheet.id)
      assert shortcut == "inventory"
    end

    test "returns nil for empty name" do
      %{project: project} = create_project()
      assert Shortcuts.generate_sheet_shortcut("", project.id) == nil
    end
  end

  describe "generate_flow_shortcut/2" do
    test "generates shortcutified name" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_flow_shortcut("Main Quest", project.id)
      assert shortcut == "main-quest"
    end

    test "appends numeric suffix on collision" do
      %{project: project} = create_project()

      flow_fixture(project, %{name: "Prologue"})

      shortcut = Shortcuts.generate_flow_shortcut("Prologue", project.id)
      assert shortcut == "prologue-1"
    end
  end

  describe "generate_screenplay_shortcut/2" do
    test "generates shortcutified name" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_screenplay_shortcut("Act One", project.id)
      assert shortcut == "act-one"
    end
  end

  describe "generate_scene_shortcut/2" do
    test "generates shortcutified name" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_scene_shortcut("Forest Clearing", project.id)
      assert shortcut == "forest-clearing"
    end
  end
end

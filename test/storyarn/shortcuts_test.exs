defmodule Storyarn.ShortcutsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shortcuts

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  defp create_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # generate_sheet_shortcut/2 (default args dispatch, line 24)
  # =============================================================================

  describe "generate_sheet_shortcut/2 with default exclude_id" do
    test "generates shortcut without exclude_id" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_sheet_shortcut("My Sheet", project.id)
      assert shortcut == "my-sheet"
    end
  end

  # =============================================================================
  # generate_flow_shortcut/2 (default args dispatch, line 27)
  # =============================================================================

  describe "generate_flow_shortcut/2 with default exclude_id" do
    test "generates shortcut without exclude_id" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_flow_shortcut("My Flow", project.id)
      assert shortcut == "my-flow"
    end
  end

  # =============================================================================
  # generate_screenplay_shortcut/2 (default args dispatch, line 30)
  # =============================================================================

  describe "generate_screenplay_shortcut/2 with default exclude_id" do
    test "generates shortcut without exclude_id" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_screenplay_shortcut("My Screenplay", project.id)
      assert shortcut == "my-screenplay"
    end
  end

  # =============================================================================
  # generate_scene_shortcut/2 (default args dispatch, line 33)
  # =============================================================================

  describe "generate_scene_shortcut/2 with default exclude_id" do
    test "generates shortcut without exclude_id" do
      %{project: project} = create_project()

      shortcut = Shortcuts.generate_scene_shortcut("My Scene", project.id)
      assert shortcut == "my-scene"
    end
  end
end

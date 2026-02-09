defmodule Storyarn.ScreenplaysTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  describe "integration: screenplay + elements lifecycle" do
    setup :setup_project

    test "create screenplay, add elements, list and verify order", %{project: project} do
      # Create screenplay through facade
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "Test Script"})
      assert screenplay.name == "Test Script"
      assert screenplay.shortcut != nil

      # Add elements through facade
      {:ok, e1} =
        Screenplays.create_element(screenplay, %{
          type: "scene_heading",
          content: "INT. OFFICE - DAY"
        })

      {:ok, e2} =
        Screenplays.create_element(screenplay, %{type: "action", content: "John enters."})

      {:ok, e3} = Screenplays.create_element(screenplay, %{type: "character", content: "JOHN"})

      {:ok, e4} =
        Screenplays.create_element(screenplay, %{type: "dialogue", content: "Hello there."})

      # List elements through facade
      elements = Screenplays.list_elements(screenplay.id)
      assert length(elements) == 4
      assert Enum.map(elements, & &1.id) == [e1.id, e2.id, e3.id, e4.id]
      assert Enum.map(elements, & &1.position) == [0, 1, 2, 3]

      # Count through facade
      assert Screenplays.count_elements(screenplay.id) == 4

      # Group elements through facade
      groups = Screenplays.group_elements(elements)
      types = Enum.map(groups, & &1.type)
      assert types == [:scene_heading, :action, :dialogue_group]
    end

    test "create screenplay, delete, verify soft-deleted, restore", %{project: project} do
      {:ok, screenplay} = Screenplays.create_screenplay(project, %{name: "Deletable"})

      # Verify it's listed
      list = Screenplays.list_screenplays(project.id)
      assert Enum.any?(list, &(&1.id == screenplay.id))

      # Soft-delete
      {:ok, _deleted} = Screenplays.delete_screenplay(screenplay)

      # Not in active list
      list = Screenplays.list_screenplays(project.id)
      refute Enum.any?(list, &(&1.id == screenplay.id))

      # In trash
      trash = Screenplays.list_deleted_screenplays(project.id)
      assert Enum.any?(trash, &(&1.id == screenplay.id))

      # Restore
      deleted = hd(Enum.filter(trash, &(&1.id == screenplay.id)))
      {:ok, restored} = Screenplays.restore_screenplay(deleted)
      assert restored.deleted_at == nil

      # Back in active list
      list = Screenplays.list_screenplays(project.id)
      assert Enum.any?(list, &(&1.id == screenplay.id))
    end
  end
end

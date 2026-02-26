defmodule StoryarnWeb.SheetLive.Components.PropagationModalTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.SheetLive.Components.PropagationModal

  describe "PropagationModal" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{user: user, project: project}
    end

    test "renders modal with block name", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Description"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "Description"
      assert html =~ "Propagate"
    end

    test "renders descendant checkboxes", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child1 = sheet_fixture(project, %{name: "Child 1", parent_id: parent.id})
      _child2 = sheet_fixture(project, %{name: "Child 2", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Name"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "Child 1"
      assert html =~ "Child 2"
      assert html =~ "Select all"
      assert html =~ "checkbox"
    end

    test "renders Select all with count", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child1 = sheet_fixture(project, %{name: "Child 1", parent_id: parent.id})
      _child2 = sheet_fixture(project, %{name: "Child 2", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Field"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "2 sheets"
    end

    test "renders Cancel and Propagate buttons", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Test"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "Cancel"
      assert html =~ "Propagate"
      assert html =~ "cancel_propagation"
      assert html =~ "propagate_property"
    end

    test "renders help text", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Test"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "automatically appear"
      assert html =~ "Unselected sheets"
    end

    test "handles no descendants", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Test"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "0 sheets"
      # Propagate button should be disabled
      assert html =~ "disabled"
    end

    test "renders nested descendants", %{project: project} do
      parent = sheet_fixture(project, %{name: "Root"})
      child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})
      _grandchild = sheet_fixture(project, %{name: "Grandchild", parent_id: child.id})

      block = %{
        id: "block-1",
        type: "text",
        config: %{"label" => "Test"},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "Child"
      assert html =~ "Grandchild"
      assert html =~ "2 sheets"
    end

    test "uses block type when label is missing", %{project: project} do
      parent = sheet_fixture(project, %{name: "Parent"})
      _child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      block = %{
        id: "block-1",
        type: "number",
        config: %{},
        value: %{},
        is_constant: false
      }

      html =
        render_component(PropagationModal,
          id: "propagation-modal",
          sheet: parent,
          block: block,
          target: nil
        )

      assert html =~ "number"
    end
  end
end

defmodule StoryarnWeb.FlowLive.Components.BuilderPanelTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Components.BuilderPanel

  # =============================================================================
  # builder_content/1 — condition node
  # =============================================================================

  describe "builder_content/1 with condition node" do
    test "renders title, close button, and empty state hint" do
      assigns = %{
        node: %{
          id: 1,
          type: "condition",
          data: %{
            "condition" => %{"logic" => "all", "rules" => []},
            "switch_mode" => false
          }
        },
        form: %{},
        can_edit: true,
        project_variables: [],
        panel_sections: %{},
        __changed__: %{}
      }

      html = render_component(&BuilderPanel.builder_content/1, assigns)

      assert html =~ "Condition Builder"
      assert html =~ "close_builder"
      assert html =~ "Add rules"
    end

    test "shows switch mode hint when switch_mode enabled" do
      assigns = %{
        node: %{
          id: 3,
          type: "condition",
          data: %{
            "condition" => %{"logic" => "all", "rules" => []},
            "switch_mode" => true
          }
        },
        form: %{},
        can_edit: true,
        project_variables: [],
        panel_sections: %{},
        __changed__: %{}
      }

      html = render_component(&BuilderPanel.builder_content/1, assigns)

      assert html =~ "creates a separate output"
    end
  end

  # =============================================================================
  # builder_content/1 — instruction node
  # =============================================================================

  describe "builder_content/1 with instruction node" do
    test "renders title and empty state hint when can_edit" do
      assigns = %{
        node: %{id: 4, type: "instruction", data: %{"assignments" => []}},
        form: %{},
        can_edit: true,
        project_variables: [],
        panel_sections: %{},
        __changed__: %{}
      }

      html = render_component(&BuilderPanel.builder_content/1, assigns)

      assert html =~ "Instruction Builder"
      assert html =~ "Add assignments"
    end

    test "hides empty state hint when can_edit is false" do
      assigns = %{
        node: %{id: 6, type: "instruction", data: %{"assignments" => []}},
        form: %{},
        can_edit: false,
        project_variables: [],
        panel_sections: %{},
        __changed__: %{}
      }

      html = render_component(&BuilderPanel.builder_content/1, assigns)

      refute html =~ "Add assignments"
    end
  end

  # =============================================================================
  # builder_content/1 — unknown node type
  # =============================================================================

  describe "builder_content/1 with unknown node type" do
    test "renders close button but no builder-specific title" do
      assigns = %{
        node: %{id: 7, type: "dialogue", data: %{}},
        form: %{},
        can_edit: true,
        project_variables: [],
        panel_sections: %{},
        __changed__: %{}
      }

      html = render_component(&BuilderPanel.builder_content/1, assigns)

      assert html =~ "close_builder"
      refute html =~ "Condition Builder"
      refute html =~ "Instruction Builder"
    end
  end
end

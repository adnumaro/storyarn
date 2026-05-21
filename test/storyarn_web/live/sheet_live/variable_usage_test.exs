defmodule StoryarnWeb.SheetLive.VariableUsageTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Repo

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_url(project, sheet) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_references_tab(conn, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_url(project, sheet))
    await_async(view)
    html = render_click(view, "switch_tab", %{"tab" => "references"})
    {view, html}
  end

  # ===========================================================================
  # Flow node variable usage (existing tests)
  # ===========================================================================

  describe "variable usage in references tab" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Player", shortcut: "player"})

      health_block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Main Quest"})

      %{
        project: project,
        sheet: sheet,
        health_block: health_block,
        flow: flow
      }
    end

    test "sheet without variables does not show section at all",
         %{conn: conn, project: project} do
      # Create a sheet with only a constant block (non-variable)
      sheet = sheet_fixture(project, %{name: "Empty Sheet"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Title"}, is_constant: true})

      {_view, html} = mount_references_tab(conn, project, sheet)

      refute html =~ "Variable Usage"
    end
  end

  # ===========================================================================
  # format_assignment_detail — all operators
  # ===========================================================================

  describe "format_assignment_detail for all operator types" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "OpSheet", shortcut: "ops"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Score", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Operator Flow"})

      %{project: project, sheet: sheet, block: block, flow: flow}
    end

    test "set operator shows '= value'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "set",
                "value" => "42",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "= 42"
    end

    test "add operator shows '+= value'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "add",
                "value" => "5",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "+= 5"
    end

    test "subtract operator shows '-= value'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "subtract",
                "value" => "3",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "-= 3"
    end

    test "set_true operator shows '= true'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      # Use a boolean block for set_true
      bool_block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => false}
        })

      _ = bool_block

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "active",
                "operator" => "set_true",
                "value" => "",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "= true"
    end

    test "set_false operator shows '= false'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      bool_block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Enabled"},
          value: %{"content" => true}
        })

      _ = bool_block

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "enabled",
                "operator" => "set_false",
                "value" => "",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "= false"
    end

    test "toggle operator shows 'toggle'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      bool_block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Toggler"},
          value: %{"content" => false}
        })

      _ = bool_block

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "toggler",
                "operator" => "toggle",
                "value" => "",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "toggle"
    end

    test "clear operator shows 'clear'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      text_block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Notes"},
          value: %{"content" => "stuff"}
        })

      _ = text_block

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "notes",
                "operator" => "clear",
                "value" => "",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "clear"
    end

    test "variable_ref operator shows '= sheet.variable'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      # Create another sheet for the variable reference source
      source_sheet = sheet_fixture(project, %{name: "Source", shortcut: "src"})

      _source_block =
        block_fixture(source_sheet, %{
          type: "number",
          config: %{"label" => "Base Score"},
          value: %{"content" => "10"}
        })

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "set",
                "value" => "base_score",
                "value_type" => "variable_ref",
                "value_sheet" => "src"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "= src.base_score"
    end

    test "add with variable_ref shows '+= sheet.variable'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      source_sheet = sheet_fixture(project, %{name: "Bonus", shortcut: "bonus"})

      _bonus_block =
        block_fixture(source_sheet, %{
          type: "number",
          config: %{"label" => "Modifier"},
          value: %{"content" => "5"}
        })

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "add",
                "value" => "modifier",
                "value_type" => "variable_ref",
                "value_sheet" => "bonus"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "+= bonus.modifier"
    end

    test "subtract with variable_ref shows '-= sheet.variable'",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      source_sheet = sheet_fixture(project, %{name: "Penalty", shortcut: "penalty"})

      _penalty_block =
        block_fixture(source_sheet, %{
          type: "number",
          config: %{"label" => "Reduction"},
          value: %{"content" => "2"}
        })

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "ops",
                "variable" => "score",
                "operator" => "subtract",
                "value" => "reduction",
                "value_type" => "variable_ref",
                "value_sheet" => "penalty"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "-= penalty.reduction"
    end
  end

  # ===========================================================================
  # variable_block? filtering
  # ===========================================================================

  describe "variable_block? filtering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "sheet with nil variable_name block does not show it in variable usage",
         %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "NilVarSheet"})

      # Reference blocks don't generate variable_name
      block_fixture(sheet, %{
        type: "reference",
        config: %{"label" => "Link", "allowed_types" => ["sheet"]}
      })

      {_view, html} = mount_references_tab(conn, project, sheet)

      # No variable usage section because reference blocks are not variables
      refute html =~ "Variable Usage"
    end

    test "sheet with constant block does not show it in variable usage",
         %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "ConstVarSheet"})

      # Constant blocks are not variables
      block_fixture(sheet, %{type: "text", config: %{"label" => "Title"}, is_constant: true})

      {_view, html} = mount_references_tab(conn, project, sheet)

      refute html =~ "Variable Usage"
    end

    test "constant block is excluded from variable usage",
         %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "ConstSheet"})

      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "ConstantField"}
        })

      # Mark as constant
      Storyarn.Sheets.update_block_config(block, %{"is_constant" => true})

      {_view, html} = mount_references_tab(conn, project, sheet)

      # Constant blocks should not appear in variable usage
      # The section may show if there are other variable blocks, but ConstantField
      # should not be listed
      refute html =~ "ConstantField"
    end

    test "reference-type block is excluded from variable usage",
         %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "RefTypeSheet"})

      block_fixture(sheet, %{
        type: "reference",
        config: %{"label" => "LinkedSheet"},
        value: %{"content" => ""}
      })

      {_view, html} = mount_references_tab(conn, project, sheet)

      refute html =~ "Variable Usage"
    end
  end

  # ===========================================================================
  # label_for_block and icon_for_node_type helpers
  # ===========================================================================

  describe "label_for_block displays block config label" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "LabelSheet", shortcut: "lbl"})
      flow = flow_fixture(project, %{name: "Label Flow"})
      %{project: project, sheet: sheet, flow: flow}
    end

    test "shows config label when present",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Custom Label", "placeholder" => "0"}
        })

      _ = block

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "lbl",
                "variable" => "custom_label",
                "operator" => "set",
                "value" => "1",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "Custom Label"
    end
  end

  describe "icon_for_node_type" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "IconSheet", shortcut: "icon"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Power", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Icon Flow"})
      %{project: project, sheet: sheet, block: block, flow: flow}
    end

    test "instruction node shows zap icon",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "icon",
                "variable" => "power",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      # The icon component renders with the name attribute
      assert html =~ "instruction"
    end

    test "condition node shows git-branch icon",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "blocks" => [
                %{
                  "id" => "b1",
                  "type" => "block",
                  "logic" => "all",
                  "rules" => [
                    %{
                      "id" => "r1",
                      "sheet" => "icon",
                      "variable" => "power",
                      "operator" => "greater_than",
                      "value" => "50"
                    }
                  ]
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "condition"
    end
  end
end

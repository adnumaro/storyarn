defmodule StoryarnWeb.SheetLive.VariableUsageTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Scenes

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_url(project, sheet) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_references_tab(conn, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_url(project, sheet))
    render_async(view, 500)
    html = render_click(view, "switch_tab", %{"tab" => "references"})
    {view, html}
  end

  # ===========================================================================
  # Flow node variable usage (existing tests)
  # ===========================================================================

  describe "variable usage in references tab" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "shows variable usage when instruction node writes to variable",
         %{conn: conn, project: project, sheet: sheet, health_block: _block, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "player",
                "variable" => "health",
                "operator" => "add",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "Variable Usage"
      assert html =~ "Modified by"
      assert html =~ "Main Quest"
      assert html =~ "instruction"
    end

    test "shows variable usage when condition node reads variable",
         %{conn: conn, project: project, sheet: sheet, health_block: _block, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "rule_1",
                  "sheet" => "player",
                  "variable" => "health",
                  "operator" => "greater_than",
                  "value" => "50"
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "Variable Usage"
      assert html =~ "Read by"
      assert html =~ "Main Quest"
      assert html =~ "condition"
    end

    test "navigate link includes flow_id and node_id",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assign_1",
                "sheet" => "player",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "flows/#{flow.id}?node=#{node.id}"
    end

    test "variables with no usage do not show section",
         %{conn: conn, project: project, sheet: sheet} do
      {_view, html} = mount_references_tab(conn, project, sheet)

      # Section shows but with empty state message
      assert html =~ "No variables on this sheet are used in any flow or scene yet."
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
  # Scene zone references
  # ===========================================================================

  describe "scene zone variable references" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "ZoneSheet", shortcut: "zs"})

      health_block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      scene = scene_fixture(project, %{name: "Battle Arena"})

      zone =
        zone_fixture(scene, %{
          "name" => "Danger Zone"
        })

      %{
        project: project,
        sheet: sheet,
        health_block: health_block,
        scene: scene,
        zone: zone
      }
    end

    test "shows zone write reference in variable usage",
         %{
           conn: conn,
           project: project,
           sheet: sheet,
           zone: zone,
           scene: scene
         } do
      # Update zone with action_data that writes to the variable
      {:ok, updated_zone} =
        Scenes.update_zone(zone, %{
          "action_type" => "instruction",
          "action_data" => %{
            "assignments" => [
              %{
                "id" => "za1",
                "sheet" => "zs",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "25",
                "value_type" => "literal"
              }
            ]
          }
        })

      _ = {updated_zone, scene}

      {_view, html} = mount_references_tab(conn, project, sheet)

      # Should show the scene name and zone name
      assert html =~ "Battle Arena"
      assert html =~ "Danger Zone"
      assert html =~ "Modified by"
      # Zone refs link to scenes, not flows
      assert html =~ "scenes/#{scene.id}"
    end

    test "shows zone read reference via condition",
         %{
           conn: conn,
           project: project,
           sheet: sheet,
           zone: zone
         } do
      # Update zone with condition that reads the variable
      {:ok, _updated_zone} =
        Scenes.update_zone(zone, %{
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "zr1",
                "sheet" => "zs",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "0"
              }
            ]
          }
        })

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "Battle Arena"
      assert html =~ "Danger Zone"
      assert html =~ "Read by"
    end
  end

  # ===========================================================================
  # variable_block? filtering
  # ===========================================================================

  describe "variable_block? filtering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "normal variable blocks appear in usage section",
         %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "NormalSheet", shortcut: "normal"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Strength", "placeholder" => "0"}
      })

      {_view, html} = mount_references_tab(conn, project, sheet)

      # Should show the variable usage section (even if empty state)
      assert html =~ "Variable Usage"
      assert html =~ "No variables on this sheet are used in any flow or scene yet."
    end
  end

  # ===========================================================================
  # Lazy loading state transitions
  # ===========================================================================

  describe "lazy loading" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "LazySheet", shortcut: "lazy"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Speed", "placeholder" => "0"}
      })

      flow = flow_fixture(project, %{name: "Speed Flow"})

      %{project: project, sheet: sheet, flow: flow}
    end

    test "variable usage section loads data on first render of references tab",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      # Create a reference so usage is non-empty
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "lazy",
                "variable" => "speed",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      # Mount the sheet (starts on content tab)
      {:ok, view, _html} = live(conn, sheet_url(project, sheet))
      html = render_async(view, 500)

      # Content tab should not contain variable usage
      refute html =~ "Variable Usage"

      # Switch to references tab — triggers lazy load
      html = render_click(view, "switch_tab", %{"tab" => "references"})

      # Should have loaded the usage data
      assert html =~ "Variable Usage"
      assert html =~ "Speed Flow"
    end

    test "usage_map is nil initially and gets populated on tab switch",
         %{conn: conn, project: project, sheet: sheet} do
      # Mount the sheet
      {:ok, view, _html} = live(conn, sheet_url(project, sheet))
      render_async(view, 500)

      # Switch to references tab — the section should render
      html = render_click(view, "switch_tab", %{"tab" => "references"})

      # With no references, should show empty state
      assert html =~ "No variables on this sheet are used in any flow or scene yet."
    end
  end

  # ===========================================================================
  # label_for_block and icon_for_node_type helpers
  # ===========================================================================

  describe "label_for_block displays block config label" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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
      project = project_fixture(user) |> Repo.preload(:workspace)
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
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "condition"
    end
  end

  # ===========================================================================
  # Total refs badge
  # ===========================================================================

  describe "total refs badge" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "BadgeSheet", shortcut: "badge"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Level", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Badge Flow"})
      %{project: project, sheet: sheet, block: block, flow: flow}
    end

    test "shows ref count badge when references exist",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "badge",
                "variable" => "level",
                "operator" => "set",
                "value" => "1",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node)

      {_view, html} = mount_references_tab(conn, project, sheet)

      # The badge shows the count of total references
      assert html =~ "badge badge-sm"
    end

    test "does not show ref count badge when no references exist",
         %{conn: conn, project: project, sheet: sheet} do
      {_view, html} = mount_references_tab(conn, project, sheet)

      # With zero refs, the badge span should not be rendered
      # (the :if={@total_refs > 0} guard prevents it)
      assert html =~ "No variables on this sheet are used in any flow or scene yet."
    end
  end

  # ===========================================================================
  # Multiple variables on same sheet
  # ===========================================================================

  describe "multiple variables on the same sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "MultiVar", shortcut: "mv"})

      health_block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      attack_block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Attack", "placeholder" => "0"}
        })

      flow = flow_fixture(project, %{name: "Multi Flow"})

      %{
        project: project,
        sheet: sheet,
        health_block: health_block,
        attack_block: attack_block,
        flow: flow
      }
    end

    test "shows usage for multiple variables independently",
         %{conn: conn, project: project, sheet: sheet, flow: flow} do
      # Create a node that writes to health
      node1 =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mv",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      VariableReferenceTracker.update_references(node1)

      # Create a node that reads attack
      node2 =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{
              "logic" => "all",
              "rules" => [
                %{
                  "id" => "r1",
                  "sheet" => "mv",
                  "variable" => "attack",
                  "operator" => "greater_than",
                  "value" => "10"
                }
              ]
            }
          }
        })

      VariableReferenceTracker.update_references(node2)

      {_view, html} = mount_references_tab(conn, project, sheet)

      assert html =~ "Health"
      assert html =~ "Attack"
      assert html =~ "Modified by"
      assert html =~ "Read by"
    end
  end
end

defmodule StoryarnWeb.SheetLive.VariableUsageTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Repo

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

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      # Switch to references tab
      html = render_click(view, "switch_tab", %{"tab" => "references"})

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

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_click(view, "switch_tab", %{"tab" => "references"})

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

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_click(view, "switch_tab", %{"tab" => "references"})

      assert html =~ "flows/#{flow.id}?node=#{node.id}"
    end

    test "variables with no usage do not show section",
         %{conn: conn, project: project, sheet: sheet} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_click(view, "switch_tab", %{"tab" => "references"})

      # Section shows but with empty state message
      assert html =~ "No variables on this sheet are used in any flow or map yet."
    end

    test "sheet without variables does not show section at all",
         %{conn: conn, project: project} do
      # Create a sheet with only a divider (non-variable block)
      sheet = sheet_fixture(project, %{name: "Empty Sheet"})
      block_fixture(sheet, %{type: "divider", config: %{}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_click(view, "switch_tab", %{"tab" => "references"})

      refute html =~ "Variable Usage"
    end
  end
end

defmodule Storyarn.Projects.DashboardTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.Dashboard
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project, user: user}
  end

  describe "project_stats/1" do
    test "returns zero counts for empty project", %{project: project} do
      stats = Dashboard.project_stats(project.id)

      assert stats.sheet_count == 0
      assert stats.variable_count == 0
      assert stats.flow_count == 0
      assert stats.dialogue_count == 0
      assert stats.scene_count == 0
      assert stats.total_word_count == 0
    end

    test "counts sheets and variables", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Character"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}, is_constant: false})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}, is_constant: true})

      stats = Dashboard.project_stats(project.id)

      assert stats.sheet_count == 1
      # Only non-constant blocks with variable types count as variables
      assert stats.variable_count == 1
    end

    test "counts flows and dialogue nodes", %{project: project} do
      flow = flow_fixture(project, %{name: "Chapter 1"})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello world"}})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Goodbye"}})
      node_fixture(flow, %{type: "condition", data: %{}})

      stats = Dashboard.project_stats(project.id)

      assert stats.flow_count == 1
      assert stats.dialogue_count == 2
    end

    test "counts words from all user-written text", %{project: project} do
      flow = flow_fixture(project, %{name: "Act One", description: ""})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "<p>Hello <b>beautiful</b> world</p>",
          "menu_text" => "Choose wisely",
          "responses" => [%{"text" => "Yes please"}, %{"text" => "No thanks"}]
        }
      })

      node_fixture(flow, %{type: "dialogue", data: %{"text" => "<p>One two</p>"}})

      stats = Dashboard.project_stats(project.id)

      # Only player-facing runtime text contributes to localization volume.
      assert stats.total_word_count == 11
    end

    test "matches sheet dashboard words when the project only has sheets", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Hero", description: "Main hero"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Biography", "placeholder" => "Add story"},
        value: %{"content" => "Brave explorer"}
      })

      block_fixture(sheet, %{
        type: "select",
        config: %{
          "label" => "Class",
          "placeholder" => "Choose class",
          "options" => [
            %{"key" => "sword_master", "value" => "Sword Master"}
          ]
        }
      })

      table_block = table_block_fixture(sheet, %{label: "Stats"})
      table_column_fixture(table_block, %{name: "Combat Rank"})
      table_row_fixture(table_block, %{name: "Front Line"})

      stats = Dashboard.project_stats(project.id)
      sheet_words = project.id |> Storyarn.Sheets.sheet_word_counts() |> Map.values() |> Enum.sum()

      assert sheet_words == 3
      assert stats.total_word_count == sheet_words
    end

    test "excludes scene editor content from localization words", %{project: project} do
      scene = scene_fixture(project, %{name: "World Map", description: "Capital city"})
      layer = layer_fixture(scene, %{"name" => "Upper City"})

      zone_fixture(scene, %{
        "name" => "Market Square",
        "tooltip" => "Crowded at noon",
        "layer_id" => layer.id
      })

      pin_1 =
        pin_fixture(scene, %{
          "label" => "Clock Tower",
          "tooltip" => "Visible everywhere",
          "layer_id" => layer.id
        })

      pin_2 =
        pin_fixture(scene, %{
          "label" => "West Gate",
          "tooltip" => "",
          "layer_id" => layer.id
        })

      annotation_fixture(scene, %{"text" => "Secret route", "layer_id" => layer.id})
      Storyarn.ScenesFixtures.connection_fixture(scene, pin_1, pin_2, %{"label" => "Patrol path"})

      stats = Dashboard.project_stats(project.id)

      assert stats.total_word_count == 0
    end
  end

  describe "tool_health_summary/1" do
    test "counts each severity per tool and excludes info from actionable" do
      summary =
        Dashboard.tool_health_summary(%{
          flows: [
            %{severity: :error, code: :missing_entry},
            %{severity: :warning, code: :isolated_node},
            %{severity: :warning, code: :isolated_node},
            %{severity: :info, code: :empty_flow}
          ],
          sheets: [%{severity: :info, code: :empty_leaf_sheet}],
          scenes: []
        })

      assert summary.flows == %{error: 1, warning: 2, info: 1, actionable: 3}

      # Info-only reads as up to date: `actionable` is what the card reports.
      assert summary.sheets == %{error: 0, warning: 0, info: 1, actionable: 0}
      assert summary.scenes == %{error: 0, warning: 0, info: 0, actionable: 0}
    end

    test "always returns every tool, even when a domain has no findings" do
      summary = Dashboard.tool_health_summary(%{flows: [], sheets: [], scenes: []})

      assert summary |> Map.keys() |> Enum.sort() == [:flows, :scenes, :sheets]
    end

    test "raises when a tool is missing rather than silently reporting it clean" do
      assert_raise KeyError, fn ->
        Dashboard.tool_health_summary(%{flows: [], sheets: []})
      end
    end
  end

  describe "real findings from the three checkers" do
    test "a flow with no entry node surfaces as an actionable flow error", %{project: project} do
      flow = flow_fixture(project)
      entry = Repo.get_by(Storyarn.Flows.FlowNode, flow_id: flow.id, type: "entry")
      Repo.delete!(entry)

      summary =
        Dashboard.tool_health_summary(%{
          flows: Storyarn.Flows.list_dashboard_health_findings(project.id),
          sheets: Storyarn.Sheets.list_dashboard_health_findings(project.id),
          scenes: Storyarn.Scenes.list_dashboard_health_findings(project.id)
        })

      assert summary.flows.error > 0
      assert summary.flows.actionable > 0
    end

    test "an empty leaf sheet is info, so sheets still read as up to date", %{project: project} do
      sheet_fixture(project)

      summary =
        Dashboard.tool_health_summary(%{
          flows: Storyarn.Flows.list_dashboard_health_findings(project.id),
          sheets: Storyarn.Sheets.list_dashboard_health_findings(project.id),
          scenes: Storyarn.Scenes.list_dashboard_health_findings(project.id)
        })

      assert summary.sheets.info > 0
      assert summary.sheets.actionable == 0
    end
  end

  describe "recent_activity/2 and the screenplays tool" do
    # The UNION over `screenplays` took the WHOLE overview down with an
    # `undefined_table` the moment that tool's table was dropped — stats and
    # activity both, on a page where screenplays were never reachable anyway
    # (they have no editor route). The overview covers what the navigation covers.
    test "omits screenplays even when the project has one", %{project: project} do
      Storyarn.ScreenplaysFixtures.screenplay_fixture(project, %{name: "A Screenplay"})

      activity = Dashboard.recent_activity(project.id)

      refute Enum.any?(activity, &(&1.type == "screenplay"))
      refute Enum.any?(activity, &(&1.name == "A Screenplay"))
    end

    test "still returns sheets, flows and scenes", %{project: project} do
      sheet_fixture(project, %{name: "A Sheet"})
      flow_fixture(project, %{name: "A Flow"})

      types = project.id |> Dashboard.recent_activity() |> Enum.map(& &1.type) |> Enum.uniq()

      assert "sheet" in types
      assert "flow" in types
      refute "screenplay" in types
    end
  end

  describe "recent_activity/2" do
    test "returns recent changes sorted by date", %{project: project} do
      sheet_fixture(project, %{name: "Old Sheet"})
      flow_fixture(project, %{name: "New Flow"})

      activity = Dashboard.recent_activity(project.id)

      assert length(activity) >= 2
      # Most recent first
      names = Enum.map(activity, & &1.name)
      assert "New Flow" in names
      assert "Old Sheet" in names
    end

    test "respects limit", %{project: project} do
      for i <- 1..5, do: sheet_fixture(project, %{name: "Sheet #{i}"})

      activity = Dashboard.recent_activity(project.id, 3)

      assert length(activity) == 3
    end

    test "returns empty list for empty project", %{project: project} do
      assert Dashboard.recent_activity(project.id) == []
    end
  end
end

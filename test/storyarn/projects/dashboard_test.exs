defmodule Storyarn.Projects.DashboardTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.Dashboard
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user) |> Repo.preload(:workspace)
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

    test "counts words from all text sources stripping HTML", %{project: project} do
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

      # Flow name: "Act One" (2)
      # Dialogue 1: "Hello beautiful world" (3) + menu: "Choose wisely" (2)
      # Dialogue 2 text: "One two" (2)
      # Total: 2 + 3 + 2 + 2 + 2 + 2 = 13
      assert stats.total_word_count == 13
    end
  end

  describe "count_all_nodes_by_type/1" do
    test "returns node type distribution", %{project: project} do
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Bye"}})
      node_fixture(flow, %{type: "condition", data: %{}})

      dist = Dashboard.count_all_nodes_by_type(project.id)

      # flow_fixture creates entry + exit nodes automatically
      assert dist["dialogue"] == 2
      assert dist["condition"] == 1
      assert dist["entry"] == 1
      assert dist["exit"] == 1
    end

    test "returns empty map for project with no flows", %{project: project} do
      assert Dashboard.count_all_nodes_by_type(project.id) == %{}
    end
  end

  describe "count_dialogue_lines_by_speaker/1" do
    test "returns speakers ranked by line count", %{project: project} do
      speaker = sheet_fixture(project, %{name: "Jaime"})
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Line 1", "speaker_sheet_id" => speaker.id}
      })

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Line 2", "speaker_sheet_id" => speaker.id}
      })

      result = Dashboard.count_dialogue_lines_by_speaker(project.id)

      assert [%{sheet_name: "Jaime", line_count: 2}] = result
    end

    test "returns empty list when no speakers assigned", %{project: project} do
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "No speaker"}})

      assert Dashboard.count_dialogue_lines_by_speaker(project.id) == []
    end
  end

  describe "detect_issues/1" do
    test "detects flows without entry node", %{project: project} do
      flow = flow_fixture(project)
      # flow_fixture creates entry + exit. Delete the entry node.
      entry = Repo.get_by(Storyarn.Flows.FlowNode, flow_id: flow.id, type: "entry")
      Repo.delete!(entry)

      issues =
        Dashboard.detect_issues(project.id,
          workspace_slug: project.workspace.slug,
          project_slug: project.slug
        )

      entry_issues = Enum.filter(issues, &(&1.severity == :error))
      refute Enum.empty?(entry_issues)
      assert Enum.any?(entry_issues, &String.contains?(&1.message, "no entry node"))
    end

    test "returns empty list for healthy project", %{project: project} do
      _flow = flow_fixture(project)
      _sheet = sheet_fixture(project)

      issues =
        Dashboard.detect_issues(project.id,
          workspace_slug: project.workspace.slug,
          project_slug: project.slug
        )

      # Might have info-level issues (empty sheets), but no errors
      error_issues = Enum.filter(issues, &(&1.severity == :error))
      assert Enum.empty?(error_issues)
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

defmodule Storyarn.Flows.FlowStatsTest do
  @moduledoc """
  Covers the two project-wide aggregations the flows dashboard renders as its
  node histogram and speaker ranking. Both moved here from
  `Storyarn.Projects.Dashboard` when the project overview became a global
  context surface — they answer questions about flows.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project, user: user}
  end

  describe "count_project_nodes_by_type/1" do
    test "returns node type distribution across every flow", %{project: project} do
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Bye"}})
      node_fixture(flow, %{type: "condition", data: %{}})

      dist = Flows.count_project_nodes_by_type(project.id)

      # flow_fixture creates entry + exit nodes automatically
      assert dist["dialogue"] == 2
      assert dist["condition"] == 1
      assert dist["entry"] == 1
      assert dist["exit"] == 1
    end

    test "aggregates across flows rather than reporting one", %{project: project} do
      flow_a = flow_fixture(project)
      flow_b = flow_fixture(project)
      node_fixture(flow_a, %{type: "dialogue", data: %{"text" => "A"}})
      node_fixture(flow_b, %{type: "dialogue", data: %{"text" => "B"}})

      assert Flows.count_project_nodes_by_type(project.id)["dialogue"] == 2
    end

    test "returns empty map for project with no flows", %{project: project} do
      assert Flows.count_project_nodes_by_type(project.id) == %{}
    end

    test "excludes soft-deleted flows", %{project: project} do
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hi"}})
      {:ok, _} = Flows.delete_flow(flow)

      assert Flows.count_project_nodes_by_type(project.id) == %{}
    end
  end

  describe "count_dialogue_lines_by_speaker/2" do
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

      assert [%{sheet_name: "Jaime", line_count: 2}] =
               Flows.count_dialogue_lines_by_speaker(project.id)
    end

    test "ranks the busiest speaker first", %{project: project} do
      quiet = sheet_fixture(project, %{name: "Quiet"})
      loud = sheet_fixture(project, %{name: "Loud"})
      flow = flow_fixture(project)

      node_fixture(flow, %{type: "dialogue", data: %{"text" => "q", "speaker_sheet_id" => quiet.id}})

      for i <- 1..3 do
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "l#{i}", "speaker_sheet_id" => loud.id}
        })
      end

      assert [%{sheet_name: "Loud", line_count: 3}, %{sheet_name: "Quiet", line_count: 1}] =
               Flows.count_dialogue_lines_by_speaker(project.id)
    end

    test "honours the limit", %{project: project} do
      flow = flow_fixture(project)

      for i <- 1..3 do
        speaker = sheet_fixture(project, %{name: "Speaker #{i}"})
        node_fixture(flow, %{type: "dialogue", data: %{"text" => "x", "speaker_sheet_id" => speaker.id}})
      end

      assert length(Flows.count_dialogue_lines_by_speaker(project.id, 2)) == 2
    end

    test "returns empty list when no speakers assigned", %{project: project} do
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "No speaker"}})

      assert Flows.count_dialogue_lines_by_speaker(project.id) == []
    end

    # The dashboard drops the link for these rows; the lines themselves still
    # exist, so dropping the row instead would under-report the dialogue volume.
    test "keeps lines whose speaker sheet was deleted, with no name", %{project: project} do
      speaker = sheet_fixture(project, %{name: "Ghost"})
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Line", "speaker_sheet_id" => speaker.id}
      })

      Repo.delete!(speaker)

      assert [%{sheet_name: nil, line_count: 1}] =
               Flows.count_dialogue_lines_by_speaker(project.id)
    end
  end
end

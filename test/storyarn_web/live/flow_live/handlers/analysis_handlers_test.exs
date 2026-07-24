defmodule StoryarnWeb.FlowLive.Handlers.AnalysisHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  defp load_flow(view), do: render_async(view, 2000)

  defp analysis_props(view) do
    vue = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
    vue.props["panels"]["analysis"]
  end

  defp flow_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  defp mount_editor(conn, project, flow) do
    {:ok, view, _html} = live(conn, flow_url(project, flow))
    load_flow(view)
    view
  end

  # entry → dialogue with no outgoing connection: one deterministic
  # no_outgoing_connection finding.
  defp seed_dead_end(flow) do
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue"})
    connection_fixture(flow, entry, stuck)
    stuck
  end

  describe "panel lifecycle" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Analyzed Flow"})
      %{project: project, flow: flow}
    end

    test "panel starts closed and empty", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)

      props = analysis_props(view)
      assert props["open"] == false
      assert props["active"] == []
      assert props["stale"] == false
    end

    test "opening computes a snapshot with canonical findings", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      stuck = seed_dead_end(flow)
      view = mount_editor(conn, project, flow)

      render_click(view, "open_analysis_panel", %{})
      props = analysis_props(view)

      assert props["open"] == true
      assert props["stale"] == false
      assert props["computedAt"]
      assert props["reasonCodes"] == Flows.finding_dismissal_reason_codes()

      rule_ids = Enum.map(props["active"], & &1["ruleId"])
      assert "no_outgoing_connection" in rule_ids

      finding = Enum.find(props["active"], &(&1["ruleId"] == "no_outgoing_connection"))
      assert finding["targetId"] == stuck.id
      assert finding["category"] == "structure"
      assert finding["severity"] == "warning"
      assert [%{"id" => evidence_id, "type" => "flow_node"}] = finding["evidence"]
      assert evidence_id == stuck.id
    end

    test "a relevant mutation marks the open snapshot stale and rerun refreshes", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      seed_dead_end(flow)
      view = mount_editor(conn, project, flow)

      render_click(view, "open_analysis_panel", %{})
      assert analysis_props(view)["stale"] == false

      # A structural mutation through the editor reloads flow data and must
      # mark the snapshot stale without recomputing it.
      render_hook(view, "add_node", %{
        "type" => "dialogue",
        "position_x" => 500.0,
        "position_y" => 500.0
      })

      assert analysis_props(view)["stale"] == true

      render_click(view, "rerun_analysis", %{})
      assert analysis_props(view)["stale"] == false
    end

    test "close keeps the snapshot but closes the panel", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)

      render_click(view, "open_analysis_panel", %{})
      render_click(view, "close_analysis_panel", %{})

      assert analysis_props(view)["open"] == false
    end
  end

  describe "evidence navigation" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Evidence Flow"})
      %{project: project, flow: flow}
    end

    test "node evidence pushes navigate_to_node for a live node", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      stuck = seed_dead_end(flow)
      view = mount_editor(conn, project, flow)

      render_click(view, "analysis_navigate_evidence", %{"type" => "flow_node", "id" => stuck.id})

      assert_push_event(view, "navigate_to_node", %{node_db_id: node_id})
      assert node_id == stuck.id
    end

    test "connection evidence pushes navigate_to_connection with endpoints", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      stuck = node_fixture(flow, %{type: "dialogue"})
      connection = connection_fixture(flow, entry, stuck)

      view = mount_editor(conn, project, flow)

      render_click(view, "analysis_navigate_evidence", %{
        "type" => "flow_connection",
        "id" => connection.id
      })

      assert_push_event(view, "navigate_to_connection", payload)
      assert payload.source_node_id == entry.id
      assert payload.target_node_id == stuck.id
      assert payload.source_pin == "output"
    end

    test "evidence outside the current flow is rejected as stale", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      other_flow = flow_fixture(project)
      foreign_node = node_fixture(other_flow, %{type: "dialogue"})

      view = mount_editor(conn, project, flow)

      html =
        render_click(view, "analysis_navigate_evidence", %{
          "type" => "flow_node",
          "id" => foreign_node.id
        })

      assert html =~ "no longer available"
      refute_push_event(view, "navigate_to_node", %{})
    end
  end

  describe "surface limitation" do
    setup :register_and_log_in_user

    test "the compact editor renders neither the analysis panel nor its palette surface", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Compact Flow"})
      seed_dead_end(flow)

      {:ok, view, _html} = live(conn, flow_url(project, flow) <> "?layout=compact")
      load_flow(view)

      # V1 supports the normal flow editor only: compact mode mounts just the
      # canvas — no FlowPanels (analysis panel) and no FlowHeader (which
      # registers the flows palette surface with the analyze command).
      assert_raise RuntimeError, fn ->
        LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      end

      assert_raise RuntimeError, fn ->
        LiveVue.Test.get_vue(view, name: "live/flow/show/FlowHeader")
      end
    end
  end

  describe "dismiss and restore" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Disposition Flow"})
      seed_dead_end(flow)
      %{project: project, flow: flow}
    end

    test "editor dismisses and restores a finding", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)
      render_click(view, "open_analysis_panel", %{})

      [finding | _] = analysis_props(view)["active"]

      render_click(view, "dismiss_finding", %{
        "finding_id" => finding["findingId"],
        "reason_code" => "intentional_design",
        "note" => ""
      })

      props = analysis_props(view)
      refute Enum.any?(props["active"], &(&1["findingId"] == finding["findingId"]))
      assert [dismissed] = props["dismissed"]
      assert dismissed["findingId"] == finding["findingId"]
      assert dismissed["reasonCode"] == "intentional_design"
      assert dismissed["dismissedBy"]

      render_click(view, "restore_finding_dismissal", %{"dismissal_id" => dismissed["dismissalId"]})

      props = analysis_props(view)
      assert Enum.any?(props["active"], &(&1["findingId"] == finding["findingId"]))
      assert props["dismissed"] == []
    end

    test "dismissing from a stale snapshot is rejected", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      render_click(view, "open_analysis_panel", %{})
      [finding | _] = analysis_props(view)["active"]

      render_hook(view, "add_node", %{
        "type" => "dialogue",
        "position_x" => 700.0,
        "position_y" => 700.0
      })

      assert analysis_props(view)["stale"] == true

      html =
        render_click(view, "dismiss_finding", %{
          "finding_id" => finding["findingId"],
          "reason_code" => "intentional_design",
          "note" => ""
        })

      assert html =~ "no longer current"
      assert Flows.list_active_finding_dismissals(Flows.get_flow!(project.id, flow.id)) == []
    end

    test "restore with an out-of-range id fails closed", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)
      render_click(view, "open_analysis_panel", %{})

      html =
        render_click(view, "restore_finding_dismissal", %{
          "dismissal_id" => 99_999_999_999_999_999_999_999_999
        })

      assert html =~ "no longer current"
      assert Process.alive?(view.pid)
    end

    test "navigating evidence before the flow graph loads fails closed", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      stuck = seed_dead_end(flow)
      {:ok, view, _html} = live(conn, flow_url(project, flow))

      # No render_async: the fully-preloaded flow has not arrived yet.
      html =
        render_click(view, "analysis_navigate_evidence", %{"type" => "flow_node", "id" => stuck.id})

      assert html =~ "no longer available"
      assert Process.alive?(view.pid)
    end

    test "unknown finding id shows a stale-selection flash, no disposition", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      render_click(view, "open_analysis_panel", %{})

      html =
        render_click(view, "dismiss_finding", %{
          "finding_id" => "sf1_deadbeef",
          "reason_code" => "intentional_design",
          "note" => ""
        })

      assert html =~ "no longer current"
      assert Flows.list_active_finding_dismissals(Flows.get_flow!(project.id, flow.id)) == []
    end

    test "viewer can open and inspect but cannot dismiss", %{
      conn: _conn,
      project: project,
      flow: flow
    } do
      viewer = user_fixture()
      membership_fixture(project, viewer, "viewer")
      viewer_conn = log_in_user(build_conn(), viewer)

      view = mount_editor(viewer_conn, project, flow)
      render_click(view, "open_analysis_panel", %{})

      props = analysis_props(view)
      assert props["open"] == true
      assert props["canEdit"] == false
      assert props["active"] != []

      [finding | _] = props["active"]

      render_click(view, "dismiss_finding", %{
        "finding_id" => finding["findingId"],
        "reason_code" => "intentional_design",
        "note" => ""
      })

      assert Flows.list_active_finding_dismissals(Flows.get_flow!(project.id, flow.id)) == []
      assert analysis_props(view)["dismissed"] == []
    end
  end
end

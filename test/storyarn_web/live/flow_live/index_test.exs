defmodule StoryarnWeb.FlowLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Index

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/flow/dashboard/FlowDashboard")
  end

  describe "Flow index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Chapter One"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.component == "live/flow/dashboard/FlowDashboard"
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Chapter One" end)
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      flow_fixture(project, %{name: "Shared Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Shared Flow" end)
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders empty table when no flows exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.props["table-data"] == []
      assert vue.props["overview-status"] == "ready"
      assert vue.props["stats"]["flow_count"] == 0
    end

    test "passes stats to Vue when flows exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Main Story"})

      # Add a dialogue node to get word counts
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello world"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      stats = vue.props["stats"]
      assert is_map(stats)
      assert stats["word_count"] == 2
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Main Story" and row["word_count"] == 2 end)
    end

    test "sort_flows event toggles table order", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Alpha Flow"})
      flow_fixture(project, %{name: "Zeta Flow"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

      await_async(view)

      # Default: name asc — Alpha before Zeta
      vue = get_dashboard_vue(view)
      names = Enum.map(vue.props["table-data"], & &1["name"])
      alpha_pos = Enum.find_index(names, &(&1 == "Alpha Flow"))
      zeta_pos = Enum.find_index(names, &(&1 == "Zeta Flow"))
      assert alpha_pos < zeta_pos

      # Toggle sort via event — Zeta before Alpha
      render_click(view, "sort_flows", %{"column" => "name"})

      vue = get_dashboard_vue(view)
      names = Enum.map(vue.props["table-data"], & &1["name"])
      alpha_pos = Enum.find_index(names, &(&1 == "Alpha Flow"))
      zeta_pos = Enum.find_index(names, &(&1 == "Zeta Flow"))
      assert zeta_pos < alpha_pos
    end

    test "refreshes the visible dashboard after a committed flow update", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Before"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

      await_async(view)
      assert "Before" in Enum.map(get_dashboard_vue(view).props["table-data"], & &1["name"])

      assert {:ok, _flow} = Flows.update_flow(flow, %{name: "After"})

      Process.sleep(550)
      render(view)
      await_async(view)

      names = Enum.map(get_dashboard_vue(view).props["table-data"], & &1["name"])
      assert "After" in names
      refute "Before" in names
    end
  end

  describe "health issues" do
    setup :register_and_log_in_user

    test "preserves the authenticated locale inside async issue formatting", %{
      conn: conn,
      user: user
    } do
      user = user |> Ecto.Changeset.change(locale: "es") |> Repo.update!()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Localizado"})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})

      issues = issues_for(conn, project)

      assert Enum.any?(issues, fn issue ->
               issue["entity_type"] == "dialogue" and issue["label"] =~ "Diálogo"
             end)
    end

    test "renders errors before warnings before info", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      # Flows sweep in name order, so without a sort the whole of AAA — including
      # its `:info` — arrives before BBB's `:error`.
      flow_a = flow_fixture(project, %{name: "AAA"})
      node_fixture(flow_a, %{type: "instruction", data: %{"assignments" => []}})

      flow_b = flow_fixture(project, %{name: "BBB"})
      flow_b.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry")) |> soft_delete!()
      node_fixture(flow_b, %{type: "dialogue", data: %{"text" => ""}})

      issues = issues_for(conn, project)
      severities = Enum.map(issues, & &1["severity"])

      # Positive control: the fixture spans the whole catalog, so ordering is
      # actually being asserted.
      assert "error" in severities
      assert "warning" in severities
      assert "info" in severities

      assert severities == Enum.sort_by(severities, &severity_rank/1)
      assert List.first(severities) == "error"
    end

    test "a node-level issue deep-links to its node", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Deep Link"})
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
      # Drops the Entry, so the flow carries a flow-level finding too.
      flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry")) |> soft_delete!()

      issues = issues_for(conn, project)
      base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      node_issue = Enum.find(issues, &(&1["code"] == "missing_dialogue_text"))
      assert node_issue, "expected the dialogue's own finding on the dashboard"
      assert node_issue["href"] == "#{base}?highlight=node:#{dialogue.id}"

      # A flow-level finding has no node to open, so it keeps the bare href.
      flow_issue = Enum.find(issues, &(&1["code"] == "missing_entry"))
      assert flow_issue, "expected the flow-level finding on the dashboard"
      assert flow_issue["href"] == base
    end

    test "paginates, clamps, filters, and identifies findings without another load", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Many Findings"})

      for index <- 1..14 do
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "speaker_sheet_id" => "", "index" => index}
        })
      end

      other_flow = flow_fixture(project, %{name: "Other Flow"})

      node_fixture(other_flow, %{
        type: "dialogue",
        data: %{"text" => "", "speaker_sheet_id" => ""}
      })

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

      await_async(view)

      props = get_dashboard_vue(view).props
      pagination = props["issue-pagination"]
      ids = Enum.map(props["issues"], & &1["id"])

      assert pagination["total"] > 25
      assert pagination["totalPages"] > 1
      assert length(props["issues"]) == 25
      assert length(ids) == length(Enum.uniq(ids))
      assert Enum.all?(ids, &is_binary/1)

      assert %{"count" => 15} =
               Enum.find(
                 props["issue-filter-options"]["codes"],
                 &(&1["value"] == "missing_dialogue_text")
               )

      render_click(view, "page_flow_issues", %{"page" => 999})
      clamped = get_dashboard_vue(view).props["issue-pagination"]
      assert clamped["page"] == clamped["totalPages"]

      render_click(view, "filter_flow_issues", %{
        "filter" => "code",
        "value" => "missing_dialogue_text"
      })

      filtered = get_dashboard_vue(view).props
      assert filtered["issue-pagination"]["page"] == 1
      assert filtered["issue-pagination"]["total"] == 15
      assert Enum.all?(filtered["issues"], &(&1["code"] == "missing_dialogue_text"))

      assert %{"count" => 14} =
               Enum.find(
                 filtered["issue-filter-options"]["resources"],
                 &(&1["value"] == to_string(flow.id))
               )

      assert %{"count" => 1} =
               Enum.find(
                 filtered["issue-filter-options"]["resources"],
                 &(&1["value"] == to_string(other_flow.id))
               )

      render_click(view, "filter_flow_issues", %{
        "filter" => "resource",
        "value" => to_string(flow.id)
      })

      resource_filtered = get_dashboard_vue(view).props
      assert resource_filtered["issue-pagination"]["total"] == 14
      assert Enum.all?(resource_filtered["issues"], &(&1["flow_id"] == flow.id))

      assert %{"count" => 14} =
               Enum.find(
                 resource_filtered["issue-filter-options"]["codes"],
                 &(&1["value"] == "missing_dialogue_text")
               )
    end
  end

  describe "deleting the last flow" do
    setup :register_and_log_in_user

    test "refreshes to the empty state after deleting the last flow", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Only Flow"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

      await_async(view)

      # Positive control: the total is non-zero BEFORE the delete, so the
      # assertion below is actually observing the reset.
      assert get_dashboard_vue(view).props["pagination"]["total"] == 1

      render_click(view, "delete", %{"id" => to_string(flow.id)})
      send(view.pid, :load_dashboard_data)
      render(view)
      await_async(view)

      props = get_dashboard_vue(view).props
      assert props["pagination"]["total"] == 0
      assert props["stats"]["flow_count"] == 0
      assert props["overview-status"] == "ready"
      assert props["table-data"] == []
    end
  end

  describe "dashboard load failure" do
    # `{:exit, _reason}` was swallowed silently, so `dashboard_stats` stayed nil
    # and Vue renders a skeleton while it is nil: a crashed load presented as a
    # dashboard that never finishes loading, with no message and nothing to
    # click. That is why the formula-overflow crash looked like "blank forever".
    test "a crashed load logs the reason and leaves an error, not a skeleton" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          dashboard_stats: nil,
          overview_status: :loading
        }
      }

      {result, log} =
        with_log(fn ->
          {:noreply, result} =
            Index.handle_async(:load_dashboard_overview, {:exit, :boom}, socket)

          result
        end)

      # The reason must reach the error tracker, not vanish.
      assert log =~ "Flow dashboard overview load failed for project 4242"
      assert log =~ ":boom"

      assert result.assigns.dashboard_stats == nil
      assert result.assigns.overview_status == :error
    end

    test "a failed refresh preserves loaded content and marks it stale" do
      stats = %{flow_count: 3}

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          dashboard_stats: stats,
          overview_status: :refreshing
        }
      }

      {:noreply, result} =
        Index.handle_async(:load_dashboard_overview, {:exit, :boom}, socket)

      assert result.assigns.dashboard_stats == stats
      assert result.assigns.overview_status == :stale
    end

    test "retry immediately returns the overview to loading" do
      socket = %Socket{assigns: %{__changed__: %{}, overview_status: :error}}

      {:noreply, result} = Index.handle_event("retry_dashboard_overview", %{}, socket)

      assert result.assigns.overview_status == :loading
      assert_receive :load_dashboard_overview
      refute_receive :load_dashboard_issues
    end
  end

  defp soft_delete!(node) do
    node |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
  end

  defp severity_rank("error"), do: 0
  defp severity_rank("warning"), do: 1
  defp severity_rank(_info), do: 2

  defp issues_for(conn, project) do
    {:ok, view, _html} =
      live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

    await_async(view)

    get_dashboard_vue(view).props["issues"]
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/flows")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end

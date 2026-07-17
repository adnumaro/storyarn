defmodule StoryarnWeb.FlowLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias StoryarnWeb.FlowLive.Show

  describe "flow editor layout" do
    setup :register_and_log_in_user

    test "renders header, surface, and panels on the canonical route",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Canonical Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)

      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      header = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowHeader")

      assert header.props["flow-name"] == "Canonical Flow"
      assert surface.props["surface"]["canvas"]["canvasId"] == "flow-canvas-#{flow.id}"
      assert surface.props["surface"]["dock"]["flowId"] == flow.id
      assert panels.props["panels"]["debug"]["open"] == false
    end

    test "compact route keeps the canvas boundary mounted while data loads",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Compact Flow"})

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"
        )

      layout = LiveVue.Test.get_vue(html, name: "live/layouts/compare/Layout")
      initial_canvas = LiveVue.Test.get_vue(html, name: "live/flow/show/FlowCanvas")

      assert layout.id == "compare-layout"
      assert initial_canvas.id == "flow-editor-compact-#{flow.id}"
      assert initial_canvas.props["loading"] == true
      assert initial_canvas.props["flow-data"] == nil

      render_async(view, 2000)

      loaded_canvas = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowCanvas")

      assert loaded_canvas.props["loading"] == false
      assert loaded_canvas.props["flow-data"] =~ "Compact Flow"
      assert loaded_canvas.props["canvas-id"] == "flow-canvas-#{flow.id}"
    end
  end

  describe "async flow loading" do
    setup :register_and_log_in_user

    test "ignores stale load results after navigating to another flow", %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      current_flow = flow_fixture(project, %{name: "Current Flow"})
      stale_flow = flow_fixture(project, %{name: "Stale Flow"})

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flow: current_flow,
          loading: true,
          selected_node: :keep
        }
      }

      {:noreply, result} =
        Show.handle_async(:load_flow_data, {:ok, %{flow: stale_flow}}, socket)

      assert result.assigns.flow.id == current_flow.id
      assert result.assigns.loading == true
      assert result.assigns.selected_node == :keep
    end
  end

  describe "Hub color events" do
    setup :register_and_log_in_user

    test "updates the selected Hub with a valid picker color", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Colored Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#be185d"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == "#22c55e"
    end

    test "rejects a legacy named picker color from the current contract",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Validated Hub Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#3b82f6"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "blue"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == Flows.hub_color_default_hex()
    end

    test "ignores Hub color events when the selected node is not a Hub",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Non-Hub Color Flow"})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "checkpoint"}})

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => jump.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, jump.id).data == %{"target_hub_id" => "checkpoint"}
    end

    test "does not let a viewer update a Hub color", %{conn: conn, user: user} do
      owner = Storyarn.AccountsFixtures.user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      flow = flow_fixture(project, %{name: "Viewer Hub Color Flow"})

      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "checkpoint", "color" => "#be185d"}
        })

      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
      view = mount_flow(conn, url)

      render_click(view, "node_selected", %{"id" => hub.id})
      render_click(view, "update_hub_color", %{"color" => "#22c55e"})

      assert Flows.get_node!(flow.id, hub.id).data["color"] == "#be185d"
    end
  end

  describe "version history events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "History Flow"})
      url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      %{project: project, flow: flow, url: url}
    end

    test "creates a named version", %{conn: conn, url: url, flow: flow} do
      view = mount_flow(conn, url)

      render_click(view, "create_version", %{
        "title" => "First milestone",
        "description" => "Initial playable flow"
      })

      version = Versioning.get_version("flow", flow.id, 1)
      assert version.title == "First milestone"
      assert version.description == "Initial playable flow"
      refute version.is_auto
    end

    test "requires a title", %{conn: conn, url: url, flow: flow} do
      view = mount_flow(conn, url)

      render_click(view, "create_version", %{"title" => "", "description" => "Ignored"})

      assert Versioning.count_versions("flow", flow.id) == 0
    end

    test "updates version title and description", %{
      conn: conn,
      user: user,
      project: project,
      url: url,
      flow: flow
    } do
      {:ok, version} =
        Versioning.create_version("flow", flow, project.id, user.id, is_auto: true)

      view = mount_flow(conn, url)

      render_click(view, "promote_version", %{
        "version_number" => to_string(version.version_number),
        "title" => "Named checkpoint",
        "description" => "Ready for review"
      })

      updated = Versioning.get_version("flow", flow.id, version.version_number)
      assert updated.title == "Named checkpoint"
      assert updated.description == "Ready for review"
    end

    test "deletes an existing version", %{conn: conn, user: user, project: project, url: url, flow: flow} do
      {:ok, version} =
        Versioning.create_version("flow", flow, project.id, user.id, title: "Disposable")

      view = mount_flow(conn, url)

      render_click(view, "delete_version", %{"version_number" => to_string(version.version_number)})

      refute Versioning.get_version("flow", flow.id, version.version_number)
    end

    test "restores the flow from the selected version", %{
      conn: conn,
      user: user,
      project: project,
      url: url,
      flow: flow
    } do
      {:ok, version} =
        Versioning.create_version("flow", flow, project.id, user.id, title: "Before rename")

      {:ok, _changed_flow} = Flows.update_flow(flow, %{name: "Changed Flow"})
      view = mount_flow(conn, url)

      render_click(view, "confirm_restore", %{
        "version_number" => to_string(version.version_number),
        "skip_pre_snapshot" => true
      })

      restored = Flows.get_flow(project.id, flow.id)
      assert restored.name == "History Flow"
    end
  end

  defp mount_flow(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end
end

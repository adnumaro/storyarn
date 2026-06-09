defmodule StoryarnWeb.E2E.FlowsTest do
  @moduledoc """
  E2E tests for flow-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Flows
  alias Storyarn.Repo

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  # Authenticate by injecting a signed session cookie directly.
  # This avoids the phx-trigger-action race condition from the magic link login flow.
  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  describe "flows list (authenticated)" do
    test "shows empty state when project has no flows", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("h1", text: "Flows")
      |> assert_has("p", text: "No flows yet")
    end

    test "shows flow list when project has flows", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Main Story Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("a", text: "Main Story Flow")
    end

    test "can create a new flow from sidebar", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> click("[data-testid='create-flows']")
      |> assert_has("[data-testid='entity-title']")
    end

    test "shows main badge on main flow", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Primary Flow"})
      Flows.set_main_flow(flow)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("span", text: "Main")
    end
  end

  describe "flow editor (authenticated)" do
    test "displays flow editor with canvas", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Story Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("h1", text: "Story Flow")
      |> assert_has("[id^=\"flow-canvas-\"]")
    end

    test "shows dock with node tools for editor", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("[data-testid='flow-dock']")
    end

    test "changing flow from the sidebar updates the browser path", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      root_flow = flow_fixture(project, %{name: "Root Flow"})
      branch_flow = flow_fixture(project, %{name: "Branch Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{root_flow.id}")
      |> assert_has("h1", text: "Root Flow")
      |> assert_has("button[data-tip='Show panel']")
      |> click("button[data-tip='Show panel']")
      |> assert_has("#main-sidebar[data-open='true']")
      |> assert_has(
        "#flows-tree-container a[href='/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{branch_flow.id}']"
      )
      |> click(
        "#flows-tree-container a[href='/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{branch_flow.id}']"
      )
      |> assert_path("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{branch_flow.id}")
      |> assert_has("h1", text: "Branch Flow")
    end

    test "can create nodes from the dock and connect them", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Connected Story Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("[data-testid='flow-dock']")
      |> click("[data-testid='flow-dock-narrative']")
      |> click("[data-testid='flow-dock-node-dialogue']")
      |> place_node_on_canvas(180, 160)
      |> click("[data-testid='flow-dock-logic']")
      |> click("[data-testid='flow-dock-node-condition']")
      |> place_node_on_canvas(460, 160)

      nodes = wait_for_nodes(flow.id, ["dialogue", "condition"])
      dialogue = Enum.find(nodes, &(&1.type == "dialogue"))
      condition = Enum.find(nodes, &(&1.type == "condition"))

      assert dialogue
      assert condition

      conn
      |> create_connection_on_canvas(dialogue.id, condition.id)
      |> assert_has("[id^=\"flow-canvas-\"]")

      connections = wait_for_connection(flow.id, dialogue.id, condition.id)

      assert Enum.any?(connections, fn connection ->
               connection.source_node_id == dialogue.id and connection.target_node_id == condition.id
             end)
    end
  end

  describe "flow access control" do
    test "viewer can see flows but not add node tools", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Shared Flow"})
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate(viewer)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("h1", text: "Shared Flow")
      |> refute_has("[phx-click=add_node]")
    end

    test "editor can see node tools in dock", %{conn: conn} do
      owner = user_fixture()
      editor = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project)
      membership_fixture(project, editor, "editor")

      conn
      |> authenticate(editor)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("[data-testid='flow-dock']")
    end
  end

  defp wait_for_nodes(flow_id, expected_types, attempts \\ 20)

  defp wait_for_nodes(flow_id, expected_types, 0) do
    nodes = Flows.list_nodes(flow_id)

    missing =
      Enum.reject(expected_types, fn type ->
        Enum.any?(nodes, &(&1.type == type))
      end)

    flunk("Expected flow nodes missing after wait: #{Enum.join(missing, ", ")}")
  end

  defp wait_for_nodes(flow_id, expected_types, attempts) do
    nodes = Flows.list_nodes(flow_id)

    if Enum.all?(expected_types, fn type -> Enum.any?(nodes, &(&1.type == type)) end) do
      nodes
    else
      Process.sleep(50)
      wait_for_nodes(flow_id, expected_types, attempts - 1)
    end
  end

  defp wait_for_connection(flow_id, source_node_id, target_node_id, attempts \\ 20)

  defp wait_for_connection(flow_id, source_node_id, target_node_id, 0) do
    connections = Flows.list_connections(flow_id)

    if !Enum.any?(connections, &connection_between?(&1, source_node_id, target_node_id)) do
      flunk("Expected flow connection missing after wait")
    end

    connections
  end

  defp wait_for_connection(flow_id, source_node_id, target_node_id, attempts) do
    connections = Flows.list_connections(flow_id)

    if Enum.any?(connections, &connection_between?(&1, source_node_id, target_node_id)) do
      connections
    else
      Process.sleep(50)
      wait_for_connection(flow_id, source_node_id, target_node_id, attempts - 1)
    end
  end

  defp connection_between?(connection, source_node_id, target_node_id) do
    connection.source_node_id == source_node_id and connection.target_node_id == target_node_id
  end

  defp place_node_on_canvas(conn, x, y) do
    evaluate(
      conn,
      """
      ({ x, y }) => {
        const canvas = document.querySelector('[id^="flow-canvas-"]');
        if (!canvas) throw new Error('Flow canvas not found');

        const rect = canvas.getBoundingClientRect();
        const event = new PointerEvent('pointerdown', {
          bubbles: true,
          cancelable: true,
          button: 0,
          clientX: rect.left + x,
          clientY: rect.top + y,
        });

        canvas.dispatchEvent(event);
      }
      """,
      is_function: true,
      arg: %{x: x, y: y}
    )
  end

  defp create_connection_on_canvas(conn, source_node_id, target_node_id) do
    evaluate(
      conn,
      """
      ({ sourceNodeId, targetNodeId }) =>
        new Promise((resolve) => {
          const canvas = document.querySelector('[id^="flow-canvas-"]');
          if (!canvas) throw new Error('Flow canvas not found');

          const root = canvas.closest('[data-phx-root-id]');
          if (!root) throw new Error('LiveView root not found');

          const view = window.liveSocket?.getViewByEl(root);
          if (!view) throw new Error('LiveView instance not found');

          view.pushEvent('click', root, null, 'connection_created', {
            source_node_id: sourceNodeId,
            source_pin: 'output',
            target_node_id: targetNodeId,
            target_pin: 'input',
          }, {}, () => resolve(true));

          setTimeout(() => resolve(true), 250);
        })
      """,
      is_function: true,
      arg: %{sourceNodeId: source_node_id, targetNodeId: target_node_id}
    )
  end
end

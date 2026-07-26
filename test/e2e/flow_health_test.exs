defmodule StoryarnWeb.E2E.FlowHealthTest do
  @moduledoc """
  Real-browser coverage for flow health, on the ONE surface that now shows it: the
  header popover, the same shared component sheets and scenes use.

  This replaces `flow_analysis_test.exs`, which drove the structural-analysis
  panel — a second health surface with its own palette command, dismissal form and
  dismissed tab. The consolidation removed it, so what remains to prove in a real
  browser is that a designer sees the finding and can reach the node it names.

  Run with: mix test.e2e test/e2e/flow_health_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Flows
  alias Storyarn.Repo

  @moduletag :e2e

  # entry → dialogue with nothing on its output: one structural finding
  # (`no_outgoing_connection`) and two editorial ones on the same node (no
  # speaker, no text). Both catalogs in one popover is the point.
  defp seed_flow(project) do
    flow = flow_fixture(project, %{name: "Health Flow"})
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue", data: %{"text" => ""}})
    connection_fixture(flow, entry, stuck)
    {flow, stuck}
  end

  defp flow_path(project, flow) do
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  test "the header popover shows both catalogs and navigates to the node", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    {flow, stuck} = seed_flow(project)

    conn
    |> authenticate(user)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    # The badge is the shared component's, hence the `flow-health-*` test ids.
    |> assert_has("[data-testid='flow-health-warning-count']", timeout: 20_000)
    |> click("[data-testid='flow-health-trigger']")
    |> assert_has("[data-testid='flow-health-warnings']")
    # Structural and editorial, side by side, translated from codes by Vue.
    |> assert_has("[data-testid='flow-health-warnings']", text: "Node has no outgoing connection")
    |> assert_has("[data-testid='flow-health-warnings']", text: "Missing dialogue speaker")
    # The item carries the node it names, and clicking it is the way back to it.
    |> assert_has("[data-health-entity-id='#{stuck.id}']")
    |> click("[data-health-entity-id='#{stuck.id}']")
    |> refute_has("[data-testid='flow-health-warnings']")
  end

  test "a viewer sees the same findings", %{conn: conn} do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    {flow, _stuck} = seed_flow(project)

    viewer = user_fixture()
    membership_fixture(project, viewer, "viewer")

    conn
    |> authenticate(viewer)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    |> assert_has("[data-testid='flow-health-warning-count']", timeout: 20_000)
    |> click("[data-testid='flow-health-trigger']")
    # Health is a read: a viewer sees it whole. There is no disposition action to
    # withhold any more, which is why this no longer refutes one.
    |> assert_has("[data-testid='flow-health-warnings']", text: "Node has no outgoing connection")
  end

  test "the dashboard names the same findings as the editor", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    {_flow, stuck} = seed_flow(project)

    conn
    |> authenticate(user)
    |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
    # The row is specific, like sheets': location · finding, never "N warnings".
    |> assert_has("[data-severity='warning']", text: "Node has no outgoing connection", timeout: 20_000)
    |> assert_has("[data-severity='warning']", text: "Health Flow")
    |> unwrap(fn _ ->
      codes =
        project.id
        |> Flows.list_dashboard_health_findings()
        |> Enum.filter(&(&1.entity_id == stuck.id))
        |> Enum.map(& &1.code)

      assert :no_outgoing_connection in codes
      assert :missing_dialogue_speaker in codes
    end)
  end
end

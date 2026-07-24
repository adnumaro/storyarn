defmodule StoryarnWeb.E2E.FlowAnalysisTest do
  @moduledoc """
  Real-browser coverage for the structural-analysis panel: an editor running
  the non-AI palette command, dismissing and restoring a finding, and a
  viewer inspecting without disposition actions.

  Run with: mix test.e2e test/e2e/flow_analysis_test.exs
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Flows
  alias Storyarn.Repo

  @moduletag :e2e

  defp open_palette_expression do
    "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'k', ctrlKey: true, bubbles: true, cancelable: true}))"
  end

  # entry → dialogue without outgoing connection: one deterministic
  # no_outgoing_connection finding.
  defp seed_flow(project) do
    flow = flow_fixture(project, %{name: "Analysis Flow"})
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue"})
    connection_fixture(flow, entry, stuck)
    flow
  end

  defp flow_path(project, flow) do
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  test "editor analyzes via the palette command and dismisses a finding", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = seed_flow(project)

    conn
    |> authenticate(user)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    # Non-AI palette command opens the panel and computes a snapshot.
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> assert_has("[data-slot='command-item']", text: "Analyze current flow", timeout: 20_000)
    |> click("[data-slot='command-item']", "Analyze current flow")
    |> assert_has("[data-testid='analysis-panel']")
    |> assert_has("[data-testid='analysis-finding']", text: "Node has no outgoing connection")
    # Dismiss with a locked reason code.
    |> click("[data-testid='analysis-finding']", "Node has no outgoing connection")
    |> click("[data-testid='analysis-dismiss']")
    |> assert_has("[data-testid='analysis-dismiss-form']")
    |> click("label", "Intentional design")
    |> click("[data-testid='analysis-dismiss-confirm']")
    |> refute_has("[data-testid='analysis-finding']", text: "Node has no outgoing connection")
    # The disposition lives in the dismissed tab and is reversible.
    |> click("[data-testid='analysis-tab-dismissed']")
    |> assert_has("[data-testid='analysis-dismissed-finding']")
    |> click("[data-testid='analysis-dismissed-finding']")
    |> assert_has("[data-testid='analysis-restore']")
  end

  test "viewer inspects findings without disposition actions", %{conn: conn} do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    flow = seed_flow(project)

    viewer = user_fixture()
    membership_fixture(project, viewer, "viewer")

    conn
    |> authenticate(viewer)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='dialog-content'] [data-slot='command-input']")
    |> assert_has("[data-slot='command-item']", text: "Analyze current flow", timeout: 20_000)
    |> click("[data-slot='command-item']", "Analyze current flow")
    |> assert_has("[data-testid='analysis-panel']")
    |> assert_has("[data-testid='analysis-finding']", text: "Node has no outgoing connection")
    |> click("[data-testid='analysis-finding']", "Node has no outgoing connection")
    |> refute_has("[data-testid='analysis-dismiss']")
  end
end

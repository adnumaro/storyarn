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

  alias Storyarn.AI
  alias Storyarn.AI.Operation
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnTest.AI.FakeSettlement

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

  # Managed AI on a deterministic fake route: no provider, no secret, no cost.
  defp enable_managed_ai!(user, project) do
    FunWithFlags.enable(:ai_integrations, for_actor: user)
    scope = Storyarn.Accounts.Scope.for_user(user)
    {:ok, _policy} = AI.update_workspace_policy(scope, project.workspace_id, ["managed"])
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: user) end)
  end

  defp exhaust_allowance! do
    original = Application.get_env(:storyarn, FakeSettlement, [])
    Application.put_env(:storyarn, FakeSettlement, preflight_status: {:error, :allowance_exhausted})
    on_exit(fn -> Application.put_env(:storyarn, FakeSettlement, original) end)
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
    |> unwrap(fn _ ->
      assert Repo.aggregate(Storyarn.Flows.FindingDismissal, :count) == 1
    end)
    # The disposition lives in the dismissed tab and is reversible.
    |> click("[data-testid='analysis-tab-dismissed']")
    |> assert_has("[data-testid='analysis-dismissed-finding']")
    |> click("[data-testid='analysis-dismissed-finding']")
    |> assert_has("[data-testid='analysis-restore']")
  end

  test "editor explains a finding, and the narrative is marked stale when the flow moves with Storyarn AI", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = seed_flow(project)
    enable_managed_ai!(user, project)

    conn
    |> authenticate(user)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='command-item']", text: "Analyze current flow", timeout: 20_000)
    |> click("[data-slot='command-item']", "Analyze current flow")
    |> assert_has("[data-testid='analysis-panel']")
    |> click("[data-testid='analysis-finding']", "Node has no outgoing connection")
    # Preflight discloses payer and price BEFORE any operation exists.
    |> click("[data-testid='explanation-open']")
    |> assert_has("[data-testid='explanation-preflight']")
    |> assert_has("[data-testid='explanation-preflight']", text: "storyarn")
    |> unwrap(fn _ -> assert Repo.aggregate(Operation, :count) == 0 end)
    |> click("[data-testid='explanation-execute']")
    # Oban runs in :manual mode under MIX_ENV=test, so the background
    # execution is drained explicitly; the panel's poll then picks it up.
    |> unwrap(fn _ -> Oban.drain_queue(queue: :ai, with_safety: false) end)
    |> assert_has("[data-testid='explanation-result']", timeout: 20_000)
    |> assert_has("[data-testid='explanation-result']", text: "AI-generated")
    |> refute_has("[data-testid='explanation-stale']")
    # The flow moves under the narrative: it is marked obsolete, not refreshed.
    |> unwrap(fn _ -> node_fixture(flow, %{type: "dialogue"}) end)
    |> click("[data-testid='analysis-rerun']")
    |> assert_has("[data-testid='explanation-stale']", timeout: 20_000)
  end

  test "an exhausted allowance blocks the managed choice before execution", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = seed_flow(project)
    enable_managed_ai!(user, project)
    exhaust_allowance!()

    conn
    |> authenticate(user)
    |> visit(flow_path(project, flow))
    |> assert_has("[id^=\"flow-canvas-\"]")
    |> evaluate(open_palette_expression())
    |> assert_has("[data-slot='command-item']", text: "Analyze current flow", timeout: 20_000)
    |> click("[data-slot='command-item']", "Analyze current flow")
    |> click("[data-testid='analysis-finding']", "Node has no outgoing connection")
    |> click("[data-testid='explanation-open']")
    |> assert_has("[data-testid='explanation-error']", text: "no AI units left")
    |> refute_has("[data-testid='explanation-execute']")
    |> unwrap(fn _ -> assert Repo.aggregate(Operation, :count) == 0 end)
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
    # Positive proof of expansion before refuting the disposition action.
    |> assert_has("[data-testid='analysis-evidence-navigate']")
    |> refute_has("[data-testid='analysis-dismiss']")
  end
end

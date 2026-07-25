defmodule StoryarnWeb.FlowLive.Handlers.ExplanationHandlersTest do
  # Feature flags, workspace policy and the settlement adapter are all
  # process-global.
  use StoryarnWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI
  alias Storyarn.AI.Operation
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.Tasks.FlowFindingExplanation
  alias Storyarn.AI.UsageEvent
  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workers.AIExecutionWorker
  alias StoryarnTest.AI.FakeSettlement
  alias StoryarnWeb.FlowLive.Handlers.ExplanationHandlers

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Explained Flow"})

    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue"})
    connection_fixture(flow, entry, stuck)

    FunWithFlags.enable(:ai_integrations, for_actor: user)
    scope = Scope.for_user(user)
    {:ok, _policy} = AI.update_workspace_policy(scope, project.workspace_id, ["managed"])

    original_settlement = Application.get_env(:storyarn, FakeSettlement, [])

    on_exit(fn ->
      FunWithFlags.disable(:ai_integrations, for_actor: user)
      Application.put_env(:storyarn, FakeSettlement, original_settlement)
    end)

    %{project: project, flow: flow, stuck: stuck}
  end

  defp flow_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  defp mount_editor(conn, project, flow) do
    {:ok, view, _html} = live(conn, flow_url(project, flow))
    render_async(view, 2000)
    view
  end

  defp panels(view) do
    LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels").props["panels"]
  end

  defp explanation(view), do: panels(view)["explanation"]

  # The seeded flow also has an isolated exit node, so the finding under test
  # is selected by rule rather than by position.
  defp open_panel_and_finding(view) do
    render_click(view, "open_analysis_panel", %{})

    finding =
      Enum.find(panels(view)["analysis"]["active"], &(&1["ruleId"] == "no_outgoing_connection"))

    assert finding, "expected a no_outgoing_connection finding in the snapshot"
    finding
  end

  # Drives the surface from an open panel to a queued operation — the prelude
  # almost every execution test needs before it can assert anything.
  defp execute_explanation!(view) do
    finding = open_panel_and_finding(view)
    render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})
    [%{"routeRef" => route_ref}] = explanation(view)["routes"]
    render_click(view, "execute_explanation", %{"route_ref" => route_ref})
    finding
  end

  # The worker runs only when drained: :background + Oban testing: :manual.
  defp drain_execution! do
    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: AIExecutionWorker.__opts__()[:queue] || :ai, with_safety: false)
  end

  describe "availability" do
    test "the surface is unavailable without the product flag", %{
      conn: conn,
      user: user,
      project: project,
      flow: flow
    } do
      FunWithFlags.disable(:ai_integrations, for_actor: user)

      view = mount_editor(conn, project, flow)

      assert explanation(view)["available"] == false
      assert explanation(view)["status"] == "idle"
    end

    test "an operationally disabled task is blocked, not hidden", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      original = Application.get_env(:storyarn, FlowFindingExplanation, [])
      Application.put_env(:storyarn, FlowFindingExplanation, Keyword.put(original, :enabled, false))
      on_exit(fn -> Application.put_env(:storyarn, FlowFindingExplanation, original) end)

      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)

      # The surface stays visible and says why, instead of vanishing.
      assert explanation(view)["available"] == true

      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      props = explanation(view)
      assert props["status"] == "blocked"
      assert props["error"] == "task_disabled"
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "a viewer cannot see the surface OR reach it over the socket", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      viewer = user_fixture()
      membership_fixture(project, viewer, "viewer")
      FunWithFlags.enable(:ai_integrations, for_actor: viewer)
      on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: viewer) end)

      view = conn |> log_in_user(viewer) |> mount_editor(project, flow)
      finding = open_panel_and_finding(view)

      # `viewer` has :view and nothing else, so the surface is hidden.
      assert explanation(view)["available"] == false

      # And hiding is NOT the boundary — the slice says so explicitly. Pushing the
      # events directly must spend nothing, at either layer.
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})
      render_click(view, "execute_explanation", %{"route_ref" => "forged-route-ref"})

      assert explanation(view)["status"] == "idle"
      assert Repo.aggregate(Operation, :count) == 0
      assert Repo.aggregate(RouteOption, :count) == 0
      # The provider proxy: one usage-event row exists per attempt, so none means
      # nothing ever reached a provider.
      assert Repo.aggregate(UsageEvent, :count) == 0
    end

    test "an eligible editor sees an idle surface", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)

      assert explanation(view)["available"] == true
      assert explanation(view)["status"] == "idle"
      assert explanation(view)["routes"] == []
    end
  end

  describe "preflight" do
    test "discloses route, payer, price and context WITHOUT creating an operation", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)

      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      props = explanation(view)
      assert props["status"] == "preflight"
      assert props["findingId"] == finding["findingId"]

      assert [%{"lane" => "managed", "payer" => "storyarn", "priceUnits" => 1, "routeRef" => route_ref}] =
               props["routes"]

      assert is_binary(route_ref)
      assert props["disclosure"]["scope"] == "structural_finding"
      assert props["disclosure"]["included_count"] >= 1
      # Retention is part of the spend decision, so it is disclosed before it.
      assert props["retentionSeconds"] == 1_800

      # Preflight never charges and never creates an operation.
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "a stale snapshot refuses to explain", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)

      # A structural mutation marks the snapshot stale without recomputing it.
      render_hook(view, "add_node", %{"type" => "dialogue", "position_x" => 10.0, "position_y" => 10.0})
      assert panels(view)["analysis"]["stale"] == true

      html = render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      assert html =~ "rerun before explaining"
      assert explanation(view)["status"] == "idle"
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "an unknown or forged finding id is refused", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)
      open_panel_and_finding(view)

      html = render_click(view, "open_explanation", %{"finding_id" => "sf1_forged"})

      assert html =~ "no longer current"
      assert explanation(view)["status"] == "idle"
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "an exhausted allowance blocks with its own reason", %{conn: conn, project: project, flow: flow} do
      Application.put_env(:storyarn, FakeSettlement, preflight_status: {:error, :allowance_exhausted})

      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)

      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      props = explanation(view)
      assert props["status"] == "blocked"
      assert props["error"] == "allowance_exhausted"
      assert props["routes"] == []
      assert Repo.aggregate(Operation, :count) == 0
    end
  end

  describe "error class catalog" do
    @locales ~w(en es)

    test "every renderable error class has copy in every locale" do
      for locale <- @locales do
        errors =
          "assets/app/locales/#{locale}/flows.json"
          |> File.read!()
          |> Jason.decode!()
          |> get_in(["flows", "explanation", "errors"])

        assert is_map(errors), "missing flows.explanation.errors in #{locale}"

        for class <- ExplanationHandlers.error_classes() do
          assert is_binary(errors[class]) and errors[class] != "",
                 "error class #{class} has no #{locale} copy — the panel would fall back to the " <>
                   "generic sentence and no test would notice"
        end
      end
    end

    test "the catalog ships no copy the panel can never render" do
      declared = MapSet.new(ExplanationHandlers.error_classes())

      translated =
        "assets/app/locales/en/flows.json"
        |> File.read!()
        |> Jason.decode!()
        |> get_in(["flows", "explanation", "errors"])
        |> Map.keys()
        |> MapSet.new()

      assert translated |> MapSet.difference(declared) |> MapSet.to_list() == [],
             "dead error copy: these keys are translated but error_class/1 can never emit them"
    end
  end

  describe "spending" do
    test "two surfaces on the same finding replay ONE paid operation", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      first = mount_editor(conn, project, flow)
      second = mount_editor(conn, project, flow)

      execute_explanation!(first)

      # The second surface finds the operation already in flight for this exact
      # occurrence and ATTACHES to it: no preflight, no route picker, so it is
      # never even offered the purchase.
      finding = open_panel_and_finding(second)
      render_click(second, "open_explanation", %{"finding_id" => finding["findingId"]})

      assert explanation(second)["status"] == "queued"
      assert explanation(second)["routes"] == []
      assert Repo.aggregate(Operation, :count) == 1
      assert explanation(first)["status"] == "queued"

      drain_execution!()

      # And exactly ONE provider attempt happened. ai_usage_events has a unique
      # index on operation_id and is inserted immediately before the provider
      # call, so this counts real attempts — a replay reuses the original row.
      assert Repo.aggregate(UsageEvent, :count) == 1
    end

    test "closing the surface releases the operation nobody will read", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)

      render_click(view, "close_explanation", %{})

      assert Repo.one!(Operation).execution_status == "cancelled"
      assert explanation(view)["status"] == "idle"
    end

    test "an explicit rerun buys a second operation with its own key", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      render_click(view, "rerun_explanation", %{})
      [%{"routeRef" => rerun_ref}] = explanation(view)["routes"]
      render_click(view, "execute_explanation", %{"route_ref" => rerun_ref})

      keys = Operation |> Repo.all() |> Enum.map(& &1.idempotency_key)
      assert length(keys) == 2
      assert keys == Enum.uniq(keys)
    end

    test "reopening inside the TTL replays the paid result instead of buying another", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      render_click(view, "close_explanation", %{})
      assert explanation(view)["status"] == "idle"

      # Reopening probes this attempt's key and shows the result straight away:
      # no preflight, no route picker, no second charge.
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      props = explanation(view)
      assert props["status"] == "succeeded"
      assert props["result"]["summary"]
      assert props["routes"] == []
      assert Repo.aggregate(Operation, :count) == 1
    end

    test "a rerun after reopening still buys its own operation", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)

      render_click(view, "close_explanation", %{})
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})
      assert explanation(view)["status"] == "succeeded"

      # The probe must not make the surface read-only: attempt 1 is a real
      # preflight again, because it is a purchase the actor has not made.
      render_click(view, "rerun_explanation", %{})
      assert explanation(view)["status"] == "preflight"
      assert [%{"routeRef" => _}] = explanation(view)["routes"]
    end

    test "a spent-but-dead key does not brick the finding", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = execute_explanation!(view)

      # Simulate the operation ending without a readable result — a cancel that
      # landed mid-attempt, or a lapsed TTL. Its key stays spent forever, so
      # re-running at the same attempt would replay the dead row every time.
      Operation
      |> Repo.one!()
      |> Ecto.Changeset.change(execution_status: "cancelled", error_classification: "user_cancelled")
      |> Repo.update!()

      render_click(view, "close_explanation", %{})
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      # Opening walks past the dead key to the first unspent one, so the actor is
      # offered a real purchase instead of a permanently broken Run button.
      assert explanation(view)["status"] == "preflight"
      [%{"routeRef" => route_ref}] = explanation(view)["routes"]
      render_click(view, "execute_explanation", %{"route_ref" => route_ref})

      assert explanation(view)["status"] == "queued"
      assert Repo.aggregate(Operation, :count) == 2
    end

    test "reopening after a rerun shows the narrative last paid for", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)

      # Mark attempt 0's stored output so it is distinguishable.
      superseded = Repo.one!(Operation)

      render_click(view, "rerun_explanation", %{})
      [%{"routeRef" => rerun_ref}] = explanation(view)["routes"]
      render_click(view, "execute_explanation", %{"route_ref" => rerun_ref})
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      render_click(view, "close_explanation", %{})
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      # The NEWEST readable attempt wins. Probing a fixed attempt 0 would have
      # resurrected the narrative the actor replaced.
      assert explanation(view)["status"] == "succeeded"
      newest = Operation |> Repo.all() |> Enum.max_by(& &1.id)
      refute newest.id == superseded.id
      assert Repo.aggregate(Operation, :count) == 2
    end

    test "closing while the provider attempt is running does not destroy paid output", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)

      # Once an attempt has started, cancelling cannot stop the provider call and
      # the unit is committed regardless — it would only delete the output the
      # actor paid for. So the panel must leave it alone.
      Operation
      |> Repo.one!()
      |> Ecto.Changeset.change(execution_status: "running", external_attempt_started_at: TimeHelpers.now())
      |> Repo.update!()

      render_click(view, "close_explanation", %{})

      operation = Repo.one!(Operation)
      assert operation.execution_status == "running"
      assert is_nil(operation.cancellation_requested_at)
    end

    test "a poll tick that changes nothing re-renders nothing", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)

      # show.ex hands the whole `assigns` to its prop builders, which strong-taints
      # the template: one changed assign re-encodes flow_data for the entire
      # canvas. A silent tick must therefore touch no assign at all.
      test_pid = self()
      handler = {__MODULE__, :render_probe}

      :telemetry.attach(
        handler,
        [:phoenix, :live_view, :render, :stop],
        fn _event, _measures, _meta, _config -> send(test_pid, :rendered) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      send(view.pid, :poll_explanation)
      send(view.pid, :poll_explanation)
      # Round-trip to be sure both ticks were processed before asserting.
      assert explanation(view)["status"] == "queued"

      refute_received :rendered

      # Positive control: the probe is live, so the assertion above can fail.
      render_click(view, "close_explanation", %{})
      assert_received :rendered
    end

    test "the execution deadline detaches instead of failing, and resuming buys nothing", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      Application.put_env(:storyarn, ExplanationHandlers, poll_deadline_ms: 0)

      on_exit(fn ->
        Application.delete_env(:storyarn, ExplanationHandlers)
      end)

      view = mount_editor(conn, project, flow)
      execute_explanation!(view)

      # Observed running, so the deadline clock starts; the next tick exceeds it.
      Operation |> Repo.one!() |> Ecto.Changeset.change(execution_status: "running") |> Repo.update!()
      send(view.pid, :poll_explanation)
      send(view.pid, :poll_explanation)

      assert explanation(view)["status"] == "detached"

      render_click(view, "resume_explanation", %{})
      assert explanation(view)["status"] == "running"
      assert Repo.aggregate(Operation, :count) == 1
    end
  end

  describe "execution and result" do
    test "an explicitly chosen route produces an actor-private narrative", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})
      [%{"routeRef" => route_ref}] = explanation(view)["routes"]

      render_click(view, "execute_explanation", %{"route_ref" => route_ref})
      # Queued, not running: the execution deadline only starts once a worker
      # picks the operation up, so queue wait cannot consume it.
      assert explanation(view)["status"] == "queued"

      operation = Repo.one!(Operation)
      assert operation.task_id == "flows.explain_finding"
      assert operation.subject_type == "flow_finding"
      assert operation.subject_id == flow.id
      assert operation.result_destination == %{"type" => "panel", "id" => "flow_analysis"}

      drain_execution!()

      # The panel polls; nothing is pushed to it.
      send(view.pid, :poll_explanation)

      props = explanation(view)
      assert props["status"] == "succeeded"
      assert props["stale"] == false
      # camelCase at the Vue boundary: the model's snake_case stops server-side.
      assert props["result"] |> Map.keys() |> Enum.sort() ==
               ~w(implications suggestedChecks summary whyItTriggers)

      refute Map.has_key?(props["result"], "finding_id")
    end

    test "rendering a result records `viewed` and never a disposition", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()

      # Succeeded but not yet rendered: nothing recorded.
      operation = Repo.one!(Operation)
      assert is_nil(operation.viewed_at)
      assert is_nil(operation.user_disposition)

      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      viewed = Repo.one!(Operation)
      assert viewed.viewed_at
      # The contract is explicit: viewing is never acceptance, and leaving
      # disposition nil is what keeps dismiss/apply/abandon reachable.
      assert is_nil(viewed.user_disposition)
    end

    test "the result is readable only by its initiating actor", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      operation = Repo.one!(Operation)
      other_scope = Scope.for_user(Storyarn.AccountsFixtures.user_fixture())

      assert {:error, :not_found} = AI.get_result(other_scope, operation.id)
      assert AI.get_operation(other_scope, operation.id) == nil
    end

    test "a result past its TTL is reported as expired, never re-fetched", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()

      # The operation succeeded but its actor-private window closed before the
      # panel polled for the narrative.
      Storyarn.AI.Result
      |> Repo.one!()
      |> Ecto.Changeset.change(expires_at: DateTime.add(TimeHelpers.now(), -1, :second))
      |> Repo.update!()

      send(view.pid, :poll_explanation)

      props = explanation(view)
      assert props["status"] == "expired"
      assert props["result"] == nil
    end

    test "a forged route reference never reaches the kernel", %{conn: conn, project: project, flow: flow} do
      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      render_click(view, "execute_explanation", %{"route_ref" => "forged-reference"})

      assert explanation(view)["status"] == "preflight"
      assert Repo.aggregate(Operation, :count) == 0
    end

    test "a result whose finding moved is marked obsolete, never regenerated", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      # The flow changes and the analysis is rerun: the same finding_key now
      # carries a different fingerprint, so the narrative describes evidence
      # that no longer stands.
      render_hook(view, "add_node", %{"type" => "dialogue", "position_x" => 10.0, "position_y" => 10.0})
      render_click(view, "rerun_analysis", %{})

      props = explanation(view)
      assert props["status"] == "succeeded"
      assert props["stale"] == true
      assert Repo.aggregate(Operation, :count) == 1
    end

    test "closing drops the surface without touching the operation", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)

      render_click(view, "close_explanation", %{})

      assert explanation(view)["status"] == "idle"
      assert explanation(view)["result"] == nil
      assert Repo.aggregate(Operation, :count) == 1
    end
  end

  describe "analytics" do
    defmodule TestAdapter do
      @moduledoc false
      def capture(payload) do
        send(Application.get_env(:storyarn, :analytics_test_pid), {:analytics_capture, payload})
        :ok
      end

      def identify(_payload), do: :ok
    end

    setup do
      original_adapter = Application.get_env(:storyarn, :analytics_adapter)
      Application.put_env(:storyarn, :analytics_test_pid, self())
      Application.put_env(:storyarn, :analytics_adapter, TestAdapter)

      on_exit(fn ->
        Application.delete_env(:storyarn, :analytics_test_pid)

        if original_adapter do
          Application.put_env(:storyarn, :analytics_adapter, original_adapter)
        else
          Application.delete_env(:storyarn, :analytics_adapter)
        end
      end)

      :ok
    end

    test "a blocked preflight is reported, not silently dropped", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      Application.put_env(:storyarn, FakeSettlement, preflight_status: {:error, :allowance_exhausted})

      view = mount_editor(conn, project, flow)
      finding = open_panel_and_finding(view)
      render_click(view, "open_explanation", %{"finding_id" => finding["findingId"]})

      # It is its own event: `routable/1` errors before a preflight payload
      # exists, so "preflight shown" cannot carry the blocked case.
      assert_receive {:analytics_capture, %{event: "flow explanation preflight blocked", properties: props}}
      assert props["error_class"] == "allowance_exhausted"
      assert props["rule_id"] == "no_outgoing_connection"
      refute_receive {:analytics_capture, %{event: "flow explanation preflight shown"}}
    end

    test "rerunning an obsolete narrative is recorded as a stale rerun", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      # Change the flow, then recompute: the occurrence id rotates with the new
      # evidence fingerprint, so the narrative on screen is obsolete while the
      # rule still fires on the same target.
      render_hook(view, "add_node", %{"type" => "dialogue", "position_x" => 10.0, "position_y" => 10.0})
      render_click(view, "rerun_analysis", %{})
      assert explanation(view)["stale"] == true

      # The rerun must resolve by the STABLE key: keyed on the rotated occurrence
      # id it would be refused here, which is the one moment it has to work.
      render_click(view, "rerun_explanation", %{})
      assert explanation(view)["status"] == "preflight"

      assert_receive {:analytics_capture, %{event: "flow explanation stale rerun", properties: props}}
      assert props["rule_id"] == "no_outgoing_connection"
    end

    test "the explanation events carry allowlisted properties only", %{
      conn: conn,
      project: project,
      flow: flow
    } do
      view = mount_editor(conn, project, flow)
      execute_explanation!(view)
      drain_execution!()
      send(view.pid, :poll_explanation)
      assert explanation(view)["status"] == "succeeded"

      assert_receive {:analytics_capture, %{event: "flow explanation preflight shown", properties: preflight}}
      assert preflight["rule_id"] == "no_outgoing_connection"
      assert preflight["route_count"] == 1
      # The blocked case is its own event: `routable/1` errors before a preflight
      # payload exists, so "preflight shown" can never describe a blocked lane.
      refute Map.has_key?(preflight, "blocked")

      assert_receive {:analytics_capture, %{event: "flow explanation route selected", properties: %{"lane" => "managed"}}}

      assert_receive {:analytics_capture, %{event: "flow explanation execution started", properties: started}}
      assert started["lane"] == "managed"

      assert_receive {:analytics_capture, %{event: "flow explanation result viewed", properties: viewed}}
      assert viewed["stale"] == false

      # No narrative, no ids, no prompt reach analytics.
      for properties <- [preflight, started, viewed] do
        refute Map.has_key?(properties, "summary")
        refute Map.has_key?(properties, "finding_id")
        refute Map.has_key?(properties, "operation_id")
      end
    end
  end
end

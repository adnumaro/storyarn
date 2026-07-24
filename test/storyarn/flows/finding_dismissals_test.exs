defmodule Storyarn.Flows.FindingDismissalsTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FindingDismissal

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    # Reachable dead end → one deterministic canonical finding to dismiss.
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    stuck = node_fixture(flow, %{type: "dialogue"})
    connection_fixture(flow, entry, stuck)

    flow = Flows.get_flow!(project.id, flow.id)
    {:ok, analysis} = Flows.analyze_flow_structure(project.id, flow.id)
    [finding] = Enum.filter(analysis.findings, &(&1.rule_id == "no_outgoing_connection"))

    %{user: user, project: project, flow: flow, finding: finding}
  end

  defp dismiss!(flow, finding, user, attrs \\ %{}) do
    {:ok, dismissal} =
      Flows.dismiss_finding(
        flow,
        finding,
        Map.merge(%{reason_code: "intentional_design", dismissed_by_id: user.id}, attrs)
      )

    dismissal
  end

  describe "dismiss/3" do
    test "persists actor, reason and identity", %{flow: flow, finding: finding, user: user} do
      dismissal = dismiss!(flow, finding, user, %{note: "  by design  "})

      assert dismissal.project_id == flow.project_id
      assert dismissal.flow_id == flow.id
      assert dismissal.finding_key == finding.finding_key
      assert dismissal.rule_id == "no_outgoing_connection"
      assert dismissal.rule_version == finding.rule_version
      assert dismissal.evidence_fingerprint == finding.evidence_fingerprint
      assert dismissal.reason_code == "intentional_design"
      assert dismissal.note == "by design"
      assert dismissal.dismissed_by_id == user.id
      assert dismissal.restored_at == nil
    end

    test "rejects unknown reason codes", %{flow: flow, finding: finding, user: user} do
      assert {:error, changeset} =
               Flows.dismiss_finding(flow, finding, %{
                 reason_code: "wont_fix",
                 dismissed_by_id: user.id
               })

      assert %{reason_code: [_]} = errors_on(changeset)
    end

    test "requires a note for the other reason", %{flow: flow, finding: finding, user: user} do
      assert {:error, changeset} =
               Flows.dismiss_finding(flow, finding, %{
                 reason_code: "other",
                 note: "   ",
                 dismissed_by_id: user.id
               })

      assert %{note: [_]} = errors_on(changeset)

      assert {:ok, _} =
               Flows.dismiss_finding(flow, finding, %{
                 reason_code: "other",
                 note: "unforeseen case",
                 dismissed_by_id: user.id
               })
    end

    test "double dismissal is idempotent", %{flow: flow, finding: finding, user: user} do
      first = dismiss!(flow, finding, user)
      second = dismiss!(flow, finding, user)

      assert first.id == second.id
      assert Repo.aggregate(FindingDismissal, :count) == 1
    end

    test "concurrent dismissals collapse onto one active row", %{
      flow: flow,
      finding: finding,
      user: user
    } do
      results =
        1..8
        |> Task.async_stream(
          fn _i ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), self())

            Flows.dismiss_finding(flow, finding, %{
              reason_code: "intentional_design",
              dismissed_by_id: user.id
            })
          end,
          max_concurrency: 8,
          caller: self()
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, _}, &1))
      ids = results |> Enum.map(fn {:ok, d} -> d.id end) |> Enum.uniq()
      assert length(ids) == 1
      assert Repo.aggregate(FindingDismissal, :count) == 1
    end
  end

  describe "restore/3" do
    test "stamps restored actor/time and is idempotent", %{
      flow: flow,
      finding: finding,
      user: user
    } do
      other_user = user_fixture()
      dismissal = dismiss!(flow, finding, user)

      assert {:ok, restored} = Flows.restore_finding_dismissal(flow, dismissal.id, other_user.id)
      assert restored.restored_by_id == other_user.id
      assert restored.restored_at

      assert {:ok, again} = Flows.restore_finding_dismissal(flow, dismissal.id, user.id)
      assert again.restored_by_id == other_user.id

      assert Flows.list_active_finding_dismissals(flow) == []
    end

    test "keeps history and allows re-dismissal", %{flow: flow, finding: finding, user: user} do
      dismissal = dismiss!(flow, finding, user)
      {:ok, _} = Flows.restore_finding_dismissal(flow, dismissal.id, user.id)

      re_dismissal = dismiss!(flow, finding, user)

      assert re_dismissal.id != dismissal.id
      assert Repo.aggregate(FindingDismissal, :count) == 2
      assert [active] = Flows.list_active_finding_dismissals(flow)
      assert active.id == re_dismissal.id
    end

    test "rejects ids from another flow", %{project: project, flow: flow, finding: finding, user: user} do
      dismissal = dismiss!(flow, finding, user)
      other_flow = Flows.get_flow!(project.id, flow_fixture(project).id)

      assert {:error, :not_found} =
               Flows.restore_finding_dismissal(other_flow, dismissal.id, user.id)
    end
  end

  describe "isolation" do
    test "dismissals never leak across projects", %{flow: flow, finding: finding, user: user} do
      dismiss!(flow, finding, user)

      other_user = user_fixture()
      other_project = project_fixture(other_user)
      other_flow = Flows.get_flow!(other_project.id, flow_fixture(other_project).id)

      assert Flows.list_active_finding_dismissals(other_flow) == []
    end
  end

  describe "split_findings/2" do
    test "suppresses only the exact occurrence and reactivates on evidence change", %{
      project: project,
      flow: flow,
      finding: finding,
      user: user
    } do
      dismiss!(flow, finding, user)
      active_dismissals = Flows.list_active_finding_dismissals(flow)

      {:ok, analysis} = Flows.analyze_flow_structure(project.id, flow.id)
      {active, dismissed} = Flows.split_findings(analysis.findings, active_dismissals)

      dismissed_keys = Enum.map(dismissed, fn {f, _d} -> f.finding_key end)
      assert finding.finding_key in dismissed_keys
      refute Enum.any?(active, &(&1.finding_key == finding.finding_key))

      # Topology change → new evidence fingerprint → the dismissal no longer
      # matches and the finding reactivates.
      node_fixture(flow, %{type: "dialogue"})
      {:ok, drifted} = Flows.analyze_flow_structure(project.id, flow.id)
      {active_after, dismissed_after} = Flows.split_findings(drifted.findings, active_dismissals)

      assert Enum.any?(active_after, &(&1.finding_key == finding.finding_key))
      refute Enum.any?(dismissed_after, fn {f, _d} -> f.finding_key == finding.finding_key end)
    end
  end
end

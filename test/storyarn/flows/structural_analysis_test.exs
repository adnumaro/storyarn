defmodule Storyarn.Flows.StructuralAnalysisTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.StructuralAnalysis.Rules

  # Drift states that the CRUD guards forbid but the analysis must handle
  # (imports, legacy data, cross-flow pin drift) are set up at the Repo level.
  defp force_node!(flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp force_data!(node, data) do
    node |> Ecto.Changeset.change(data: data) |> Repo.update!()
  end

  defp soft_delete!(node) do
    node
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end

  defp analyze!(project, flow) do
    {:ok, analysis} = Flows.analyze_flow_structure(project.id, flow.id)
    analysis
  end

  defp rule_findings(analysis, rule_id) do
    Enum.filter(analysis.findings, &(&1.rule_id == rule_id))
  end

  defp entry_node(flow), do: flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
  defp exit_node(flow), do: flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{project: project, flow: flow}
  end

  describe "entry rules" do
    test "clean flow emits no entry findings", %{project: project, flow: flow} do
      entry = entry_node(flow)
      connection_fixture(flow, entry, exit_node(flow))

      analysis = analyze!(project, flow)

      assert rule_findings(analysis, "missing_entry") == []
      assert rule_findings(analysis, "multiple_entries") == []
    end

    test "missing entry targets the flow", %{project: project, flow: flow} do
      soft_delete!(entry_node(flow))

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_entry")
      assert finding.target == %{type: :flow, id: flow.id}
      assert finding.category == :structure
      assert finding.severity == :error
      assert finding.evidence == [%{type: "flow", id: flow.id}]
    end

    test "multiple entries lists every entry node as evidence", %{project: project, flow: flow} do
      entry = entry_node(flow)
      extra = force_node!(flow, %{type: "entry", data: %{}, position_x: 0.0, position_y: 0.0})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "multiple_entries")
      assert finding.details.count == 2

      evidence_ids = finding.evidence |> Enum.filter(&(&1.type == "flow_node")) |> Enum.map(& &1.id)
      assert Enum.sort(evidence_ids) == Enum.sort([entry.id, extra.id])
    end

    test "without entry no unreachable claims are made", %{project: project, flow: flow} do
      soft_delete!(entry_node(flow))
      node_fixture(flow, %{type: "dialogue"})

      analysis = analyze!(project, flow)

      assert rule_findings(analysis, "unreachable_node") == []
    end
  end

  describe "reachability rules" do
    test "detached branch is unreachable, jump virtual edge reaches its hub", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      island_a = node_fixture(flow, %{type: "dialogue"})
      island_b = node_fixture(flow, %{type: "dialogue"})

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)
      connection_fixture(flow, island_a, island_b)

      analysis = analyze!(project, flow)

      unreachable_ids = analysis |> rule_findings("unreachable_node") |> Enum.map(& &1.target.id)
      assert Enum.sort(unreachable_ids) == Enum.sort([island_a.id, island_b.id])
    end

    test "isolated node is isolated_node, not unreachable_node nor dead end", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      connection_fixture(flow, entry, exit_node(flow))
      isolated = node_fixture(flow, %{type: "dialogue"})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "isolated_node")
      assert finding.target.id == isolated.id
      assert rule_findings(analysis, "unreachable_node") == []
      assert rule_findings(analysis, "no_outgoing_connection") == []
    end

    test "cycles are valid", %{project: project, flow: flow} do
      entry = entry_node(flow)
      a = node_fixture(flow, %{type: "dialogue"})
      b = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, a)
      connection_fixture(flow, a, b)
      connection_fixture(flow, b, a)

      analysis = analyze!(project, flow)

      assert rule_findings(analysis, "unreachable_node") == []
    end
  end

  describe "output rules" do
    test "reachable dead end emits no_outgoing_connection", %{project: project, flow: flow} do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "no_outgoing_connection")
      assert finding.target.id == stuck.id
    end

    test "unreachable dead end emits only unreachable_node", %{project: project, flow: flow} do
      entry = entry_node(flow)
      connection_fixture(flow, entry, exit_node(flow))
      detached_a = node_fixture(flow, %{type: "dialogue"})
      detached_b = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, detached_a, detached_b)

      analysis = analyze!(project, flow)

      unreachable_ids = analysis |> rule_findings("unreachable_node") |> Enum.map(& &1.target.id)
      assert detached_b.id in unreachable_ids
      assert rule_findings(analysis, "no_outgoing_connection") == []
    end

    test "partially connected responses emit missing_output_connections", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [%{"id" => "r1", "text" => "Yes"}, %{"id" => "r2", "text" => "No"}]
          }
        })

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_output_connections")
      assert finding.target.id == dialogue.id
      assert finding.details.pins == ["r2"]
    end
  end

  describe "pin validity rules" do
    test "stale source pin emits invalid_output_pins with connection evidence", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Choose", "responses" => [%{"id" => "r1", "text" => "Yes"}]}
        })

      connection_fixture(flow, entry, dialogue)
      stale_conn = connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})
      force_data!(dialogue, %{"text" => "Choose", "responses" => []})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "invalid_output_pins")
      assert finding.target.id == dialogue.id
      assert finding.details.pins == ["r1"]
      assert %{type: "flow_connection", id: stale_conn.id} in finding.evidence
    end
  end

  describe "orphan hub rule" do
    test "hub without incoming connection nor jump is orphan", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      orphan = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "lost", "color" => "violet"}})
      connection_fixture(flow, entry, exit_n)
      connection_fixture(flow, orphan, exit_n)

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "orphan_hub")
      assert finding.target.id == orphan.id
      assert finding.details.hub_id == "lost"
    end

    test "hub referenced only by a jump is not orphan", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)

      analysis = analyze!(project, flow)

      assert rule_findings(analysis, "orphan_hub") == []
    end
  end

  describe "reference integrity rules" do
    test "jump with removed hub emits stale_jump_target", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)
      soft_delete!(hub)

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "stale_jump_target")
      assert finding.target.id == jump.id
      assert finding.category == :reference_integrity
    end

    test "jump without target emits missing_jump_target", %{project: project, flow: flow} do
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      _ = hub
      force_data!(jump, %{"target_hub_id" => ""})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_jump_target")
      assert finding.target.id == jump.id
    end

    test "subflow with deleted referenced flow emits stale_subflow_reference", %{
      project: project,
      flow: flow
    } do
      target_flow = flow_fixture(project)

      subflow =
        node_fixture(flow, %{type: "subflow", data: %{"referenced_flow_id" => target_flow.id}})

      # Repo-level soft delete: the trash-refs sweep would clear the node's
      # reference on a domain delete; stale refs exist only as drift.
      project.id
      |> Flows.get_flow!(target_flow.id)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "stale_subflow_reference")
      assert finding.target.id == subflow.id
    end

    test "subflow without reference emits missing_subflow_reference", %{
      project: project,
      flow: flow
    } do
      subflow = node_fixture(flow, %{type: "subflow", data: %{}})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_subflow_reference")
      assert finding.target.id == subflow.id
    end

    test "exit in flow_reference mode with dead flow emits stale_exit_flow_reference", %{
      project: project,
      flow: flow
    } do
      target_flow = flow_fixture(project)
      exit_n = exit_node(flow)

      force_data!(exit_n, %{
        "exit_mode" => "flow_reference",
        "referenced_flow_id" => target_flow.id
      })

      project.id
      |> Flows.get_flow!(target_flow.id)
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "stale_exit_flow_reference")
      assert finding.target.id == exit_n.id
    end
  end

  describe "determinism and identity" do
    test "findings are identical and identically ordered across runs", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      first = analyze!(project, flow)
      second = analyze!(project, flow)

      assert first.findings == second.findings
      assert first.graph_digest == second.graph_digest
    end

    test "ordering is canonical: category, then severity, then rule", %{
      project: project,
      flow: flow
    } do
      # structure error (missing entry after delete) + structure warning
      # (isolated) + reference_integrity error (missing subflow ref)
      soft_delete!(entry_node(flow))
      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "subflow", data: %{}})

      analysis = analyze!(project, flow)
      categories = Enum.map(analysis.findings, &{&1.category, &1.severity})

      assert categories ==
               Enum.sort_by(categories, fn {category, severity} ->
                 {Map.fetch!(%{structure: 0, reference_integrity: 1}, category),
                  Map.fetch!(%{error: 0, warning: 1}, severity)}
               end)
    end

    test "evidence change rotates finding_id but keeps finding_key", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      [before_finding] = rule_findings(analyze!(project, flow), "no_outgoing_connection")

      # An unrelated topology change alters the graph digest → new evidence
      # fingerprint for the negative claim, same stable key.
      node_fixture(flow, %{type: "dialogue"})

      [after_finding] = rule_findings(analyze!(project, flow), "no_outgoing_connection")

      assert before_finding.finding_key == after_finding.finding_key
      assert before_finding.evidence_fingerprint != after_finding.evidence_fingerprint
      assert before_finding.finding_id != after_finding.finding_id
    end

    test "every emitted rule id belongs to the frozen catalog", %{project: project, flow: flow} do
      soft_delete!(entry_node(flow))
      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "subflow", data: %{}})

      analysis = analyze!(project, flow)

      assert analysis.findings != []
      assert Enum.all?(analysis.findings, &Rules.known?(&1.rule_id))
    end
  end

  describe "dashboard adapter equivalence" do
    test "detect_flow_issues counts equal the canonical findings", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      other_flow = flow_fixture(project)
      soft_delete!(entry_node(other_flow))

      issues = Flows.detect_flow_issues(project.id)
      analyses = Flows.analyze_project_structure(project.id)

      for analysis <- analyses,
          {issue_type, rule_id} <- [
            no_entry: "missing_entry",
            disconnected_nodes: "isolated_node",
            dead_end_nodes: "no_outgoing_connection"
          ] do
        canonical_count = Enum.count(analysis.findings, &(&1.rule_id == rule_id))

        dashboard_count =
          issues
          |> Enum.find(&(&1.flow_id == analysis.flow_id and &1.issue_type == issue_type))
          |> then(&((&1 && &1.count) || 0))

        assert dashboard_count == canonical_count,
               "#{issue_type} for flow #{analysis.flow_id}: dashboard=#{dashboard_count} canonical=#{canonical_count}"
      end
    end

    test "hub connected only through a jump is not disconnected in the dashboard", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)

      issues = Flows.detect_flow_issues(project.id)

      refute Enum.any?(
               issues,
               &(&1.flow_id == flow.id and &1.issue_type == :disconnected_nodes)
             )
    end
  end

  describe "parity with the editor serializer" do
    test "engine flags equal serializer flags on a drifted graph", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Choose", "responses" => [%{"id" => "r1", "text" => "Yes"}]}
        })

      island = node_fixture(flow, %{type: "dialogue"})
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})

      connection_fixture(flow, entry, dialogue)
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)
      force_data!(dialogue, %{"text" => "Choose", "responses" => []})
      _ = island

      serialized = project.id |> Flows.get_flow!(flow.id) |> Flows.serialize_for_canvas()
      {:ok, analysis} = Flows.analyze_flow_structure(project.id, flow.id)
      graph = analysis.graph

      for payload <- serialized.nodes, payload.type != "sequence" do
        assert Map.get(payload.data, "unreachable", false) ==
                 (MapSet.member?(graph.unreachable_ids, payload.id) and
                    Storyarn.Flows.NodeConnectionRules.can_be_unreachable?(payload.type)),
               "unreachable mismatch for node #{payload.id} (#{payload.type})"

        assert Map.get(payload.data, "dead_end", false) ==
                 MapSet.member?(graph.dead_end_ids, payload.id),
               "dead_end mismatch for node #{payload.id} (#{payload.type})"

        assert Map.get(payload.data, "invalid_output_pins", []) ==
                 Map.get(graph.invalid_output_pins, payload.id, []),
               "invalid_output_pins mismatch for node #{payload.id}"
      end
    end
  end
end

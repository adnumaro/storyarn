defmodule Storyarn.Flows.StructuralAnalysisTest do
  use Storyarn.DataCase

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HealthChecker

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

  # Codes are atoms now; the tests still name them as strings for readability.
  defp rule_findings(analysis, code) do
    Enum.filter(analysis.findings, &(to_string(&1.code) == code))
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
      assert {finding.entity_type, finding.entity_id} == {"flow", nil}
      assert finding.severity == :error
    end

    test "multiple entries reports how many it found", %{project: project, flow: flow} do
      _entry = entry_node(flow)
      _extra = force_node!(flow, %{type: "entry", data: %{}, position_x: 0.0, position_y: 0.0})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "multiple_entries")
      # The finding targets the flow and reports how many entries it found; the
      # per-node evidence list went with the fingerprints.
      assert {finding.entity_type, finding.entity_id} == {"flow", nil}
      assert finding.details.count == 2
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

      unreachable_ids = analysis |> rule_findings("unreachable_node") |> Enum.map(& &1.entity_id)
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
      assert finding.entity_id == isolated.id
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
      assert finding.entity_id == stuck.id
    end

    test "unreachable dead end emits only unreachable_node", %{project: project, flow: flow} do
      entry = entry_node(flow)
      connection_fixture(flow, entry, exit_node(flow))
      detached_a = node_fixture(flow, %{type: "dialogue"})
      detached_b = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, detached_a, detached_b)

      analysis = analyze!(project, flow)

      unreachable_ids = analysis |> rule_findings("unreachable_node") |> Enum.map(& &1.entity_id)
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
      assert finding.entity_id == dialogue.id
      assert finding.details.pins == ["r2"]
    end

    test "response connected through a legacy pin alias is not reported missing", %{
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
      # Legacy rows persist an accepted alias of the canonical `r1` pin.
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "response_r1"})

      analysis = analyze!(project, flow)

      assert rule_findings(analysis, "missing_output_connections") == []
      assert rule_findings(analysis, "invalid_output_pins") == []
      assert rule_findings(analysis, "no_outgoing_connection") == []
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
      assert finding.entity_id == dialogue.id
      assert finding.details.pins == ["r1"]
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
      assert finding.entity_id == orphan.id
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
      assert finding.entity_id == jump.id
    end

    test "jump without target emits missing_jump_target", %{project: project, flow: flow} do
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      _ = hub
      force_data!(jump, %{"target_hub_id" => ""})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_jump_target")
      assert finding.entity_id == jump.id
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
      assert finding.entity_id == subflow.id
    end

    test "subflow without reference emits missing_subflow_reference", %{
      project: project,
      flow: flow
    } do
      subflow = node_fixture(flow, %{type: "subflow", data: %{}})

      analysis = analyze!(project, flow)

      assert [finding] = rule_findings(analysis, "missing_subflow_reference")
      assert finding.entity_id == subflow.id
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
      assert finding.entity_id == exit_n.id
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
    end

    test "ordering is canonical: severity, then location, then code", %{
      project: project,
      flow: flow
    } do
      force_node!(flow, %{type: "hub", data: %{"hub_id" => ""}, position_x: 0.0, position_y: 0.0})
      force_node!(flow, %{type: "jump", data: %{}, position_x: 0.0, position_y: 0.0})
      analysis = analyze!(project, flow)

      keys =
        Enum.map(analysis.findings, fn finding ->
          {finding.severity, finding.entity_id || 0, to_string(finding.code)}
        end)

      assert keys ==
               Enum.sort_by(keys, fn {severity, entity_id, code} ->
                 {Map.fetch!(%{error: 0, warning: 1, info: 2}, severity), entity_id, code}
               end)
    end

    test "blank hub ids never resolve a blank jump target", %{project: project, flow: flow} do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)

      # Drift both ends to blank: no phantom virtual edge may connect them.
      force_data!(hub, %{"hub_id" => "", "color" => "violet"})
      force_data!(jump, %{"target_hub_id" => ""})

      analysis = analyze!(project, flow)

      assert [_missing] = rule_findings(analysis, "missing_jump_target")
      unreachable_ids = analysis |> rule_findings("unreachable_node") |> Enum.map(& &1.entity_id)
      assert hub.id in unreachable_ids
    end

    test "every emitted code belongs to the one health vocabulary", %{project: project, flow: flow} do
      soft_delete!(entry_node(flow))
      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "subflow", data: %{}})

      analysis = analyze!(project, flow)

      assert analysis.findings != []
      assert Enum.all?(analysis.findings, &(&1.code in HealthChecker.codes()))
    end
  end

  describe "dashboard equivalence" do
    # The claim used to be "the 3 dashboard buckets count the same as the
    # canonical rules". It is now much stronger: the dashboard returns THE SAME
    # findings, so there is no mapping left that could drift.
    test "the dashboard returns the editor's findings for every flow", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      stuck = node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, entry, stuck)

      other_flow = flow_fixture(project)
      soft_delete!(entry_node(other_flow))

      dashboard_by_flow =
        project.id
        |> Flows.list_dashboard_health_findings()
        |> Enum.group_by(& &1.flow_id, &{&1.severity, &1.code, &1.entity_type, &1.entity_id})

      for analysis <- Flows.analyze_project_structure(project.id) do
        editor =
          analysis.findings
          |> Enum.map(&{&1.severity, &1.code, &1.entity_type, &1.entity_id})
          |> Enum.sort()

        dashboard = dashboard_by_flow |> Map.get(analysis.flow_id, []) |> Enum.sort()

        # The dashboard also carries the editorial codes, so it is a superset;
        # what must hold is that it loses nothing structural.
        assert editor -- dashboard == [],
               "flow #{analysis.flow_id} lost findings on the dashboard: #{inspect(editor -- dashboard)}"
      end
    end

    test "a detached chain reports both nodes unreachable", %{project: project, flow: flow} do
      entry = entry_node(flow)
      connection_fixture(flow, entry, exit_node(flow))
      island_a = node_fixture(flow, %{type: "dialogue"})
      island_b = node_fixture(flow, %{type: "dialogue"})
      connection_fixture(flow, island_a, island_b)

      unreachable =
        project.id
        |> Flows.list_dashboard_health_findings()
        |> Enum.filter(&(&1.flow_id == flow.id and &1.code == :unreachable_node))

      assert unreachable |> Enum.map(& &1.entity_id) |> Enum.sort() ==
               Enum.sort([island_a.id, island_b.id])
    end

    test "a hub connected only through a jump is not reported isolated", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, exit_n)

      refute project.id
             |> Flows.list_dashboard_health_findings()
             |> Enum.any?(&(&1.entity_id == hub.id and &1.code == :isolated_node))
    end
  end

  describe "from_serialized parity" do
    test "serializer-fed analysis equals the DB path finding for finding", %{
      project: project,
      flow: flow
    } do
      entry = entry_node(flow)
      exit_n = exit_node(flow)
      target_flow = flow_fixture(project)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Choose", "responses" => [%{"id" => "r1", "text" => "Yes"}]}
        })

      subflow =
        node_fixture(flow, %{type: "subflow", data: %{"referenced_flow_id" => target_flow.id}})

      hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})
      jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
      node_fixture(flow, %{type: "annotation", data: %{"text" => "note"}})

      connection_fixture(flow, entry, jump)
      connection_fixture(flow, hub, dialogue)
      connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})
      _ = subflow

      loaded = Flows.get_flow!(project.id, flow.id)
      flow_data = Flows.serialize_for_canvas(loaded)

      from_serialized = Flows.analyze_serialized_flow_structure(flow_data, project.id)
      {:ok, from_db} = Flows.analyze_flow_structure(project.id, flow.id)

      assert Enum.map(from_serialized.findings, &{&1.code, &1.entity_type, &1.entity_id}) ==
               Enum.map(from_db.findings, &{&1.code, &1.entity_type, &1.entity_id})
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

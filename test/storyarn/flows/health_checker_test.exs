defmodule Storyarn.Flows.HealthCheckerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{project: project, flow: flow}
  end

  # These fixtures are nodes without connections, so only the codes derivable from
  # a node's own data appear, plus `isolated_node`. The graph-derived family —
  # pin validity, dead ends, unreachability with a real Entry — is covered in
  # `structural_analysis_test.exs`, which builds actual graphs. The composition
  # itself is covered in `health_consolidation_test.exs`.
  describe "severity contract" do
    test "treats invalid graph configuration and broken references as errors" do
      flow_data = %{
        nodes: [
          health_node(1, "entry"),
          health_node(2, "subflow", %{"referenced_flow_id" => nil}),
          health_node(3, "subflow", %{
            "referenced_flow_id" => 99,
            "stale_reference" => true
          }),
          health_node(4, "jump", %{"target_hub_id" => nil}),
          health_node(5, "jump", %{"target_hub_id" => "missing-hub"}),
          health_node(6, "exit", %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }),
          health_node(7, "exit", %{
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => 100,
            "stale_reference" => true
          }),
          health_node(8, "instruction", %{
            "has_stale_refs" => true,
            "invalid_output_pins" => ["obsolete"],
            "invalid_input_pins" => ["legacy-input"]
          })
        ]
      }

      assert error_codes(flow_data) ==
               MapSet.new([
                 :missing_subflow_reference,
                 :stale_subflow_reference,
                 :missing_jump_target,
                 :stale_jump_target,
                 :missing_exit_flow_reference,
                 :stale_exit_flow_reference,
                 :stale_variable_reference
               ])

      assert :missing_entry in error_codes(%{nodes: []})

      assert :multiple_entries in error_codes(%{nodes: [health_node(1, "entry"), health_node(2, "entry")]})
    end

    test "treats incomplete, risky, or disconnected authoring as warnings" do
      incomplete_condition = %{
        "blocks" => [
          %{
            "type" => "block",
            "rules" => [
              %{"sheet" => "hero", "variable" => nil, "operator" => "equals", "value" => "x"}
            ]
          }
        ]
      }

      incomplete_assignment = %{
        "sheet" => "hero",
        "variable" => nil,
        "operator" => "set",
        "value" => "x"
      }

      flow_data = %{
        nodes: [
          health_node(1, "entry"),
          health_node(2, "dialogue", %{
            "text" => "",
            "speaker_sheet_id" => nil,
            "has_type_warnings" => true,
            "unreachable" => true,
            "missing_output_pins" => ["response-b"],
            "responses" => [
              %{
                "id" => "response-a",
                "text" => "",
                "has_type_warnings" => true,
                "condition" => incomplete_condition,
                "instruction_assignments" => [incomplete_assignment]
              }
            ]
          }),
          health_node(3, "condition", %{"condition" => incomplete_condition}),
          health_node(4, "instruction", %{"assignments" => [incomplete_assignment]}),
          health_node(5, "subflow", %{"dead_end" => true})
        ]
      }

      assert warning_codes(flow_data) ==
               MapSet.new([
                 :variable_type_mismatch,
                 :response_type_mismatch,
                 :missing_dialogue_text,
                 :missing_dialogue_speaker,
                 :empty_dialogue_response,
                 :incomplete_response_condition,
                 :incomplete_response_assignment,
                 :incomplete_condition,
                 :incomplete_instruction_assignment,
                 :isolated_node
               ])
    end

    test "reserves info for valid no-op/default authoring states" do
      flow_data = %{
        nodes: [
          health_node(1, "entry"),
          health_node(2, "instruction", %{"assignments" => []}),
          health_node(3, "condition", %{"condition" => %{"blocks" => []}})
        ]
      }

      assert info_codes(flow_data) == MapSet.new([:empty_instruction, :empty_condition])
    end
  end

  describe "required output connections" do
    test "reports a subflow with no outgoing connection as a warning", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      # Reachable on purpose: an unreachable node reports only `unreachable_node`.
      connection_fixture(flow, entry_node(flow), subflow)

      {_flow_data, findings} = check_flow(project, flow)
      subflow_id = subflow.id

      assert %{
               severity: :warning,
               code: :no_outgoing_connection,
               entity_id: ^subflow_id
             } = finding_for(findings, subflow, :no_outgoing_connection)
    end

    test "an obsolete subflow pin is invalid and does not count as an outgoing connection", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      target = exit_node(flow)
      # Reachable on purpose: an unreachable node reports only `unreachable_node`.
      connection_fixture(flow, entry_node(flow), subflow)

      # Deliberately bypass the productive writer: this health-check regression
      # exercises repair visibility for a legacy/corrupt pin that new writes reject.
      Repo.insert!(%FlowConnection{
        flow_id: flow.id,
        source_node_id: subflow.id,
        target_node_id: target.id,
        source_pin: "exit_obsolete",
        target_pin: "input"
      })

      {flow_data, findings} = check_flow(project, flow)
      subflow_data = serialized_node(flow_data, subflow).data

      assert subflow_data["dead_end"] == true
      assert subflow_data["invalid_output_pins"] == ["exit_obsolete"]

      assert %{
               severity: :error,
               details: %{pins: ["exit_obsolete"]}
             } = finding_for(findings, subflow, :invalid_output_pins)

      assert %{severity: :warning} =
               finding_for(findings, subflow, :no_outgoing_connection)
    end

    test "reports the unconnected boolean condition branch", %{
      project: project,
      flow: flow
    } do
      condition =
        node_fixture(flow, %{
          type: "condition",
          data: %{
            "condition" => %{"logic" => "all", "rules" => []},
            "switch_mode" => false
          }
        })

      connection_fixture(flow, entry_node(flow), condition)
      connection_fixture(flow, condition, exit_node(flow), %{source_pin: "true"})

      {_flow_data, findings} = check_flow(project, flow)

      assert %{
               severity: :warning,
               details: %{pins: ["false"]}
             } = finding_for(findings, condition, :missing_output_connections)

      refute finding_for(findings, condition, :no_outgoing_connection)
    end

    test "reports each unconnected dialogue response branch", %{
      project: project,
      flow: flow
    } do
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "Choose",
            "responses" => [
              response("response-a", "First"),
              response("response-b", "Second")
            ]
          }
        })

      connection_fixture(flow, entry_node(flow), dialogue)
      connection_fixture(flow, dialogue, exit_node(flow), %{source_pin: "response-a"})

      {_flow_data, findings} = check_flow(project, flow)

      assert %{
               severity: :warning,
               details: %{pins: ["response-b"]}
             } = finding_for(findings, dialogue, :missing_output_connections)

      refute finding_for(findings, dialogue, :no_outgoing_connection)
    end

    test "reports each unconnected referenced-flow exit branch", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)
      connected_exit = exit_node(referenced_flow)

      missing_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          data: %{"label" => "Alternate"}
        })

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      connection_fixture(flow, entry_node(flow), subflow)

      connection_fixture(flow, subflow, exit_node(flow), %{
        source_pin: "exit_#{connected_exit.id}"
      })

      {_flow_data, findings} = check_flow(project, flow)
      missing_exit_pin = "exit_#{missing_exit.id}"

      assert %{
               severity: :warning,
               details: %{pins: [^missing_exit_pin]}
             } = finding_for(findings, subflow, :missing_output_connections)

      refute finding_for(findings, subflow, :no_outgoing_connection)
    end
  end

  describe "reachability" do
    test "a jump makes its target hub reachable without a physical jump-to-hub connection", %{
      project: project,
      flow: flow
    } do
      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "destination", "name" => "Destination"}
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "destination"}
        })

      connection_fixture(flow, entry_node(flow), jump)
      connection_fixture(flow, hub, exit_node(flow))

      {flow_data, findings} = check_flow(project, flow)

      refute serialized_node(flow_data, hub).data["unreachable"]
      refute finding_for(findings, hub, :unreachable_node)
    end
  end

  describe "attribution" do
    # A project-wide sweep groups by `flow_id`. A checker that cannot fill its own
    # findings' flow forces every caller to patch them afterwards, and the one that
    # forgets collapses every flow under a nil key.
    test "every finding carries the flow the snapshot names" do
      findings =
        Flows.HealthChecker.check(%{
          flow_id: 4242,
          nodes: [
            health_node(1, "instruction", %{"assignments" => []}),
            health_node(2, "dialogue", %{"text" => ""})
          ]
        })

      # Positive control: the fixture really does emit findings from both halves
      # of the editorial catalog.
      assert :empty_instruction in Enum.map(findings, & &1.code)
      assert :missing_dialogue_text in Enum.map(findings, & &1.code)

      assert Enum.all?(findings, &(&1.flow_id == 4242)),
             "flow ids: #{inspect(Enum.map(findings, &{&1.code, &1.flow_id}))}"
    end

    test "a snapshot without a flow still checks, attributing to no flow" do
      findings = Flows.HealthChecker.check(%{nodes: [health_node(1, "instruction", %{"assignments" => []})]})

      assert Enum.map(findings, & &1.code) == [:empty_instruction]
      assert Enum.all?(findings, &is_nil(&1.flow_id))
    end
  end

  defp check_flow(project, flow) do
    flow_data =
      project.id
      |> Flows.get_flow!(flow.id)
      |> Flows.serialize_for_canvas()

    {flow_data, Flows.flow_health_findings(flow_data, project.id)}
  end

  defp entry_node(flow), do: Enum.find(Flows.list_nodes(flow.id), &(&1.type == "entry"))
  defp exit_node(flow), do: Enum.find(Flows.list_nodes(flow.id), &(&1.type == "exit"))

  defp serialized_node(flow_data, node) do
    Enum.find(flow_data.nodes, &(&1.id == node.id))
  end

  defp finding_for(findings, node, code) do
    Enum.find(findings, &(&1.entity_id == node.id and &1.code == code))
  end

  defp health_node(id, type, data \\ %{}), do: %{id: id, type: type, data: data}

  defp composed_findings(flow_data) do
    flow_data
    |> Map.put_new(:id, 1)
    |> Map.put_new(:name, "Flow")
    |> Map.put_new(:connections, [])
    |> Storyarn.Flows.StructuralAnalysis.Topology.from_serialized(1)
    |> Storyarn.Flows.StructuralAnalysis.findings()
  end

  defp error_codes(flow_data), do: finding_codes(flow_data, :error)
  defp warning_codes(flow_data), do: finding_codes(flow_data, :warning)
  defp info_codes(flow_data), do: finding_codes(flow_data, :info)

  # The COMPOSED flow health, which is what the product now shows: the editorial
  # checks plus the graph-derived ones, through the one composition point. Before
  # the consolidation `HealthChecker.check/1` emitted both halves itself; the
  # split moved the structural codes to `StructuralAnalysis` without changing the
  # set, so these assertions stay meaningful exactly as written.
  defp finding_codes(flow_data, severity) do
    flow_data
    |> composed_findings()
    |> Enum.filter(&(&1.severity == severity))
    |> MapSet.new(& &1.code)
  end

  defp response(id, text) do
    %{
      "id" => id,
      "text" => text,
      "condition" => nil,
      "instruction_assignments" => []
    }
  end
end

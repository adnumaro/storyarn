defmodule Storyarn.Flows.DashboardHealthCoverageTest do
  @moduledoc """
  The flows equivalent of
  `test/storyarn/sheets/dashboard_health_coverage_test.exs:218` and
  `test/storyarn/scenes/dashboard_health_coverage_test.exs:52-59`: every code the
  checker DECLARES must be reachable from the project-wide sweep. What flows has
  instead (`health_consolidation_test.exs:207-213`) compares the editor's code set
  to the dashboard's on one fixture — it passes when a code reaches NEITHER.

  Coverage is asserted by CONSTRUCTING all 27, not by reading the source.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HealthChecker
  alias Storyarn.Flows.VariableReference

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, world: build_world(project)}
  end

  test "the dashboard sweep emits every code the checker can emit", %{project: project} do
    emitted =
      project.id
      |> Flows.list_dashboard_health_findings()
      |> MapSet.new(& &1.code)

    declared = MapSet.new(HealthChecker.codes())
    unreachable = declared |> MapSet.difference(emitted) |> MapSet.to_list() |> Enum.sort()

    # No exclusion list: every one of the 27 is reachable from a project-wide
    # sweep. A code that stopped being reachable is a problem users would only
    # ever see after opening the one flow that has it — add the state that
    # triggers it, do not shrink the assertion.
    assert unreachable == [],
           "the dashboard cannot emit #{inspect(unreachable)}, so those problems are only ever " <>
             "visible after opening the one flow that has them"

    assert emitted == declared
  end

  # `entity_type` used to come from a linear scan over every node, with a `"node"`
  # default. It now reads the node it already holds — so this pins that every
  # node-level finding still names the node's OWN type and never a constant.
  test "every node-level finding carries the node's own type", %{project: project} do
    nodes_by_id =
      project.id
      |> Flows.list_flows()
      |> Enum.flat_map(&Flows.list_nodes(&1.id))
      |> Map.new(&{&1.id, &1})

    node_findings =
      project.id
      |> Flows.list_dashboard_health_findings()
      |> Enum.reject(&is_nil(&1.entity_id))

    # Positive control: the world really does span more than one node type, so a
    # constant could not satisfy this by accident.
    types = node_findings |> Enum.map(& &1.entity_type) |> Enum.uniq()
    assert length(types) > 3, "expected node-level findings on several node types, got #{inspect(types)}"

    for finding <- node_findings do
      node = Map.fetch!(nodes_by_id, finding.entity_id)

      assert finding.entity_type == node.type,
             "#{finding.code} on node #{node.id} reported entity_type " <>
               "#{inspect(finding.entity_type)} but the node is a #{inspect(node.type)}"
    end
  end

  test "the editor emits the same code set as the dashboard, flow by flow", %{
    project: project,
    world: world
  } do
    dashboard = Flows.list_dashboard_health_findings(project.id)

    for {_name, flow} <- Map.delete(world, :speaker) do
      editor = flow |> editor_findings(project.id) |> comparable()

      surface =
        dashboard
        |> Enum.filter(&(&1.flow_id == flow.id))
        |> comparable()

      assert editor != [], "a vacuous comparison proves nothing: #{flow.name} must have findings"
      assert editor == surface, "editor and dashboard disagree about #{flow.name}"
    end
  end

  # ===========================================================================
  # Surface adapters
  # ===========================================================================

  # `Flows.get_flow/2` is what `FlowLive.Show` mounts with, and unlike
  # `Repo.preload([:nodes, :connections])` it filters soft-deleted nodes. Using
  # the preload shortcut here would make the "editor" side of this comparison a
  # graph the editor never sees.
  defp editor_findings(flow, project_id) do
    project_id
    |> Flows.get_flow(flow.id)
    |> Flows.serialize_for_canvas()
    |> Flows.flow_health_findings(project_id)
  end

  defp comparable(findings) do
    findings
    |> Enum.map(&{&1.severity, &1.code, &1.entity_type, &1.entity_id})
    |> Enum.sort()
  end

  # ===========================================================================
  # The world: one flow per code family
  # ===========================================================================

  defp build_world(project) do
    speaker = sheet_fixture(project, %{name: "Narrator"})

    %{
      speaker: speaker,
      structure: build_structure_flow(project, speaker),
      references: build_reference_flow(project),
      editorial: build_editorial_flow(project, speaker),
      pins: build_pin_flow(project, speaker),
      entryless: build_entryless_flow(project),
      twin_entries: build_twin_entry_flow(project)
    }
  end

  # --- missing_entry ---------------------------------------------------------
  defp build_entryless_flow(project) do
    flow = flow_fixture(project, %{name: "No Entry"})
    flow |> entry_node() |> soft_delete!()
    flow
  end

  # --- multiple_entries ------------------------------------------------------
  # `create_node/2` returns `{:error, :entry_node_exists}`, so the second Entry
  # is written raw: this rule exists for imported/legacy graphs.
  defp build_twin_entry_flow(project) do
    flow = flow_fixture(project, %{name: "Two Entries"})
    connection_fixture(flow, entry_node(flow), exit_node(flow))
    force_node!(flow, %{type: "entry", data: %{}, position_x: 0.0, position_y: 0.0})
    flow
  end

  # --- isolated_node, unreachable_node, no_outgoing_connection,
  #     missing_output_connections, orphan_hub -------------------------------
  defp build_structure_flow(project, speaker) do
    flow = flow_fixture(project, %{name: "Structure"})
    entry = entry_node(flow)
    exit_n = exit_node(flow)

    # isolated: no edges at all.
    node_fixture(flow, %{type: "dialogue", data: dialogue_data(speaker)})

    # unreachable: has an incoming edge, but not from Entry.
    unreachable_source = node_fixture(flow, %{type: "instruction", data: %{"assignments" => []}})
    unreachable = node_fixture(flow, %{type: "dialogue", data: dialogue_data(speaker)})
    connection_fixture(flow, unreachable_source, unreachable)
    connection_fixture(flow, unreachable, exit_n)

    # no_outgoing_connection: reachable, nothing leaves it.
    dead_end = node_fixture(flow, %{type: "dialogue", data: dialogue_data(speaker)})
    connection_fixture(flow, entry, dead_end)

    # missing_output_connections: only the true branch is wired.
    condition =
      node_fixture(flow, %{
        type: "condition",
        data: %{"condition" => complete_condition(), "switch_mode" => false}
      })

    connection_fixture(flow, entry, condition)
    connection_fixture(flow, condition, exit_n, %{source_pin: "true"})

    # orphan_hub: no incoming edge and no jump aimed at it.
    hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "lost", "color" => "violet"}})
    connection_fixture(flow, hub, exit_n)

    flow
  end

  # --- the six reference-integrity errors ------------------------------------
  # The productive writer refuses a reference to a deleted flow, so the "stale"
  # half is built live and then broken at the Repo level — the same technique
  # `structural_analysis_test.exs` already uses, and the only way this state
  # actually occurs (imports, trash-ref drift).
  defp build_reference_flow(project) do
    flow = flow_fixture(project, %{name: "References"})
    entry = entry_node(flow)
    target = flow_fixture(project, %{name: "Live Target"})
    hub = node_fixture(flow, %{type: "hub", data: %{"hub_id" => "camp", "color" => "violet"}})

    missing_subflow = node_fixture(flow, %{type: "subflow", data: %{}})
    stale_subflow = node_fixture(flow, %{type: "subflow", data: %{"referenced_flow_id" => target.id}})

    missing_jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})
    stale_jump = node_fixture(flow, %{type: "jump", data: %{"target_hub_id" => "camp"}})

    missing_exit = node_fixture(flow, %{type: "exit", data: %{}})
    stale_exit = node_fixture(flow, %{type: "exit", data: %{}})

    for node <- [missing_subflow, stale_subflow, missing_jump, stale_jump, missing_exit, stale_exit] do
      connection_fixture(flow, entry, node)
    end

    connection_fixture(flow, entry, hub)

    force_data!(missing_jump, %{"target_hub_id" => ""})
    force_data!(missing_exit, %{"exit_mode" => "flow_reference", "referenced_flow_id" => nil})
    force_data!(stale_exit, %{"exit_mode" => "flow_reference", "referenced_flow_id" => target.id})

    # Break the two live targets behind the writers' back.
    soft_delete!(hub)

    project.id
    |> Flows.get_flow!(target.id)
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update!()

    flow
  end

  # --- invalid_output_pins, invalid_input_pins -------------------------------
  defp build_pin_flow(project, speaker) do
    flow = flow_fixture(project, %{name: "Pins"})
    entry = entry_node(flow)
    exit_n = exit_node(flow)

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Choose", "speaker_sheet_id" => speaker.id, "responses" => [response("r1", "Yes")]}
      })

    connection_fixture(flow, entry, dialogue)
    connection_fixture(flow, dialogue, exit_n, %{source_pin: "r1"})
    # The response disappears; the persisted edge keeps its pin.
    force_data!(dialogue, %{"text" => "Choose", "speaker_sheet_id" => speaker.id, "responses" => []})

    # The productive writer refuses a bad target pin, so drift is written raw.
    Repo.insert!(%FlowConnection{
      flow_id: flow.id,
      source_node_id: entry.id,
      target_node_id: exit_n.id,
      source_pin: "output",
      target_pin: "legacy-input"
    })

    flow
  end

  # --- the twelve editorial codes --------------------------------------------
  defp build_editorial_flow(project, speaker) do
    sheet = sheet_fixture(project, %{name: "Hero"})
    number = block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
    text = block_fixture(sheet, %{type: "text", config: %{"label" => "Title"}})

    flow = flow_fixture(project, %{name: "Editorial"})
    entry = entry_node(flow)

    # empty_instruction (info)
    node_fixture(flow, %{type: "instruction", data: %{"assignments" => []}})

    # empty_condition (info)
    node_fixture(flow, %{type: "condition", data: %{"condition" => %{"blocks" => []}}})

    # incomplete_condition (warning)
    node_fixture(flow, %{type: "condition", data: %{"condition" => incomplete_condition()}})

    # incomplete_instruction_assignment (warning)
    node_fixture(flow, %{
      type: "instruction",
      data: %{"assignments" => [incomplete_assignment()]}
    })

    # missing_dialogue_speaker + empty_dialogue_response
    # + incomplete_response_condition + incomplete_response_assignment
    node_fixture(flow, %{
      type: "dialogue",
      data: %{
        "text" => "",
        "speaker_sheet_id" => nil,
        "responses" => [
          %{
            "id" => "r1",
            "text" => "",
            "condition" => incomplete_condition(),
            "instruction_assignments" => [incomplete_assignment()]
          }
        ]
      }
    })

    # missing_dialogue_text needs its own node: a dialogue that presents
    # responses is a choice menu and needs no line of its own, so only one with
    # neither text nor responses is incomplete.
    node_fixture(flow, %{
      type: "dialogue",
      data: %{
        "text" => "",
        "speaker_sheet_id" => sheet.id,
        "responses" => []
      }
    })

    # variable_type_mismatch: a numeric operator aimed at a text variable.
    node_fixture(flow, %{
      type: "instruction",
      data: %{
        "assignments" => [
          %{
            "id" => "a1",
            "sheet" => sheet.shortcut,
            "variable" => text.variable_name,
            "operator" => "add",
            "value" => "1",
            "value_type" => "literal"
          }
        ]
      }
    })

    # response_type_mismatch: the same, inside a dialogue response.
    node_fixture(flow, %{
      type: "dialogue",
      data: %{
        "text" => "Pick",
        "speaker_sheet_id" => speaker.id,
        "responses" => [
          %{
            "id" => "r1",
            "text" => "Take it",
            "instruction_assignments" => [
              %{
                "id" => "a1",
                "sheet" => sheet.shortcut,
                "variable" => text.variable_name,
                "operator" => "add",
                "value" => "1",
                "value_type" => "literal"
              }
            ]
          }
        ]
      }
    })

    # stale_variable_reference: a tracked reference whose block was renamed
    # behind its back, which is what `list_stale_node_ids_by_flow/1` looks for.
    stale_node =
      node_fixture(flow, %{
        type: "condition",
        data: %{"condition" => complete_condition(sheet.shortcut, number.variable_name)}
      })

    connection_fixture(flow, entry, stale_node)

    Repo.insert!(%VariableReference{
      source_type: "flow_node",
      source_id: stale_node.id,
      flow_node_id: stale_node.id,
      block_id: number.id,
      kind: "read",
      source_sheet: sheet.shortcut,
      source_variable: "renamed_away",
      inserted_at: DateTime.utc_now(:second),
      updated_at: DateTime.utc_now(:second)
    })

    flow
  end

  # ===========================================================================
  # Primitives
  # ===========================================================================

  defp entry_node(flow), do: flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
  defp exit_node(flow), do: flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))

  defp force_node!(flow, attrs) do
    %FlowNode{flow_id: flow.id} |> Ecto.Changeset.change(attrs) |> Repo.insert!()
  end

  defp soft_delete!(node) do
    node |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
  end

  defp force_data!(node, data), do: node |> Ecto.Changeset.change(data: data) |> Repo.update!()

  defp dialogue_data(speaker), do: %{"text" => "Hello", "speaker_sheet_id" => speaker.id, "responses" => []}

  defp response(id, text), do: %{"id" => id, "text" => text}

  defp complete_condition(sheet \\ "hero", variable \\ "health") do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "b1",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{"id" => "r1", "sheet" => sheet, "variable" => variable, "operator" => "greater_than", "value" => "0"}
          ]
        }
      ]
    }
  end

  defp incomplete_condition do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "b1",
          "type" => "block",
          "logic" => "all",
          "rules" => [%{"id" => "r1", "sheet" => "hero", "variable" => nil, "operator" => "equals", "value" => "x"}]
        }
      ]
    }
  end

  defp incomplete_assignment do
    %{"id" => "a1", "sheet" => "hero", "variable" => nil, "operator" => "set", "value" => "x"}
  end
end

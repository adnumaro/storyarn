defmodule Storyarn.Projects.Exports.ValidatorHealthBoundaryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Exports.ExportOptions
  alias Storyarn.Projects.Exports.Validator
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Repo

  setup do
    %{project: project_fixture(user_fixture())}
  end

  test "artifact loss is reported without leaking authoring-only structural rules", %{
    project: project
  } do
    flow = flow_fixture(project, %{name: "Authoring Health"})
    speaker = sheet_fixture(project, %{name: "Speaker"})

    node_fixture(flow, %{
      type: "dialogue",
      data: %{"text" => "Disconnected", "speaker_sheet_id" => speaker.id}
    })

    health_codes =
      project.id
      |> Flows.list_dashboard_health_findings()
      |> MapSet.new(& &1.code)

    assert :isolated_node in health_codes

    result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
    export_rules = MapSet.new(result.errors ++ result.warnings ++ result.info, & &1.rule)

    assert :unreachable_node in export_rules
    refute :orphan_nodes in export_rules
    refute :unreachable_nodes in export_rules
    refute :isolated_node in export_rules
  end

  test "missing entry remains a blocking artifact finding", %{project: project} do
    flow = flow_fixture(project, %{name: "No Entry"})

    flow.id
    |> Flows.list_nodes()
    |> Enum.filter(&(&1.type == "entry"))
    |> Enum.each(&Repo.delete!/1)

    result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

    assert result.status == :errors
    assert Enum.any?(result.errors, &(&1.rule == :missing_entry and &1.flow_id == flow.id))
  end

  test "multiple entries remain a blocking artifact finding", %{project: project} do
    flow = flow_fixture(project, %{name: "Two Entries"})

    Repo.insert!(%FlowNode{
      flow_id: flow.id,
      type: "entry",
      data: %{},
      position_x: 300.0,
      position_y: 100.0
    })

    result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

    assert result.status == :errors

    assert Enum.any?(
             result.errors,
             &(&1.rule == :multiple_entries and &1.flow_id == flow.id and &1.count == 2)
           )
  end

  test "connections from non-exportable output pins remain blocking", %{project: project} do
    flow = flow_fixture(project, %{name: "Stale Output"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Choose",
          "localization_id" => "dialogue_stale_output",
          "responses" => [%{"id" => "response_valid", "text" => "Continue"}]
        }
      })

    exit_node = node_fixture(flow, %{type: "exit", data: %{}})

    Repo.insert!(%FlowConnection{
      flow_id: flow.id,
      source_node_id: dialogue.id,
      target_node_id: exit_node.id,
      source_pin: "removed_response",
      target_pin: "input"
    })

    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    connection_fixture(flow, entry, dialogue)

    result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

    assert result.status == :errors

    assert Enum.any?(
             result.errors,
             &(&1.rule == :invalid_output_pins and &1.entity_id == dialogue.id)
           )
  end

  test "unreachable nodes do not block or inflate editorial summaries", %{project: project} do
    flow = flow_fixture(project, %{name: "Discarded Branch"})

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "",
          "speaker_sheet_id" => nil,
          "localization_id" => "discarded_dialogue",
          "responses" => [%{"id" => "response_valid", "text" => "Continue"}]
        }
      })

    exit_node = node_fixture(flow, %{type: "exit", data: %{}})

    Repo.insert!(%FlowConnection{
      flow_id: flow.id,
      source_node_id: dialogue.id,
      target_node_id: exit_node.id,
      source_pin: "removed_response",
      target_pin: "input"
    })

    dashboard = Flows.list_dashboard_health_findings(project.id)
    assert Enum.any?(dashboard, &(&1.code == :invalid_output_pins and &1.entity_id == dialogue.id))

    # The editorial sample is the missing speaker: this dialogue presents a
    # response, so it is a choice menu and its empty text is not a finding. The
    # pairing with the `missing_speakers` refute below is the actual boundary —
    # the dashboard reports it, the export does not.
    assert Enum.any?(dashboard, &(&1.code == :missing_dialogue_speaker and &1.entity_id == dialogue.id))

    result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

    assert Enum.any?(result.warnings, &(&1.rule == :unreachable_node and &1.entity_id == dialogue.id))
    refute Enum.any?(result.errors, &(&1.rule == :invalid_output_pins))
    refute Enum.any?(result.warnings, &(&1.rule == :empty_dialogue))
    refute Enum.any?(result.warnings, &(&1.rule == :missing_speakers))
  end

  test "editorial summaries use canonical health and respect partial selection", %{project: project} do
    selected = flow_fixture(project, %{name: "Selected"})
    excluded = flow_fixture(project, %{name: "Excluded"})

    selected_dialogues =
      for flow <- [selected, selected] do
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "speaker_sheet_id" => nil}
        })
      end

    node_fixture(excluded, %{
      type: "dialogue",
      data: %{"text" => "", "speaker_sheet_id" => nil}
    })

    entry = selected.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    [first, second] = selected_dialogues
    connection_fixture(selected, entry, first)
    connection_fixture(selected, first, second)

    dashboard = Flows.list_dashboard_health_findings(project.id)
    assert Enum.count(dashboard, &(&1.code == :missing_dialogue_text)) == 3
    assert Enum.count(dashboard, &(&1.code == :missing_dialogue_speaker)) == 3

    result =
      Validator.validate_project(project.id, %ExportOptions{
        format: :ink,
        flow_ids: [selected.id]
      })

    empty_dialogue = Enum.find(result.warnings, &(&1.rule == :empty_dialogue))
    missing_speakers = Enum.find(result.warnings, &(&1.rule == :missing_speakers))

    assert Enum.count(result.warnings, &(&1.rule == :empty_dialogue)) == 1
    assert Enum.count(result.warnings, &(&1.rule == :missing_speakers)) == 1
    assert empty_dialogue.count == 2
    assert empty_dialogue.dashboard == :flows
    assert missing_speakers.count == 2
    assert missing_speakers.dashboard == :flows
    refute Map.has_key?(empty_dialogue, :node_id)
    refute Map.has_key?(missing_speakers, :node_id)
  end

  test "omitting flows also omits flow-health summaries", %{project: project} do
    flow = flow_fixture(project, %{name: "Not Exported"})

    node_fixture(flow, %{
      type: "dialogue",
      data: %{"text" => "", "speaker_sheet_id" => nil}
    })

    result =
      Validator.validate_project(project.id, %ExportOptions{
        format: :ink,
        include_flows: false
      })

    refute Enum.any?(result.warnings, &(&1.rule == :empty_dialogue))
    refute Enum.any?(result.warnings, &(&1.rule == :missing_speakers))
  end
end

defmodule Storyarn.Exports.ValidatorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Exports.Validator
  alias Storyarn.Exports.Validator.ValidationResult

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  import Storyarn.SheetsFixtures

  # =============================================================================
  # Setup
  # =============================================================================

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # Clean project
  # =============================================================================

  describe "clean project" do
    setup [:setup_project]

    test "passes validation for empty project", %{project: project} do
      result = Validator.validate_project(project.id)
      assert %ValidationResult{status: :passed} = result
      assert result.errors == []
      assert result.warnings == []
    end

    test "passes validation for well-formed project", %{project: project} do
      # Create a complete, valid flow
      flow = flow_fixture(project, %{name: "Clean Flow"})
      # Flow auto-creates entry node
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello!", "speaker_sheet_id" => "some_speaker"}
        })

      exit_node = node_fixture(flow, %{type: "exit", data: %{}})

      # Get the auto-created entry
      entry = Storyarn.Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))

      # Connect: entry → dialogue → exit
      Storyarn.FlowsFixtures.connection_fixture(flow, entry, dialogue)
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      result = Validator.validate_project(project.id)
      assert result.status in [:passed, :warnings]
      assert result.errors == []
    end
  end

  # =============================================================================
  # missing_entry (error)
  # =============================================================================

  describe "missing_entry" do
    setup [:setup_project]

    test "reports error when flow has no entry node", %{project: project} do
      # Create flow, then delete its auto-created entry node
      flow = flow_fixture(project, %{name: "Broken Flow"})
      entry = Storyarn.Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      # Hard-delete the entry node to simulate a broken state
      Storyarn.Repo.delete!(entry)

      result = Validator.validate_project(project.id)
      assert result.status == :errors

      entry_error = Enum.find(result.errors, &(&1.rule == :missing_entry))
      assert entry_error != nil
      assert entry_error.flow_name == "Broken Flow"
    end
  end

  # =============================================================================
  # orphan_nodes (warning)
  # =============================================================================

  describe "orphan_nodes" do
    setup [:setup_project]

    test "reports warning for nodes with no connections", %{project: project} do
      flow = flow_fixture(project, %{name: "Orphan Flow"})
      # Create a dialogue node that's not connected to anything
      _orphan =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Orphan node"}
        })

      result = Validator.validate_project(project.id)
      orphan_warnings = Enum.filter(result.warnings, &(&1.rule == :orphan_nodes))
      assert length(orphan_warnings) == 1
      assert hd(orphan_warnings).node_type == "dialogue"
    end
  end

  # =============================================================================
  # unreachable_nodes (warning)
  # =============================================================================

  describe "unreachable_nodes" do
    setup [:setup_project]

    test "reports warning for nodes not reachable from entry", %{project: project} do
      flow = flow_fixture(project, %{name: "Unreachable Flow"})

      # Create two dialogue nodes and connect them to each other
      # but NOT connected to the entry node
      d1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Island 1"}})
      d2 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Island 2"}})
      Storyarn.FlowsFixtures.connection_fixture(flow, d1, d2)

      result = Validator.validate_project(project.id)
      unreachable = Enum.filter(result.warnings, &(&1.rule == :unreachable_nodes))
      # d1 and d2 should be unreachable (not connected from entry)
      unreachable_dialogue = Enum.filter(unreachable, &(&1.node_type == "dialogue"))
      assert length(unreachable_dialogue) == 2
    end
  end

  # =============================================================================
  # empty_dialogue (warning)
  # =============================================================================

  describe "empty_dialogue" do
    setup [:setup_project]

    test "reports warning for dialogue nodes with empty text", %{project: project} do
      flow = flow_fixture(project, %{name: "Empty Dialogue Flow"})

      _empty =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "speaker_sheet_id" => "npc"}
        })

      result = Validator.validate_project(project.id)
      empty_warnings = Enum.filter(result.warnings, &(&1.rule == :empty_dialogue))
      assert length(empty_warnings) == 1
    end

    test "reports warning for dialogue nodes with only HTML tags", %{project: project} do
      flow = flow_fixture(project, %{name: "HTML Only Flow"})

      _html =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p><br></p>", "speaker_sheet_id" => "npc"}
        })

      result = Validator.validate_project(project.id)
      empty_warnings = Enum.filter(result.warnings, &(&1.rule == :empty_dialogue))
      assert length(empty_warnings) == 1
    end
  end

  # =============================================================================
  # missing_speakers (warning)
  # =============================================================================

  describe "missing_speakers" do
    setup [:setup_project]

    test "reports warning for dialogue nodes without speaker", %{project: project} do
      flow = flow_fixture(project, %{name: "No Speaker Flow"})

      _nospeaker =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Who says this?"}
        })

      result = Validator.validate_project(project.id)
      speaker_warnings = Enum.filter(result.warnings, &(&1.rule == :missing_speakers))
      assert length(speaker_warnings) == 1
    end
  end

  # =============================================================================
  # broken_references (error) — jump to non-existent hub
  # =============================================================================

  describe "broken_references" do
    setup [:setup_project]

    test "reports error for jump node targeting non-existent hub", %{project: project} do
      flow = flow_fixture(project, %{name: "Broken Jump Flow"})

      _jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "nonexistent_hub"}
        })

      result = Validator.validate_project(project.id)
      broken = Enum.filter(result.errors, &(&1.rule == :broken_references))
      assert length(broken) == 1
      assert hd(broken).ref_type == :hub
    end

    test "no error when jump targets existing hub", %{project: project} do
      flow = flow_fixture(project, %{name: "Valid Jump Flow"})

      _hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "hub_1", "label" => "Main Hub"}
        })

      _jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "hub_1"}
        })

      result = Validator.validate_project(project.id)

      broken_hub =
        Enum.filter(result.errors, &(&1.rule == :broken_references && &1[:ref_type] == :hub))

      assert broken_hub == []
    end

    test "reports error for subflow targeting non-existent flow", %{project: project} do
      flow = flow_fixture(project, %{name: "Broken Subflow"})

      _subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"target_flow_id" => -999}
        })

      result = Validator.validate_project(project.id)

      broken =
        Enum.filter(result.errors, &(&1.rule == :broken_references && &1[:ref_type] == :flow))

      assert length(broken) == 1
    end

    test "reports error for scene node targeting non-existent scene", %{project: project} do
      flow = flow_fixture(project, %{name: "Broken Scene Flow"})

      _scene_node =
        node_fixture(flow, %{
          type: "scene",
          data: %{"scene_id" => -999}
        })

      result = Validator.validate_project(project.id)

      broken =
        Enum.filter(result.errors, &(&1.rule == :broken_references && &1[:ref_type] == :scene))

      assert length(broken) == 1
    end
  end

  # =============================================================================
  # missing_translations (warning)
  # =============================================================================

  describe "missing_translations" do
    setup [:setup_project]

    test "reports warning when translations are pending", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = flow_fixture(project, %{name: "Translated Flow"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello!"}
        })

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello!",
          locale_code: "es",
          translated_text: nil,
          status: "pending"
        })

      result = Validator.validate_project(project.id)
      translation_warnings = Enum.filter(result.warnings, &(&1.rule == :missing_translations))
      assert length(translation_warnings) == 1
      assert hd(translation_warnings).locale == "es"
    end

    test "no warning when all translations are final", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      flow = flow_fixture(project, %{name: "Fully Translated"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello!"}
        })

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: dialogue.id,
          source_field: "text",
          source_text: "Hello!",
          locale_code: "es",
          translated_text: "Hola!",
          status: "final"
        })

      result = Validator.validate_project(project.id)
      translation_warnings = Enum.filter(result.warnings, &(&1.rule == :missing_translations))
      assert translation_warnings == []
    end
  end

  # =============================================================================
  # circular_subflows (warning)
  # =============================================================================

  describe "circular_subflows" do
    setup [:setup_project]

    test "reports warning for circular subflow references", %{project: project} do
      flow_a = flow_fixture(project, %{name: "Flow A"})
      flow_b = flow_fixture(project, %{name: "Flow B"})

      # A references B via subflow
      _subflow_a =
        node_fixture(flow_a, %{
          type: "subflow",
          data: %{"target_flow_id" => flow_b.id}
        })

      # B references A (circular)
      _subflow_b =
        node_fixture(flow_b, %{
          type: "subflow",
          data: %{"target_flow_id" => flow_a.id}
        })

      result = Validator.validate_project(project.id)
      circular = Enum.filter(result.warnings, &(&1.rule == :circular_subflows))
      assert length(circular) == 2

      flow_ids = Enum.map(circular, & &1.flow_id) |> MapSet.new()
      assert MapSet.member?(flow_ids, flow_a.id)
      assert MapSet.member?(flow_ids, flow_b.id)
    end

    test "no warning for non-circular subflow references", %{project: project} do
      flow_a = flow_fixture(project, %{name: "Flow A"})
      flow_b = flow_fixture(project, %{name: "Flow B"})

      # A references B (one-way, no cycle)
      _subflow =
        node_fixture(flow_a, %{
          type: "subflow",
          data: %{"target_flow_id" => flow_b.id}
        })

      result = Validator.validate_project(project.id)
      circular = Enum.filter(result.warnings, &(&1.rule == :circular_subflows))
      assert circular == []
    end
  end

  # =============================================================================
  # orphan_sheets (info)
  # =============================================================================

  describe "orphan_sheets" do
    setup [:setup_project]

    test "reports info for sheets with no references", %{project: project} do
      _sheet = sheet_fixture(project, %{name: "Unused Sheet"})

      result = Validator.validate_project(project.id)
      orphans = Enum.filter(result.info, &(&1.rule == :orphan_sheets))
      assert length(orphans) == 1
      assert hd(orphans).sheet_name == "Unused Sheet"
    end
  end

  # =============================================================================
  # ValidationResult structure
  # =============================================================================

  describe "result structure" do
    setup [:setup_project]

    test "includes statistics", %{project: project} do
      result = Validator.validate_project(project.id)
      assert result.statistics.project_id == project.id
      assert is_integer(result.statistics.total_findings)
      assert is_integer(result.statistics.error_count)
      assert is_integer(result.statistics.warning_count)
      assert is_integer(result.statistics.info_count)
    end

    test "status is :errors when errors exist", %{project: project} do
      flow = flow_fixture(project, %{name: "Error Flow"})
      entry = Storyarn.Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      Storyarn.Repo.delete!(entry)

      result = Validator.validate_project(project.id)
      assert result.status == :errors
    end

    test "accepts ExportOptions", %{project: project} do
      {:ok, opts} = Storyarn.Exports.ExportOptions.new(%{format: :storyarn})
      result = Validator.validate_project(project.id, opts)
      assert %ValidationResult{} = result
    end

    test "export fails when validation detects errors", %{project: project} do
      # Create a flow with a broken state (no entry node)
      flow = flow_fixture(project, %{name: "Broken Flow"})
      entry = Storyarn.Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      Storyarn.Repo.delete!(entry)

      # Export with validation enabled (default) should fail
      result = Storyarn.Exports.export_project(project, %{format: :storyarn})
      assert {:error, {:validation_failed, %ValidationResult{status: :errors}}} = result
    end

    test "export succeeds when validation is disabled", %{project: project} do
      # Create a flow with a broken state
      flow = flow_fixture(project, %{name: "Broken Flow"})
      entry = Storyarn.Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      Storyarn.Repo.delete!(entry)

      # Export with validation disabled should succeed
      result =
        Storyarn.Exports.export_project(project, %{
          format: :storyarn,
          validate_before_export: false
        })

      assert {:ok, _json} = result
    end
  end
end

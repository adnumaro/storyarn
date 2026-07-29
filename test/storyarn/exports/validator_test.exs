defmodule Storyarn.Exports.ValidatorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.Validator
  alias Storyarn.Exports.Validator.ValidationResult
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

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
      result = Validator.validate_project(project.id, %ExportOptions{format: :unity})
      assert %ValidationResult{status: :passed} = result
      assert result.errors == []
      assert result.warnings == []
    end

    test "passes validation for well-formed project", %{project: project} do
      # Create a complete, valid flow
      flow = flow_fixture(project, %{name: "Clean Flow"})
      speaker = sheet_fixture(project, %{name: "Speaker"})
      # Flow auto-creates entry node
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello!", "speaker_sheet_id" => speaker.id}
        })

      exit_node = node_fixture(flow, %{type: "exit", data: %{}})

      # Get the auto-created entry
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))

      # Connect: entry → dialogue → exit
      Storyarn.FlowsFixtures.connection_fixture(flow, entry, dialogue)
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, exit_node)

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      assert result.errors == [], inspect(result.errors)
      assert result.status in [:passed, :warnings]
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
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      # Hard-delete the entry node to simulate a broken state
      Repo.delete!(entry)

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      assert result.status == :errors

      entry_error = Enum.find(result.errors, &(&1.rule == :missing_entry))
      assert entry_error
      assert entry_error.flow_name == "Broken Flow"
    end
  end

  # =============================================================================
  # empty_dialogue (warning)
  # =============================================================================

  describe "empty_dialogue" do
    setup [:setup_project]

    test "reports warning for dialogue nodes with empty text", %{project: project} do
      flow = flow_fixture(project, %{name: "Empty Dialogue Flow"})
      speaker = sheet_fixture(project, %{name: "NPC"})

      _empty =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "", "speaker_sheet_id" => speaker.id}
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      empty_warnings = Enum.filter(result.warnings, &(&1.rule == :empty_dialogue))
      assert length(empty_warnings) == 1
    end

    test "reports warning for dialogue nodes with only HTML tags", %{project: project} do
      flow = flow_fixture(project, %{name: "HTML Only Flow"})
      speaker = sheet_fixture(project, %{name: "NPC"})

      _html =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "<p><br></p>", "speaker_sheet_id" => speaker.id}
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
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

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      speaker_warnings = Enum.filter(result.warnings, &(&1.rule == :missing_speakers))
      assert length(speaker_warnings) == 1
    end
  end

  # =============================================================================
  # Artifact control references
  # =============================================================================

  describe "artifact control references" do
    setup [:setup_project]

    test "reports error for jump node targeting non-existent hub", %{project: project} do
      flow = flow_fixture(project, %{name: "Broken Jump Flow"})

      _jump =
        corrupt_node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "nonexistent_hub"}
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      broken = Enum.filter(result.errors, &(&1.rule == :stale_jump_target))
      assert length(broken) == 1
      assert hd(broken).node_id
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

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      broken_hub =
        Enum.filter(result.errors, &(&1.rule == :stale_jump_target))

      assert broken_hub == []
    end

    test "reports error for subflow targeting non-existent flow", %{project: project} do
      flow = flow_fixture(project, %{name: "Broken Subflow"})

      _subflow =
        corrupt_node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => -999}
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      broken = Enum.filter(result.errors, &(&1.rule == :stale_subflow_reference))

      assert length(broken) == 1
    end

    test "partial exports accept references to active flows outside the selection", %{project: project} do
      included = flow_fixture(project, %{name: "Included"})
      excluded = flow_fixture(project, %{name: "Excluded"})

      node_fixture(included, %{
        type: "subflow",
        data: %{"referenced_flow_id" => excluded.id}
      })

      result =
        Validator.validate_project(project.id, %ExportOptions{
          format: :ink,
          flow_ids: [included.id]
        })

      refute Enum.any?(result.errors, &(&1.rule == :stale_subflow_reference))
    end
  end

  describe "artifact integrity" do
    setup [:setup_project]

    test "blocks invalid dialogue and response runtime IDs", %{project: project} do
      flow = flow_fixture(project, %{name: "Runtime IDs"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [%{"id" => "valid_response", "text" => "Continue"}]
          }
        })

      corrupt_data =
        dialogue.data
        |> Map.put("localization_id", nil)
        |> Map.put("responses", [%{"text" => "Missing ID"}])

      dialogue |> Ecto.Changeset.change(data: corrupt_data) |> Repo.update!()

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      assert Enum.any?(result.errors, &(&1.rule == :invalid_dialogue_runtime_id))
      assert Enum.any?(result.errors, &(&1.rule == :invalid_response_runtime_id))
    end

    test "blocks missing flow and sheet shortcuts", %{project: project} do
      flow = flow_fixture(project, %{name: "Legacy Flow"})
      sheet = sheet_fixture(project, %{name: "Legacy Sheet"})

      flow |> Ecto.Changeset.change(shortcut: nil) |> Repo.update!()
      sheet |> Ecto.Changeset.change(shortcut: nil) |> Repo.update!()

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      assert Enum.any?(result.errors, &(&1.rule == :invalid_flow_identifier))
      assert Enum.any?(result.errors, &(&1.rule == :invalid_sheet_identifier))
    end

    test "uses direct artifact data and format-aware severity for stale variable references", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Stale References"})

      node_fixture(flow, %{
        type: "condition",
        data: %{"condition" => condition("missing_sheet", "missing_variable", "equals")}
      })

      ink = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      unity = Validator.validate_project(project.id, %ExportOptions{format: :unity})

      assert Enum.any?(ink.errors, &(&1.rule == :stale_variable_reference))
      assert Enum.any?(unity.warnings, &(&1.rule == :stale_variable_reference))
      refute Enum.any?(unity.errors, &(&1.rule == :stale_variable_reference))
    end

    test "surfaces target-transpiler warnings", %{project: project} do
      flow = flow_fixture(project, %{name: "Expressions"})

      node_fixture(flow, %{
        type: "condition",
        data: %{"condition" => condition("inventory", "items", "contains")}
      })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      warning = Enum.find(result.warnings, &(&1.rule == :unsupported_operator))
      assert warning
      assert warning.format == :ink
      assert warning.message =~ "contains"
    end

    test "blocks corrupt conditions that would become an always-true branch", %{project: project} do
      flow = flow_fixture(project, %{name: "Corrupt Condition"})

      node_fixture(flow, %{
        type: "condition",
        data: %{"condition" => "{not-json"}
      })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})

      assert Enum.any?(result.errors, &(&1.rule == :invalid_export_expression))
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

      result = Validator.validate_project(project.id, %ExportOptions{format: :unity})
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

      result = Validator.validate_project(project.id, %ExportOptions{format: :unity})
      translation_warnings = Enum.filter(result.warnings, &(&1.rule == :missing_translations))
      assert translation_warnings == []
    end

    test "checks only localization sources selected for the engine export", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      included_flow = flow_fixture(project, %{name: "Included"})
      excluded_flow = flow_fixture(project, %{name: "Excluded"})
      node_fixture(included_flow, %{type: "dialogue", data: %{"text" => "Included pending"}})
      node_fixture(excluded_flow, %{type: "dialogue", data: %{"text" => "Excluded pending"}})

      result =
        Validator.validate_project(project.id, %ExportOptions{
          format: :yarn,
          flow_ids: [included_flow.id],
          include_sheets: false
        })

      assert [%{total_count: 1, excluded_count: 1}] =
               Enum.filter(result.warnings, &(&1.rule == :missing_translations))
    end

    # The other half of this test covered the native full-state backup format,
    # which skipped readiness entirely. That format is gone, so every remaining
    # format is an engine format and `include_localization: false` is now the
    # only way readiness is skipped.
    test "does not apply engine readiness when localization is disabled", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Pending"}})

      disabled =
        Validator.validate_project(project.id, %ExportOptions{format: :unity, include_localization: false})

      enabled = Validator.validate_project(project.id, %ExportOptions{format: :unity})

      refute Enum.any?(disabled.warnings, &(&1.rule == :missing_translations))
      # Positive control: the same project DOES report readiness when enabled,
      # so the assertion above cannot pass for the wrong reason.
      assert Enum.any?(enabled.warnings, &(&1.rule == :missing_translations))
    end

    test "checks only target locales selected for export", %{project: project} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Pending"}})

      result =
        Validator.validate_project(project.id, %ExportOptions{
          format: :unity,
          languages: ["es"]
        })

      assert [%{locale: "es"}] = Enum.filter(result.warnings, &(&1.rule == :missing_translations))
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
          data: %{"referenced_flow_id" => flow_b.id}
        })

      # B references A (circular) — insert directly to bypass circular reference check
      {:ok, _subflow_b} =
        Repo.insert(%FlowNode{
          flow_id: flow_b.id,
          type: "subflow",
          data: %{"referenced_flow_id" => flow_a.id},
          position_x: 100.0,
          position_y: 100.0
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      circular = Enum.filter(result.warnings, &(&1.rule == :circular_subflows))
      assert length(circular) == 2

      flow_ids = MapSet.new(circular, & &1.flow_id)
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
          data: %{"referenced_flow_id" => flow_b.id}
        })

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
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

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
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
      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      assert result.statistics.project_id == project.id
      assert is_integer(result.statistics.total_findings)
      assert is_integer(result.statistics.error_count)
      assert is_integer(result.statistics.warning_count)
      assert is_integer(result.statistics.info_count)
    end

    test "status is :errors when errors exist", %{project: project} do
      flow = flow_fixture(project, %{name: "Error Flow"})
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      Repo.delete!(entry)

      result = Validator.validate_project(project.id, %ExportOptions{format: :ink})
      assert result.status == :errors
    end

    test "accepts ExportOptions", %{project: project} do
      {:ok, opts} = ExportOptions.new(%{format: :ink})
      result = Validator.validate_project(project.id, opts)
      assert %ValidationResult{} = result
    end

    test "respects export options when loading flows", %{project: project} do
      flow = flow_fixture(project, %{name: "Excluded Broken Flow"})
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      Repo.delete!(entry)

      result =
        Validator.validate_project(project.id, %ExportOptions{
          format: :ink,
          include_flows: false
        })

      refute Enum.any?(result.errors, &(&1.rule == :missing_entry))
    end

    test "export fails when validation detects errors", %{project: project} do
      # Create a flow with a broken state (no entry node)
      flow = flow_fixture(project, %{name: "Broken Flow"})
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      Repo.delete!(entry)

      # Export with validation enabled (default) should fail
      result = Storyarn.Exports.export_project(project, %{format: :ink})
      assert {:error, {:validation_failed, %ValidationResult{status: :errors}}} = result
    end

    test "export succeeds when validation is disabled", %{project: project} do
      # Create a flow with a broken state
      flow = flow_fixture(project, %{name: "Broken Flow"})
      entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      Repo.delete!(entry)

      # Export with validation disabled should succeed
      result =
        Storyarn.Exports.export_project(project, %{
          format: :ink,
          validate_before_export: false
        })

      assert {:ok, _json} = result
    end
  end

  defp corrupt_node_fixture(flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Repo.insert!()
  end

  defp condition(sheet, variable, operator) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "block_1",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule_1",
              "sheet" => sheet,
              "variable" => variable,
              "operator" => operator,
              "value" => "value"
            }
          ]
        }
      ]
    }
  end
end

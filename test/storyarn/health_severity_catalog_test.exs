defmodule Storyarn.HealthSeverityCatalogTest do
  @moduledoc """
  The frozen severity catalog for all three health domains.

  This replaces the per-rule catalog test the structural-analysis rules module
  carried before the flow/sheet/scene contracts were consolidated. `category`
  and `version` are gone from the contract — sheets and scenes never had them —
  so severity is the only thing left worth freezing, and it is the thing users
  see: severity decides the icon, the sort order and whether a finding reads as
  "broken" or "unfinished".

  It lives in one file, across all three domains, on purpose. Its value is being
  a single deliberate thing you must consciously edit; split across the three
  suites that already hold behavioural assertions, that property is lost.

  Why an exact map equality and not `for {code, sev} <- expected`: a loop catches
  a changed severity and a removed code, but NOT a newly added one — and a new
  rule silently shipping at whatever severity its author happened to type is
  exactly the regression this guards.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Flows.HealthChecker, as: FlowHealth
  alias Storyarn.Scenes.HealthChecker, as: SceneHealth
  alias Storyarn.Sheets.HealthChecker, as: SheetHealth

  describe "flows" do
    test "every flow health code is pinned to a severity" do
      assert_catalog(FlowHealth, %{
        # Structural — detected from the graph.
        invalid_input_pins: :error,
        invalid_output_pins: :error,
        missing_entry: :error,
        missing_exit_flow_reference: :error,
        missing_jump_target: :error,
        missing_subflow_reference: :error,
        multiple_entries: :error,
        stale_exit_flow_reference: :error,
        stale_jump_target: :error,
        stale_subflow_reference: :error,
        isolated_node: :warning,
        missing_output_connections: :warning,
        no_outgoing_connection: :warning,
        orphan_hub: :warning,
        unreachable_node: :warning,
        # Editorial — detected from one node's own data.
        stale_variable_reference: :error,
        empty_dialogue_response: :warning,
        incomplete_condition: :warning,
        incomplete_instruction_assignment: :warning,
        incomplete_response_assignment: :warning,
        incomplete_response_condition: :warning,
        missing_dialogue_speaker: :warning,
        missing_dialogue_text: :warning,
        response_type_mismatch: :warning,
        variable_type_mismatch: :warning,
        empty_condition: :info,
        empty_instruction: :info
      })
    end
  end

  describe "sheets" do
    test "every sheet health code is pinned to a severity" do
      assert_catalog(SheetHealth, %{
        broken_inheritance: :error,
        cyclic_formula_dependency: :error,
        disallowed_reference_target: :error,
        formula_evaluation_failed: :error,
        invalid_block_layout: :error,
        invalid_block_value: :error,
        invalid_constraints: :error,
        invalid_formula_binding: :error,
        invalid_formula_expression: :error,
        invalid_select_option_keys: :error,
        invalid_table_structure: :error,
        missing_sheet_shortcut: :error,
        missing_variable_name: :error,
        stale_incoming_variable_reference: :error,
        stale_inline_reference: :error,
        stale_reference_target: :error,
        stale_selected_option: :error,
        unbound_formula_symbol: :error,
        blank_option_label: :warning,
        empty_select_options: :warning,
        required_block_empty: :warning,
        required_table_cell_empty: :warning,
        unnamed_table_axis: :warning,
        value_outside_constraints: :warning,
        empty_leaf_sheet: :info,
        no_internal_variable_usages: :info
      })
    end
  end

  describe "scenes" do
    test "every scene health code is pinned to a severity" do
      assert_catalog(SceneHealth, %{
        invalid_ambient_trigger: :error,
        invalid_asset_reference: :error,
        invalid_collection_item: :error,
        invalid_condition_structure: :error,
        invalid_connection_endpoint: :error,
        invalid_connection_route: :error,
        invalid_layer_reference: :error,
        invalid_zone_action_configuration: :error,
        invalid_zone_geometry: :error,
        missing_scene_layer: :error,
        stale_ambient_flow_reference: :error,
        stale_collection_sheet_reference: :error,
        stale_pin_flow_reference: :error,
        stale_pin_sheet_reference: :error,
        stale_variable_reference: :error,
        stale_zone_target: :error,
        ambiguous_patrol_route: :warning,
        element_outside_canvas: :warning,
        empty_action_zone: :warning,
        incomplete_action_assignment: :warning,
        incomplete_condition: :warning,
        leader_without_walkable_area: :warning,
        missing_ambient_event_variable: :warning,
        missing_background: :warning,
        missing_default_layer: :warning,
        missing_display_variable: :warning,
        missing_scene_shortcut: :warning,
        missing_zone_label_icon: :warning,
        multiple_default_layers: :warning,
        patrol_on_playable_pin: :warning,
        patrol_without_route: :warning,
        playable_party_without_leader: :warning,
        variable_type_mismatch: :warning,
        empty_collection: :info,
        empty_scene: :info,
        empty_visibility_condition: :info
      })
    end
  end

  describe "the three catalogs share one vocabulary" do
    test "an undeclared code raises rather than defaulting to a severity" do
      for module <- [FlowHealth, SheetHealth, SceneHealth] do
        assert_raise KeyError, fn -> module.severity_for(:a_code_that_was_never_declared) end
      end
    end

    test "every severity is one of the three the UI can render" do
      # Not a substitute for the catalogs above — that assertion is nearly
      # tautological on its own, since `codes/0` and `severity_for/1` read the
      # same map. It is here because a fourth severity atom would reach the Vue
      # layer with no icon and no colour, and the failure would be silent.
      for module <- [FlowHealth, SheetHealth, SceneHealth], code <- module.codes() do
        assert module.severity_for(code) in [:error, :warning, :info]
      end
    end
  end

  # An exact map equality, plus a count check so a code cannot be added to the
  # checker and to this expectation in the same careless motion without the
  # author seeing both.
  defp assert_catalog(module, expected) do
    actual = Map.new(module.codes(), &{&1, module.severity_for(&1)})

    assert actual == expected
    assert map_size(expected) == length(module.codes())
  end
end

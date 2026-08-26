defmodule Storyarn.Sheets.Health.Contracts.SeverityCatalogTest do
  @moduledoc """
  Freezes the Sheet-owned health vocabulary exposed to its consumers.

  The exact map makes every new, removed or reclassified Sheet finding an
  explicit product decision without coupling that decision to another tool.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Health.Rules.Checker, as: HealthChecker

  test "every Sheet health code is pinned to a supported severity" do
    expected = %{
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
    }

    actual = Map.new(HealthChecker.codes(), &{&1, HealthChecker.severity_for(&1)})

    assert actual == expected
    assert map_size(expected) == length(HealthChecker.codes())
    assert Enum.all?(Map.values(actual), &(&1 in [:error, :warning, :info]))
    assert_raise KeyError, fn -> HealthChecker.severity_for(:a_code_that_was_never_declared) end
  end
end

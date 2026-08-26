defmodule Storyarn.Flows.Logic do
  @moduledoc """
  Capability boundary for Flow conditions, instructions, formulas and the
  variable vocabulary consumed by authoring and execution.
  """

  alias Storyarn.Flows.Condition
  alias Storyarn.Flows.FormulaEngine
  alias Storyarn.Flows.FormulaRuntime
  alias Storyarn.Flows.Instruction
  alias Storyarn.Flows.VariableCatalog
  alias Storyarn.Flows.VariableConstraints
  alias Storyarn.Flows.VariableNamespaceResolver
  alias Storyarn.Flows.VariableSearch

  defdelegate condition_logic_types(), to: Condition, as: :logic_types
  defdelegate condition_operators_for_type(type), to: Condition, as: :operators_for_type
  defdelegate condition_valid_operator?(operator), to: Condition, as: :valid_operator?
  defdelegate condition_operator_label(operator), to: Condition, as: :operator_label
  defdelegate condition_operator_requires_value?(operator), to: Condition, as: :operator_requires_value?
  defdelegate condition_parse(condition), to: Condition, as: :parse
  defdelegate condition_to_json(condition), to: Condition, as: :to_json
  defdelegate condition_sanitize(condition), to: Condition, as: :sanitize
  defdelegate condition_validate(condition), to: Condition, as: :validate
  defdelegate condition_has_rules?(condition), to: Condition, as: :has_rules?
  defdelegate condition_new(), to: Condition, as: :new_block_condition
  defdelegate condition_extract_all_rules(condition), to: Condition, as: :extract_all_rules

  defdelegate instruction_operators_for_type(type), to: Instruction, as: :operators_for_type
  defdelegate instruction_operator_label(operator), to: Instruction, as: :operator_label
  defdelegate instruction_operator_requires_value?(operator), to: Instruction, as: :operator_requires_value?
  defdelegate instruction_valid_value_type?(type), to: Instruction, as: :valid_value_type?
  defdelegate instruction_valid_operator?(operator), to: Instruction, as: :valid_operator?
  defdelegate instruction_all_operators(), to: Instruction, as: :all_operators
  defdelegate instruction_known_keys(), to: Instruction, as: :known_keys
  defdelegate variable_type_map(variables), to: Instruction
  defdelegate instruction_has_type_warnings?(assignments, variable_types), to: Instruction, as: :has_type_warnings?
  defdelegate instruction_new(), to: Instruction, as: :new
  defdelegate instruction_add_assignment(assignments), to: Instruction, as: :add_assignment
  defdelegate instruction_remove_assignment(assignments, id), to: Instruction, as: :remove_assignment

  defdelegate instruction_update_assignment(assignments, id, field, value),
    to: Instruction,
    as: :update_assignment

  defdelegate instruction_format_short(assignment), to: Instruction, as: :format_assignment_short
  defdelegate instruction_complete_assignment?(assignment), to: Instruction, as: :complete_assignment?
  defdelegate instruction_has_assignments?(assignments), to: Instruction, as: :has_assignments?
  defdelegate instruction_sanitize(assignments), to: Instruction, as: :sanitize

  defdelegate formula_parse(expression), to: FormulaEngine, as: :parse
  defdelegate formula_extract_symbols(expression), to: FormulaEngine, as: :extract_symbols
  defdelegate formula_evaluate(ast, variables), to: FormulaEngine, as: :evaluate
  defdelegate formula_compute(expression, variables), to: FormulaEngine, as: :compute
  defdelegate formula_to_latex(expression), to: FormulaEngine, as: :to_latex
  defdelegate formula_to_latex_substituted(expression, variables), to: FormulaEngine, as: :to_latex_substituted
  defdelegate recompute_formulas(variables), to: FormulaRuntime
  defdelegate recompute_formula_variables(variables), to: FormulaRuntime, as: :recompute_formulas
  defdelegate translate_same_row(formula_ref, bindings), to: FormulaRuntime
  defdelegate translate_same_row_binding(formula_ref, bindings), to: FormulaRuntime, as: :translate_same_row

  defdelegate variable_constraints(type, config), to: VariableConstraints, as: :extract
  defdelegate clamp_variable(value, constraints, type), to: VariableConstraints, as: :clamp
  defdelegate list_referenceable_variables(project_id), to: VariableCatalog, as: :list_referenceable
  defdelegate search_variable_suggestions(variables, query), to: VariableSearch, as: :suggestions
  defdelegate search_variable_options(variables, opts \\ []), to: VariableSearch, as: :picker_options

  defdelegate resolve_variable_namespace_sheet_id(project_id, namespace),
    to: VariableNamespaceResolver,
    as: :resolve_sheet_id

  defdelegate resolve_variable_namespace_sheet_ids(project_id, namespaces),
    to: VariableNamespaceResolver,
    as: :resolve_sheet_ids

  defmacro authoritative_variable_namespace_owner?(sheet) do
    quote do
      fragment(
        """
        (? IS NOT NULL OR NOT EXISTS (
          SELECT 1
          FROM sheets AS flow_variable_namespace_owner
          WHERE flow_variable_namespace_owner.project_id = ?
            AND flow_variable_namespace_owner.deleted_at IS NULL
            AND flow_variable_namespace_owner.shortcut = CAST(? AS TEXT)
        ))
        """,
        unquote(sheet).shortcut,
        unquote(sheet).project_id,
        unquote(sheet).id
      )
    end
  end
end

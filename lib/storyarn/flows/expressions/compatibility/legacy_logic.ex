defmodule Storyarn.Flows.Logic do
  @moduledoc "Deprecated compatibility boundary. Use `Storyarn.Flows.Expressions`."

  alias Storyarn.Flows.Expressions

  defdelegate condition_logic_types(), to: Expressions
  defdelegate condition_operators_for_type(type), to: Expressions
  defdelegate condition_valid_operator?(operator), to: Expressions
  defdelegate condition_operator_label(operator), to: Expressions
  defdelegate condition_operator_requires_value?(operator), to: Expressions
  defdelegate condition_parse(condition), to: Expressions
  defdelegate condition_to_json(condition), to: Expressions
  defdelegate condition_sanitize(condition), to: Expressions
  defdelegate condition_validate(condition), to: Expressions
  defdelegate condition_has_rules?(condition), to: Expressions
  defdelegate condition_new(), to: Expressions
  defdelegate condition_extract_all_rules(condition), to: Expressions

  defdelegate instruction_operators_for_type(type), to: Expressions
  defdelegate instruction_operator_label(operator), to: Expressions
  defdelegate instruction_operator_requires_value?(operator), to: Expressions
  defdelegate instruction_valid_value_type?(type), to: Expressions
  defdelegate instruction_valid_operator?(operator), to: Expressions
  defdelegate instruction_all_operators(), to: Expressions
  defdelegate instruction_known_keys(), to: Expressions
  defdelegate variable_type_map(variables), to: Expressions
  defdelegate instruction_has_type_warnings?(assignments, variable_types), to: Expressions
  defdelegate instruction_new(), to: Expressions
  defdelegate instruction_add_assignment(assignments), to: Expressions
  defdelegate instruction_remove_assignment(assignments, id), to: Expressions
  defdelegate instruction_update_assignment(assignments, id, field, value), to: Expressions
  defdelegate instruction_format_short(assignment), to: Expressions
  defdelegate instruction_complete_assignment?(assignment), to: Expressions
  defdelegate instruction_has_assignments?(assignments), to: Expressions
  defdelegate instruction_sanitize(assignments), to: Expressions

  defdelegate formula_parse(expression), to: Expressions
  defdelegate formula_extract_symbols(expression), to: Expressions
  defdelegate formula_evaluate(ast, variables), to: Expressions
  defdelegate formula_compute(expression, variables), to: Expressions
  defdelegate formula_to_latex(expression), to: Expressions
  defdelegate formula_to_latex_substituted(expression, variables), to: Expressions
  defdelegate recompute_formulas(variables), to: Expressions
  defdelegate recompute_formula_variables(variables), to: Expressions
  defdelegate translate_same_row(formula_ref, bindings), to: Expressions
  defdelegate translate_same_row_binding(formula_ref, bindings), to: Expressions

  defdelegate variable_constraints(type, config), to: Expressions
  defdelegate clamp_variable(value, constraints, type), to: Expressions
  defdelegate list_referenceable_variables(project_id), to: Expressions
  defdelegate search_variable_suggestions(variables, query), to: Expressions
  defdelegate search_variable_options(variables, opts \\ []), to: Expressions
  defdelegate resolve_variable_namespace_sheet_id(project_id, namespace), to: Expressions
  defdelegate resolve_variable_namespace_sheet_ids(project_id, namespaces), to: Expressions

  @doc deprecated: "SQL predicates belong to the consuming query module"
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

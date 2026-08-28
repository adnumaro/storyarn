defmodule Storyarn.Sheets.Expressions do
  @moduledoc """
  Public boundary for Sheet variables, constraints and formula evaluation.

  Callers use this capability instead of depending on its query projections or
  rule modules. `Storyarn.Sheets.FormulaEngine` remains a stable public identity
  for clients that already consume its parser and AST contract directly.
  """

  alias Storyarn.Sheets.Expressions.Execution.FormulaResolver
  alias Storyarn.Sheets.Expressions.Queries.FormulaBindings, as: FormulaBindingQueries
  alias Storyarn.Sheets.Expressions.Queries.VariableCatalog
  alias Storyarn.Sheets.Expressions.Queries.VariableNamespaces
  alias Storyarn.Sheets.Expressions.Queries.VariableValues
  alias Storyarn.Sheets.Expressions.Rules.Constraints.Boolean, as: BooleanConstraints
  alias Storyarn.Sheets.Expressions.Rules.Constraints.Date, as: DateConstraints
  alias Storyarn.Sheets.Expressions.Rules.Constraints.Number, as: NumberConstraints
  alias Storyarn.Sheets.Expressions.Rules.Constraints.Selector, as: SelectorConstraints
  alias Storyarn.Sheets.Expressions.Rules.Constraints.String, as: StringConstraints
  alias Storyarn.Sheets.Expressions.Rules.FormulaBindings
  alias Storyarn.Sheets.FormulaEngine

  defdelegate resolve_sheet_id(project_id, namespace), to: VariableNamespaces
  defdelegate resolve_sheet_ids(project_id, namespaces), to: VariableNamespaces

  defdelegate list_definitions(project_id, filter \\ :all, opts \\ []), to: VariableCatalog

  defdelegate search_variable_definitions(project_id, filter \\ :all, opts \\ []),
    to: VariableCatalog,
    as: :list_definitions

  defdelegate list_initial_value_matches(project_id, filter, operator, literal, opts \\ []),
    to: VariableCatalog

  defdelegate search_variable_initial_value_matches(project_id, filter, operator, literal, opts \\ []),
    to: VariableCatalog,
    as: :list_initial_value_matches

  defdelegate get_definition(project_id, block_id, qualified_reference), to: VariableCatalog

  defdelegate get_variable_definition(project_id, block_id, qualified_reference),
    to: VariableCatalog,
    as: :get_definition

  defdelegate predicate_string_aliases(project_id, definition, operator, literal),
    to: VariableCatalog

  defdelegate variable_predicate_string_aliases(project_id, definition, operator, literal),
    to: VariableCatalog,
    as: :predicate_string_aliases

  defdelegate list_formula_usages(project_id, qualified_reference, opts \\ []),
    to: VariableCatalog

  defdelegate list_formula_variable_usages(project_id, qualified_reference, opts \\ []),
    to: VariableCatalog,
    as: :list_formula_usages

  defdelegate regular_variable_types(), to: VariableCatalog
  defdelegate table_variable_types(), to: VariableCatalog
  defdelegate constant_table_variable_types(), to: VariableCatalog

  defdelegate list_project_variables(project_id), to: VariableValues
  defdelegate list_reference_options(project_id), to: VariableValues
  defdelegate resolve_variable_values(project_id, references), to: VariableValues

  defdelegate rewrite_cells(cells, parent_shortcut, child_shortcut, variable_name_mapping),
    to: FormulaBindings

  defdelegate build_var_name_mapping(parent_sheet_id, child_sheet_id), to: FormulaBindingQueries

  defdelegate has_formula_variable_bindings?(cells), to: FormulaBindings
  defdelegate any_rows_have_formula_bindings?(rows), to: FormulaBindings

  defdelegate enrich_table_formulas(table_data, project_id),
    to: FormulaResolver,
    as: :enrich_table_data

  defdelegate parse_formula(expression), to: FormulaEngine, as: :parse
  defdelegate extract_formula_symbols(ast), to: FormulaEngine, as: :extract_symbols
  defdelegate evaluate_formula(ast, values), to: FormulaEngine, as: :evaluate
  defdelegate compute_formula(expression, values), to: FormulaEngine, as: :compute
  defdelegate parse(expression), to: FormulaEngine
  defdelegate extract_symbols(ast), to: FormulaEngine
  defdelegate evaluate(ast, values), to: FormulaEngine
  defdelegate compute(expression, values), to: FormulaEngine
  defdelegate formula_to_latex(ast), to: FormulaEngine, as: :to_latex

  defdelegate formula_to_latex_substituted(ast, values),
    to: FormulaEngine,
    as: :to_latex_substituted

  @doc "Clamps an authored value according to the rules of its field type."
  @spec clamp_to_constraints(term(), map() | nil, String.t()) :: term()
  def clamp_to_constraints(value, constraints, "number"), do: NumberConstraints.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "text"), do: StringConstraints.clamp(value, constraints)

  def clamp_to_constraints(value, _constraints, "rich_text"), do: value

  def clamp_to_constraints(value, constraints, type) when type in ["select", "multi_select"],
    do: SelectorConstraints.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "date"), do: DateConstraints.clamp(value, constraints)

  def clamp_to_constraints(value, constraints, "boolean"), do: BooleanConstraints.clamp(value, constraints)

  def clamp_to_constraints(value, _constraints, _field_type), do: value

  defdelegate number_clamp_and_format(value, constraints),
    to: NumberConstraints,
    as: :clamp_and_format

  defdelegate number_parse_constraint(value), to: NumberConstraints, as: :parse_constraint
end

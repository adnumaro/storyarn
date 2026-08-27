defmodule Storyarn.Sheets.Logic do
  @moduledoc "Deprecated compatibility boundary. Use `Storyarn.Sheets.Expressions`."

  alias Storyarn.Sheets.Expressions

  defdelegate resolve_sheet_id(project_id, namespace), to: Expressions
  defdelegate resolve_sheet_ids(project_id, namespaces), to: Expressions
  defdelegate list_definitions(project_id, filter \\ :all, opts \\ []), to: Expressions
  defdelegate search_variable_definitions(project_id, filter \\ :all, opts \\ []), to: Expressions
  defdelegate list_initial_value_matches(project_id, filter, operator, literal, opts \\ []), to: Expressions

  defdelegate search_variable_initial_value_matches(project_id, filter, operator, literal, opts \\ []),
    to: Expressions

  defdelegate get_definition(project_id, block_id, qualified_reference), to: Expressions
  defdelegate get_variable_definition(project_id, block_id, qualified_reference), to: Expressions
  defdelegate predicate_string_aliases(project_id, definition, operator, literal), to: Expressions

  defdelegate variable_predicate_string_aliases(project_id, definition, operator, literal),
    to: Expressions

  defdelegate list_formula_usages(project_id, qualified_reference, opts \\ []), to: Expressions
  defdelegate list_formula_variable_usages(project_id, qualified_reference, opts \\ []), to: Expressions
  defdelegate regular_variable_types(), to: Expressions
  defdelegate table_variable_types(), to: Expressions
  defdelegate constant_table_variable_types(), to: Expressions
  defdelegate list_project_variables(project_id), to: Expressions
  defdelegate list_reference_options(project_id), to: Expressions
  defdelegate resolve_variable_values(project_id, references), to: Expressions
  defdelegate rewrite_cells(cells, parent_shortcut, child_shortcut, variable_name_mapping), to: Expressions
  defdelegate build_var_name_mapping(parent_sheet_id, child_sheet_id), to: Expressions
  defdelegate has_formula_variable_bindings?(cells), to: Expressions
  defdelegate any_rows_have_formula_bindings?(rows), to: Expressions
  defdelegate enrich_table_formulas(table_data, project_id), to: Expressions
  defdelegate parse_formula(expression), to: Expressions
  defdelegate extract_formula_symbols(ast), to: Expressions
  defdelegate evaluate_formula(ast, values), to: Expressions
  defdelegate compute_formula(expression, values), to: Expressions
  defdelegate parse(expression), to: Expressions
  defdelegate extract_symbols(ast), to: Expressions
  defdelegate evaluate(ast, values), to: Expressions
  defdelegate compute(expression, values), to: Expressions
  defdelegate formula_to_latex(ast), to: Expressions
  defdelegate formula_to_latex_substituted(ast, values), to: Expressions
  defdelegate clamp_to_constraints(value, constraints, field_type), to: Expressions
  defdelegate number_clamp_and_format(value, constraints), to: Expressions
  defdelegate number_parse_constraint(value), to: Expressions

  @doc deprecated: "SQL predicates belong to the consuming query module"
  defmacro authoritative_namespace_owner?(sheet) do
    quote do
      fragment(
        """
        (? IS NOT NULL OR NOT EXISTS (
          SELECT 1
          FROM sheets AS variable_namespace_owner
          WHERE variable_namespace_owner.project_id = ?
            AND variable_namespace_owner.deleted_at IS NULL
            AND variable_namespace_owner.shortcut = CAST(? AS TEXT)
        ))
        """,
        unquote(sheet).shortcut,
        unquote(sheet).project_id,
        unquote(sheet).id
      )
    end
  end
end

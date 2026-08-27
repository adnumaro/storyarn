defmodule Storyarn.Scenes.Logic do
  @moduledoc "Deprecated compatibility boundary. Use `Storyarn.Scenes.Expressions`."

  alias Storyarn.Scenes.Expressions

  defdelegate list_referenceable(project_id), to: Expressions
  defdelegate resolve_sheet_id(project_id, namespace), to: Expressions
  defdelegate resolve_sheet_ids(project_id, namespaces), to: Expressions
  defdelegate extract_constraints(type, config), to: Expressions
  defdelegate clamp_variable(value, constraints, type), to: Expressions
  defdelegate parse_condition(value), to: Expressions
  defdelegate sanitize_condition(value), to: Expressions
  defdelegate validate_condition(value), to: Expressions
  defdelegate condition_has_rules?(value), to: Expressions
  defdelegate extract_condition_rules(value), to: Expressions
  defdelegate sanitize_instructions(assignments), to: Expressions
  defdelegate instructions_present?(assignments), to: Expressions
  defdelegate instruction_complete?(assignment), to: Expressions
  defdelegate instruction_operators_for_type(type), to: Expressions
  defdelegate instruction_operator_label(operator), to: Expressions
end

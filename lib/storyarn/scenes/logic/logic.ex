defmodule Storyarn.Scenes.Logic do
  @moduledoc """
  Public capability boundary for Scene conditions, instructions, and variables.

  `Condition` and `Instruction` keep their stable module identities because
  their data shapes are contracts shared by the editor and exploration runtime.
  """

  alias Storyarn.Scenes.Condition
  alias Storyarn.Scenes.Instruction
  alias Storyarn.Scenes.VariableCatalog
  alias Storyarn.Scenes.VariableConstraints
  alias Storyarn.Scenes.VariableNamespaceResolver

  defdelegate list_referenceable(project_id), to: VariableCatalog
  defdelegate resolve_sheet_id(project_id, namespace), to: VariableNamespaceResolver
  defdelegate resolve_sheet_ids(project_id, namespaces), to: VariableNamespaceResolver

  defdelegate extract_constraints(type, config), to: VariableConstraints, as: :extract
  defdelegate clamp_variable(value, constraints, type), to: VariableConstraints, as: :clamp

  defdelegate parse_condition(value), to: Condition, as: :parse
  defdelegate sanitize_condition(value), to: Condition, as: :sanitize
  defdelegate validate_condition(value), to: Condition, as: :validate
  defdelegate condition_has_rules?(value), to: Condition, as: :has_rules?
  defdelegate extract_condition_rules(value), to: Condition, as: :extract_all_rules

  defdelegate sanitize_instructions(assignments), to: Instruction, as: :sanitize
  defdelegate instructions_present?(assignments), to: Instruction, as: :has_assignments?
  defdelegate instruction_complete?(assignment), to: Instruction, as: :complete_assignment?
  defdelegate instruction_operators_for_type(type), to: Instruction, as: :operators_for_type
  defdelegate instruction_operator_label(operator), to: Instruction, as: :operator_label
end

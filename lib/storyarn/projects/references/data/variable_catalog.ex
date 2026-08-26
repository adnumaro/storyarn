defmodule Storyarn.Projects.References.VariableCatalog do
  @moduledoc """
  References-owned contract for persisted variable-bearing field types.

  The lists are duplicated deliberately: reference extraction must remain
  stable even when the Sheet editor evolves its own catalog vocabulary.
  """

  @regular_variable_types ~w(text rich_text number select multi_select boolean date)
  @table_variable_types ~w(number text boolean select multi_select date reference formula)
  @constant_table_variable_types ~w(formula)

  @spec regular_variable_types() :: [String.t()]
  def regular_variable_types, do: @regular_variable_types

  @spec table_variable_types() :: [String.t()]
  def table_variable_types, do: @table_variable_types

  @spec constant_table_variable_types() :: [String.t()]
  def constant_table_variable_types, do: @constant_table_variable_types
end

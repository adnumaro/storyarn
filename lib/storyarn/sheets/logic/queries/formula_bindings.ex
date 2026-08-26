defmodule Storyarn.Sheets.Logic.Queries.FormulaBindings do
  @moduledoc """
  Reads the inherited block relationship needed to rewrite formula bindings.

  The returned mapping is local to Sheet Logic. It deliberately uses the
  capability's own block projection rather than importing Editor persistence.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Logic.Data.BlockRecord, as: Block

  @doc """
  Builds a mapping of parent block variable name to child block variable name
  for inherited blocks between a parent and child sheet.

  The join covers the full ancestor chain because a child block may point to a
  grandparent block through `inherited_from_block_id`.
  """
  @spec build_var_name_mapping(integer(), integer()) :: map()
  def build_var_name_mapping(parent_sheet_id, child_sheet_id) do
    from(child_b in Block,
      join: parent_b in Block,
      on: child_b.inherited_from_block_id == parent_b.id,
      where:
        child_b.sheet_id == ^child_sheet_id and
          parent_b.sheet_id == ^parent_sheet_id and
          is_nil(child_b.deleted_at) and
          not is_nil(parent_b.variable_name),
      select: {parent_b.variable_name, child_b.variable_name}
    )
    |> Repo.all()
    |> Map.new()
  end
end

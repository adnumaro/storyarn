defmodule Storyarn.Sheets.Health.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Health.Data.VariableReferenceRecord

  test "health owns its read projection of the shared variable-reference index" do
    assert VariableReferenceRecord.__schema__(:source) == "variable_references"

    assert Enum.all?([:block_id, :source_type, :source_id, :kind], fn field ->
             field in VariableReferenceRecord.__schema__(:fields)
           end)
  end
end

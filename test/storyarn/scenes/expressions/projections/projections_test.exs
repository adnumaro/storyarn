defmodule Storyarn.Scenes.Expressions.Projections.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Expressions.Projections.BlockRecord
  alias Storyarn.Scenes.Expressions.Projections.SheetRecord
  alias Storyarn.Scenes.Expressions.Projections.TableColumnRecord
  alias Storyarn.Scenes.Expressions.Projections.TableRowRecord

  test "logic owns focused projections over the shared variable tables" do
    assert SheetRecord.__schema__(:source) == "sheets"
    assert BlockRecord.__schema__(:source) == "blocks"
    assert TableColumnRecord.__schema__(:source) == "table_columns"
    assert TableRowRecord.__schema__(:source) == "table_rows"

    assert Enum.sort(SheetRecord.__schema__(:fields)) ==
             Enum.sort([:id, :name, :shortcut, :project_id, :deleted_at, :inserted_at, :updated_at])

    assert :variable_name in BlockRecord.__schema__(:fields)
    assert :config in TableColumnRecord.__schema__(:fields)
    assert :cells in TableRowRecord.__schema__(:fields)
  end
end

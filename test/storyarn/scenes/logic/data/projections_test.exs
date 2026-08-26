defmodule Storyarn.Scenes.Logic.Data.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Logic.Data.BlockRecord
  alias Storyarn.Scenes.Logic.Data.SheetRecord
  alias Storyarn.Scenes.Logic.Data.TableColumnRecord
  alias Storyarn.Scenes.Logic.Data.TableRowRecord

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

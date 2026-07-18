defmodule Storyarn.Sheets.BlockLayoutInheritanceTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  test "DnD and its undo payload cover own blocks only when active inherited instances exist" do
    project = project_fixture()
    parent = sheet_fixture(project, %{name: "Parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child"})
    source = inheritable_block_fixture(parent, label: "Inherited")

    inherited =
      child.id
      |> Sheets.list_blocks()
      |> Enum.find(&(&1.inherited_from_block_id == source.id and not &1.detached))

    first = block_fixture(child, %{config: %{"label" => "First"}})
    second = block_fixture(child, %{config: %{"label" => "Second"}})
    inherited_position = inherited.position

    dnd_layout = [
      %{id: second.id, column_group_id: nil, column_index: 0},
      %{id: first.id, column_group_id: nil, column_index: 0}
    ]

    assert {:ok, _blocks} =
             Sheets.reorder_blocks_with_columns(child.id, dnd_layout)

    assert Enum.map(
             Enum.filter(Sheets.list_blocks(child.id), &(&1.id in [first.id, second.id])),
             & &1.id
           ) == [second.id, first.id]

    undo_layout = [
      %{id: first.id, column_group_id: nil, column_index: 0},
      %{id: second.id, column_group_id: nil, column_index: 0}
    ]

    assert {:ok, _blocks} =
             Sheets.reorder_blocks_with_columns(child.id, undo_layout)

    assert {:ok, _blocks} =
             Sheets.reorder_blocks(child.id, [second.id, first.id])

    persisted_inherited = Repo.reload!(inherited)
    assert persisted_inherited.position == inherited_position
    refute persisted_inherited.detached
    assert persisted_inherited.inherited_from_block_id == source.id
  end
end

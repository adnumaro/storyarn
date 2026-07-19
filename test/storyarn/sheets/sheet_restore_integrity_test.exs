defmodule Storyarn.Sheets.SheetRestoreIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.Sheet

  test "restores a reference block with its original ID and rebuilds its tracker" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    assert tracked_reference?(block.id, target_sheet.id)

    {:ok, trashed_sheet} = Sheets.trash_sheet(source_sheet)

    Repo.delete_all(
      from(reference in EntityReference,
        where: reference.source_type == "block" and reference.source_id == ^block.id
      )
    )

    refute tracked_reference?(block.id, target_sheet.id)

    assert {:ok, restored_sheet} = Sheets.restore_sheet(trashed_sheet)
    assert restored_sheet.id == source_sheet.id

    restored_block = Repo.get!(Block, block.id)
    assert restored_block.id == block.id
    assert is_nil(restored_block.deleted_at)
    assert tracked_reference?(block.id, target_sheet.id)
  end

  test "rolls back the complete sheet restore when a block target became inactive" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    {:ok, trashed_source} = Sheets.trash_sheet(source_sheet)
    {:ok, _trashed_target} = Sheets.trash_sheet(target_sheet)

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, target_id}} =
             Sheets.restore_sheet(trashed_source)

    assert target_id == target_sheet.id
    assert Repo.reload!(trashed_source).deleted_at
    assert is_nil(Repo.reload!(block).deleted_at)
  end

  test "source delete and restore write through trash without replacing the inherited instance" do
    project = project_fixture()
    parent = sheet_fixture(project)
    child = child_sheet_fixture(project, parent)
    source = inheritable_block_fixture(parent, label: "Inherited source")

    instance =
      Repo.one!(
        from(block in Block,
          where:
            block.sheet_id == ^child.id and
              block.inherited_from_block_id == ^source.id and
              block.detached == false and is_nil(block.deleted_at)
        )
      )

    {:ok, trashed_child} = Sheets.trash_sheet(child)
    {:ok, deleted_source} = Sheets.delete_block(source)

    deleted_instance = Repo.get!(Block, instance.id)
    assert deleted_instance.id == instance.id
    assert deleted_instance.deleted_at

    assert {:ok, restored_source} = Sheets.restore_block(deleted_source)
    assert restored_source.id == source.id

    hidden_instance = Repo.get!(Block, instance.id)
    assert hidden_instance.id == instance.id
    assert is_nil(hidden_instance.deleted_at)
    assert Repo.reload!(trashed_child).deleted_at

    assert {:ok, restored_child} = Sheets.restore_sheet(trashed_child)
    assert restored_child.id == child.id
    assert inherited_instance!(child.id, source.id).id == instance.id
  end

  test "definition updates and new sources write through trash before restore" do
    project = project_fixture()
    parent = sheet_fixture(project)
    child = child_sheet_fixture(project, parent)
    source = inheritable_block_fixture(parent, label: "Original definition")

    instance =
      inherited_instance!(child.id, source.id)

    {:ok, trashed_child} = Sheets.trash_sheet(child)

    assert {:ok, _updated_source} =
             Sheets.update_block_config(source, %{
               "label" => "Updated definition",
               "placeholder" => "Updated while child was in trash"
             })

    new_source = inheritable_block_fixture(parent, label: "Created while hidden")

    synchronized = inherited_instance!(child.id, source.id)
    assert synchronized.id == instance.id
    assert synchronized.config["label"] == "Updated definition"
    assert synchronized.config["placeholder"] == "Updated while child was in trash"

    created = inherited_instance!(child.id, new_source.id)
    assert created.id != instance.id
    assert created.config["label"] == "Created while hidden"

    assert Repo.reload!(trashed_child).deleted_at

    assert {:ok, restored_child} = Sheets.restore_sheet(trashed_child)
    assert restored_child.id == child.id
    assert inherited_instance!(child.id, source.id).id == instance.id
    assert inherited_instance!(child.id, new_source.id).id == created.id
  end

  test "table definition writers preserve hidden child IDs and local cell values before restore" do
    project = project_fixture()
    parent = sheet_fixture(project)
    child = child_sheet_fixture(project, parent)

    {:ok, source_table} =
      Sheets.create_block(parent, %{
        type: "table",
        scope: "children",
        config: %{"label" => "Original table", "collapsed" => false}
      })

    child_table = inherited_instance!(child.id, source_table.id)
    [source_base_column] = Sheets.list_table_columns(source_table.id)
    [source_base_row] = Sheets.list_table_rows(source_table.id)

    {:ok, source_removed_column} =
      Sheets.create_table_column(source_table, %{name: "Remove me", type: "text"})

    {:ok, source_removed_row} =
      Sheets.create_table_row(source_table, %{name: "Remove me"})

    child_columns_before = Map.new(Sheets.list_table_columns(child_table.id), &{&1.slug, &1})
    child_rows_before = Map.new(Sheets.list_table_rows(child_table.id), &{&1.slug, &1})
    child_base_column = Map.fetch!(child_columns_before, source_base_column.slug)
    child_removed_column = Map.fetch!(child_columns_before, source_removed_column.slug)
    child_base_row = Map.fetch!(child_rows_before, source_base_row.slug)
    child_removed_row = Map.fetch!(child_rows_before, source_removed_row.slug)
    old_base_column_slug = source_base_column.slug
    old_base_row_slug = source_base_row.slug

    assert {:ok, _updated_child_row} =
             Sheets.update_table_cell(child_base_row, child_base_column.slug, 99)

    {:ok, trashed_child} = Sheets.trash_sheet(child)

    assert {:ok, _updated_table} =
             Sheets.update_block_config(source_table, %{
               "label" => "Updated table",
               "collapsed" => true
             })

    assert {:ok, source_base_column} =
             Sheets.update_table_column(source_base_column, %{
               name: "Score",
               required: true
             })

    assert {:ok, source_base_row} =
             Sheets.update_table_row(source_base_row, %{name: "Primary"})

    assert {:ok, _deleted_column} =
             Sheets.delete_table_column(source_removed_column)

    assert {:ok, _deleted_row} = Sheets.delete_table_row(source_removed_row)

    assert {:ok, source_new_column} =
             Sheets.create_table_column(source_table, %{name: "Added later", type: "text"})

    assert {:ok, source_new_row} =
             Sheets.create_table_row(source_table, %{name: "Added later"})

    assert {:ok, _columns} =
             Sheets.reorder_table_columns(source_table.id, [
               source_new_column.id,
               source_base_column.id
             ])

    assert {:ok, _rows} =
             Sheets.reorder_table_rows(source_table.id, [
               source_new_row.id,
               source_base_row.id
             ])

    hidden_child_table = inherited_instance!(child.id, source_table.id)
    assert hidden_child_table.id == child_table.id
    assert hidden_child_table.config["label"] == "Updated table"
    assert hidden_child_table.config["collapsed"] == true
    assert Repo.reload!(trashed_child).deleted_at

    source_columns = Map.new(Sheets.list_table_columns(source_table.id), &{&1.slug, &1})
    child_columns = Map.new(Sheets.list_table_columns(child_table.id), &{&1.slug, &1})

    assert child_columns |> Map.keys() |> Enum.sort() ==
             source_columns |> Map.keys() |> Enum.sort()

    restored_base_column = Map.fetch!(child_columns, source_base_column.slug)
    assert restored_base_column.id == child_base_column.id
    assert restored_base_column.required
    assert restored_base_column.position == source_columns[source_base_column.slug].position
    refute Map.has_key?(child_columns, old_base_column_slug)
    refute Map.has_key?(child_columns, source_removed_column.slug)
    refute Repo.get(Storyarn.Sheets.TableColumn, child_removed_column.id)
    assert Map.has_key?(child_columns, source_new_column.slug)

    source_rows = Map.new(Sheets.list_table_rows(source_table.id), &{&1.slug, &1})
    child_rows = Map.new(Sheets.list_table_rows(child_table.id), &{&1.slug, &1})

    assert child_rows |> Map.keys() |> Enum.sort() ==
             source_rows |> Map.keys() |> Enum.sort()

    restored_base_row = Map.fetch!(child_rows, source_base_row.slug)
    assert restored_base_row.id == child_base_row.id
    assert restored_base_row.cells[source_base_column.slug] == 99
    refute Map.has_key?(restored_base_row.cells, old_base_column_slug)
    assert restored_base_row.cells[source_new_column.slug] == nil
    assert restored_base_row.position == source_rows[source_base_row.slug].position
    refute Map.has_key?(child_rows, old_base_row_slug)
    refute Map.has_key?(child_rows, source_removed_row.slug)
    refute Repo.get(Storyarn.Sheets.TableRow, child_removed_row.id)
    assert Map.has_key?(child_rows, source_new_row.slug)

    hidden_column_ids = Map.new(child_columns, fn {slug, column} -> {slug, column.id} end)
    hidden_row_ids = Map.new(child_rows, fn {slug, row} -> {slug, row.id} end)

    assert {:ok, restored_child} = Sheets.restore_sheet(trashed_child)
    assert restored_child.id == child.id

    assert Map.new(Sheets.list_table_columns(child_table.id), &{&1.slug, &1.id}) ==
             hidden_column_ids

    assert Map.new(Sheets.list_table_rows(child_table.id), &{&1.slug, &1.id}) ==
             hidden_row_ids
  end

  test "rejects an inactive parent without changing the sheet ID or visibility" do
    project = project_fixture()
    parent = sheet_fixture(project)
    child = child_sheet_fixture(project, parent)

    {:ok, trashed_child} = Sheets.trash_sheet(child)
    {:ok, _trashed_parent} = Sheets.trash_sheet(parent)

    assert {:error, {:invalid_project_reference, :parent_id, parent_id}} =
             Sheets.restore_sheet(trashed_child)

    assert parent_id == parent.id

    persisted_child = Repo.reload!(child)
    assert persisted_child.id == child.id
    assert persisted_child.deleted_at
  end

  test "rejects a non-image banner atomically" do
    project = project_fixture()
    sheet = sheet_fixture(project)
    audio = audio_asset_fixture(project)

    {:ok, trashed_sheet} = Sheets.trash_sheet(sheet)

    Repo.update_all(
      from(candidate in Sheet, where: candidate.id == ^sheet.id),
      set: [banner_asset_id: audio.id]
    )

    assert {:error, {:invalid_asset_content_type, :banner_asset_id, asset_id}} =
             Sheets.restore_sheet(trashed_sheet)

    assert asset_id == audio.id

    persisted_sheet = Repo.reload!(sheet)
    assert persisted_sheet.id == sheet.id
    assert persisted_sheet.deleted_at
    assert persisted_sheet.banner_asset_id == audio.id
  end

  test "rejects a cyclic parent atomically" do
    project = project_fixture()
    root = sheet_fixture(project)
    child = child_sheet_fixture(project, root)

    {:ok, trashed_root} = Sheets.trash_sheet(root)

    Repo.update_all(
      from(candidate in Sheet, where: candidate.id == ^child.id),
      set: [deleted_at: nil]
    )

    Repo.update_all(
      from(candidate in Sheet, where: candidate.id == ^root.id),
      set: [parent_id: child.id]
    )

    assert {:error, :would_create_cycle} = Sheets.restore_sheet(trashed_root)

    persisted_root = Repo.reload!(root)
    assert persisted_root.id == root.id
    assert persisted_root.deleted_at
    assert persisted_root.parent_id == child.id
  end

  defp tracked_reference?(block_id, target_sheet_id) do
    Repo.exists?(
      from(reference in EntityReference,
        where:
          reference.source_type == "block" and reference.source_id == ^block_id and
            reference.target_type == "sheet" and reference.target_id == ^target_sheet_id
      )
    )
  end

  defp inherited_instance!(sheet_id, source_id) do
    Repo.one!(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and
            block.inherited_from_block_id == ^source_id and
            block.detached == false and is_nil(block.deleted_at)
      )
    )
  end
end

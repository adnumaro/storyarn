defmodule Storyarn.Sheets.WriterReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.Sheet

  test "sheet roots reject foreign and inactive parents on create and move" do
    user = user_fixture()
    project = project_fixture(user)
    foreign_project = project_fixture(user)
    foreign_parent = sheet_fixture(foreign_project)

    assert {:error, {:invalid_project_reference, :parent_id, id}} =
             Sheets.create_sheet(project, %{
               name: "Invalid child",
               parent_id: foreign_parent.id
             })

    assert id == foreign_parent.id
    refute Repo.get_by(Sheet, project_id: project.id, name: "Invalid child")

    sheet = sheet_fixture(project)

    assert {:error, {:invalid_project_reference, :parent_id, ^id}} =
             Sheets.move_sheet_to_position(sheet, foreign_parent.id, 0)

    assert Repo.reload!(sheet).parent_id == nil

    deleted_parent = sheet_fixture(project)
    soft_delete(deleted_parent)

    assert {:error, {:invalid_project_reference, :parent_id, deleted_id}} =
             Sheets.create_sheet(project, %{
               name: "Deleted parent child",
               parent_id: deleted_parent.id
             })

    assert deleted_id == deleted_parent.id
  end

  test "sheet updates reject foreign assets and preserve the current banner" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    local_banner = image_asset_fixture(project, user)
    foreign_banner = image_asset_fixture(project_fixture(user), user)

    assert {:ok, sheet} =
             Sheets.update_sheet(sheet, %{banner_asset_id: local_banner.id})

    assert {:error, {:invalid_project_reference, :banner_asset_id, asset_id}} =
             Sheets.update_sheet(sheet, %{banner_asset_id: foreign_banner.id})

    assert asset_id == foreign_banner.id
    assert Repo.reload!(sheet).banner_asset_id == local_banner.id
  end

  test "sheet banner writers reject same-project non-image assets atomically" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    audio = audio_asset_fixture(project, user)

    assert {:error, {:invalid_asset_content_type, :banner_asset_id, asset_id}} =
             Sheets.update_sheet(sheet, %{banner_asset_id: audio.id})

    assert asset_id == audio.id
    assert Repo.reload!(sheet).banner_asset_id == nil

    assert {:error, {:invalid_asset_content_type, :banner_asset_id, ^asset_id}} =
             Sheets.create_sheet(project, %{
               name: "Invalid audio banner",
               banner_asset_id: audio.id
             })

    refute Repo.get_by(Sheet,
             project_id: project.id,
             name: "Invalid audio banner"
           )
  end

  test "avatar and gallery writers reject foreign assets and batch inserts are atomic" do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    local_asset = image_asset_fixture(project, user)
    foreign_asset = image_asset_fixture(project_fixture(user), user)

    assert {:error, {:invalid_project_reference, :avatar_asset_id, asset_id}} =
             Sheets.add_avatar(sheet, foreign_asset.id)

    assert asset_id == foreign_asset.id
    assert Sheets.list_avatars(sheet.id) == []

    gallery =
      block_fixture(sheet, %{
        type: "gallery",
        config: %{"label" => "Gallery"},
        value: %{}
      })

    assert {:error, {:invalid_project_reference, :gallery_asset_id, ^asset_id}} =
             Sheets.add_gallery_images(gallery, [
               local_asset.id,
               foreign_asset.id
             ])

    assert Sheets.list_gallery_images(gallery.id) == []
  end

  test "reference blocks validate and normalize their target inside the write transaction" do
    user = user_fixture()
    project = project_fixture(user)
    source_sheet = sheet_fixture(project)
    target_flow = flow_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        config: %{"label" => "Target", "allowed_types" => ["flow"]},
        value: %{"target_type" => nil, "target_id" => nil}
      })

    assert {:ok, updated_block} =
             Sheets.update_block_value(block, %{
               "target_type" => "flow",
               "target_id" => Integer.to_string(target_flow.id)
             })

    assert updated_block.value == %{
             "target_type" => "flow",
             "target_id" => target_flow.id
           }

    assert Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id and
                   reference.target_type == "flow" and
                   reference.target_id == ^target_flow.id
             )
           )
  end

  test "reference blocks reject cross-project and inactive targets without changing JSON" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => nil, "target_id" => nil}
      })

    foreign_sheet = sheet_fixture(project_fixture())

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, target_id}} =
             Sheets.update_block_value(block, %{
               "target_type" => "sheet",
               "target_id" => foreign_sheet.id
             })

    assert target_id == foreign_sheet.id
    assert Repo.reload!(block).value == %{"target_type" => nil, "target_id" => nil}

    deleted_sheet = sheet_fixture(project)
    soft_delete(deleted_sheet)

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, deleted_id}} =
             Sheets.update_block_value(block, %{
               "target_type" => "sheet",
               "target_id" => deleted_sheet.id
             })

    assert deleted_id == deleted_sheet.id
    assert Repo.reload!(block).value == %{"target_type" => nil, "target_id" => nil}
  end

  test "rich-text mentions reject foreign targets without changing content" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "rich_text",
        value: %{"content" => "<p>Original</p>"}
      })

    foreign_sheet = sheet_fixture(project_fixture())

    content =
      ~s(<p><span class="mention" data-type="sheet" data-id="#{foreign_sheet.id}">Foreign</span></p>)

    assert {:error, {:invalid_project_reference, {:block, :content, "sheet"}, target_id}} =
             Sheets.update_block_value(block, %{"content" => content})

    assert target_id == Integer.to_string(foreign_sheet.id)
    assert Repo.reload!(block).value == %{"content" => "<p>Original</p>"}
  end

  test "rich-text writers reject every malformed mention element instead of silently dropping it" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "rich_text",
        value: %{"content" => "<p>Original</p>"}
      })

    malformed_mentions = [
      ~s(<p><a class="mention">Missing attributes</a></p>),
      ~s(<p><span class="mention" data-type="sheet">Missing ID</span></p>),
      ~s(<p><span class="mention" data-type="scene" data-id="1">Unsupported</span></p>)
    ]

    Enum.each(malformed_mentions, fn content ->
      assert {:error, {:invalid_project_reference, _context, _value}} =
               Sheets.update_block_value(block, %{"content" => content})

      assert Repo.reload!(block).value == %{"content" => "<p>Original</p>"}
    end)
  end

  test "rich-text accepts non-span mentions and atom content keys while rebuilding backlinks" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "rich_text",
        value: %{"content" => "<p>Original</p>"}
      })

    content =
      ~s(<p><a class="mention" data-type="sheet" data-id="#{target_sheet.id}">Target</a></p>)

    assert {:ok, updated_block} =
             Sheets.update_block_value(block, %{content: content})

    assert updated_block.value == %{"content" => content}

    assert Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id and
                   reference.target_type == "sheet" and
                   reference.target_id == ^target_sheet.id
             )
           )
  end

  test "changing a reference block to a non-reference type removes its stale backlink" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    assert Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id
             )
           )

    assert {:ok, updated_block} =
             Sheets.update_block(block, %{
               type: "text",
               value: %{"content" => "No reference"}
             })

    assert updated_block.type == "text"

    refute Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id
             )
           )
  end

  test "undo refuses to restore a block after its target became inactive" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    assert {:ok, deleted_block} = Sheets.delete_block(block)
    soft_delete(target_sheet)

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, target_id}} =
             Sheets.restore_block(deleted_block)

    assert target_id == target_sheet.id
    assert Repo.reload!(deleted_block).deleted_at

    refute Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id
             )
           )
  end

  test "duplicating a reference block revalidates the target and source under lock" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    soft_delete(target_sheet)

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, target_id}} =
             Sheets.duplicate_block(block)

    assert target_id == target_sheet.id
    assert Enum.map(Sheets.list_blocks(source_sheet.id), & &1.id) == [block.id]

    Repo.update_all(
      from(sheet in Sheet, where: sheet.id == ^target_sheet.id),
      set: [deleted_at: nil]
    )

    soft_delete(source_sheet)

    assert {:error, :block_not_active} = Sheets.duplicate_block(block)
    assert Repo.aggregate(Block, :count, :id) == 1
  end

  test "undo restores the original block ID and rebuilds its backlink after hard deletion" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    target_sheet = sheet_fixture(project)

    block =
      block_fixture(source_sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
      })

    snapshot = block_snapshot(block)
    assert {:ok, _deleted_block} = Sheets.permanently_delete_block(block)
    assert Repo.get(Block, block.id) == nil

    assert {:ok, restored_block} =
             Sheets.create_block_from_snapshot(source_sheet, snapshot)

    assert restored_block.id == block.id

    assert Repo.exists?(
             from(reference in EntityReference,
               where:
                 reference.source_type == "block" and
                   reference.source_id == ^block.id and
                   reference.target_type == "sheet" and
                   reference.target_id == ^target_sheet.id
             )
           )
  end

  test "snapshot undo fails atomically for a foreign target or inactive source sheet" do
    project = project_fixture()
    source_sheet = sheet_fixture(project)
    foreign_target = sheet_fixture(project_fixture())

    foreign_snapshot = %{
      id: 9_000_000_001,
      type: "reference",
      position: 0,
      config: %{"label" => "Target"},
      value: %{"target_type" => "sheet", "target_id" => foreign_target.id},
      variable_name: nil,
      is_constant: false,
      scope: "self",
      column_group_id: nil,
      column_index: 0
    }

    assert {:error, {:invalid_project_reference, {:block, :value, "sheet"}, target_id}} =
             Sheets.create_block_from_snapshot(source_sheet, foreign_snapshot)

    assert target_id == foreign_target.id
    assert Repo.get(Block, foreign_snapshot.id) == nil

    valid_snapshot =
      Map.merge(foreign_snapshot, %{
        id: 9_000_000_002,
        value: %{"target_type" => nil, "target_id" => nil}
      })

    soft_delete(source_sheet)

    assert {:error, :sheet_not_active} =
             Sheets.create_block_from_snapshot(source_sheet, valid_snapshot)

    assert Repo.get(Block, valid_snapshot.id) == nil
  end

  test "sheet reorder rejects inactive owners, invalid parents and non-member IDs atomically" do
    user = user_fixture()
    project = project_fixture(user)
    parent = sheet_fixture(project, %{name: "Parent"})
    first = sheet_fixture(project, %{name: "First", parent_id: parent.id, position: 0})
    second = sheet_fixture(project, %{name: "Second", parent_id: parent.id, position: 1})
    root = sheet_fixture(project, %{name: "Root", position: 2})
    deleted = sheet_fixture(project, %{name: "Deleted", parent_id: parent.id, position: 2})
    foreign_parent = sheet_fixture(project_fixture(user), %{name: "Foreign"})

    soft_delete(deleted)

    invalid_reorders = [
      {parent.id, [first.id]},
      {parent.id, [first.id, first.id]},
      {parent.id, [first.id, "invalid"]},
      {parent.id, [first.id, root.id]},
      {parent.id, [first.id, deleted.id]},
      {foreign_parent.id, [first.id, second.id]}
    ]

    Enum.each(invalid_reorders, fn {parent_id, ids} ->
      assert {:error, _reason} = Sheets.reorder_sheets(project.id, parent_id, ids)
      assert Repo.reload!(first).position == 0
      assert Repo.reload!(second).position == 1
    end)

    soft_delete(project)

    assert {:error, :project_not_active} =
             Sheets.reorder_sheets(project.id, parent.id, [second.id, first.id])

    assert Repo.reload!(first).position == 0
    assert Repo.reload!(second).position == 1
  end

  defp block_snapshot(block) do
    %{
      id: block.id,
      type: block.type,
      position: block.position,
      config: block.config,
      value: block.value,
      variable_name: block.variable_name,
      is_constant: block.is_constant,
      scope: block.scope,
      column_group_id: block.column_group_id,
      column_index: block.column_index
    }
  end

  defp soft_delete(struct) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.update!(Ecto.Changeset.change(struct, deleted_at: deleted_at))
  end
end

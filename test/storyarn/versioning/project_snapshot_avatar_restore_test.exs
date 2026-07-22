defmodule Storyarn.Versioning.ProjectSnapshotAvatarRestoreTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    flow = flow_fixture(project)

    %{flow: flow, project: project, sheet: sheet, user: user}
  end

  describe "project snapshot avatar reconciliation" do
    test "detaches only safety-captured refs, restores exact target, and remains recoverable", %{
      flow: flow,
      project: project,
      sheet: sheet,
      user: user
    } do
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      asset = uploaded_image_asset(project, user, "post-snapshot-avatar.png")
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "Post-snapshot"})

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => avatar.id,
            "text" => "Created after the target snapshot"
          }
        })

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert Repo.get(SheetAvatar, avatar.id) == nil

      assert %FlowNode{deleted_at: %DateTime{}, data: %{"avatar_id" => nil}} =
               Repo.get!(FlowNode, node.id)

      assert {:ok, _restored_node} = Flows.restore_node(flow.id, node.id)
      current_safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 safety_snapshot,
                 pre_restore_snapshot: current_safety_snapshot
               )

      assert %SheetAvatar{id: avatar_id, sheet_id: sheet_id} =
               Repo.get!(SheetAvatar, avatar.id)

      assert avatar_id == avatar.id
      assert sheet_id == sheet.id

      assert %FlowNode{
               id: node_id,
               deleted_at: nil,
               data: %{"avatar_id" => restored_avatar_id}
             } = Repo.get!(FlowNode, node.id)

      assert node_id == node.id
      assert restored_avatar_id == avatar.id
    end

    test "fails closed when a trash node reference is absent from the safety snapshot", %{
      flow: flow,
      project: project,
      sheet: sheet,
      user: user
    } do
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      asset = uploaded_image_asset(project, user, "trash-avatar.png")
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "Trash reference"})

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => avatar.id,
            "text" => "Already in trash"
          }
        })

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(current in FlowNode, where: current.id == ^node.id),
        set: [deleted_at: deleted_at]
      )

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error, {:restore_failed, "sheets", sheet_id, reason}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert {:avatar_restore_conflict, avatar_id, {:node_references_missing_from_pre_restore_snapshot, [node_id]}} =
               reason

      assert sheet_id == sheet.id
      assert avatar_id == avatar.id
      assert node_id == node.id
      assert Repo.get!(SheetAvatar, avatar.id).sheet_id == sheet.id
      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == avatar.id
    end

    test "preserves pending trash refs instead of deleting their avatar target", %{
      flow: flow,
      project: project,
      sheet: sheet,
      user: user
    } do
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      asset = uploaded_image_asset(project, user, "pending-trash-avatar.png")
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "Pending trash ref"})

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => avatar.id,
            "text" => "Swept before the restore"
          }
        })

      assert {:ok, 1} =
               Flows.sweep_trash_refs_jsonb(
                 FlowNode,
                 "flow_node",
                 :data,
                 "avatar_id",
                 :sheet_avatar,
                 avatar.id
               )

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error,
              {:restore_failed, "sheets", sheet_id,
               {:avatar_restore_conflict, avatar_id, {:pending_flow_trash_references, 1}}}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert sheet_id == sheet.id
      assert avatar_id == avatar.id
      assert Repo.get!(SheetAvatar, avatar.id).sheet_id == sheet.id
      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == nil

      assert Repo.exists?(
               from(ref in EntityTrashRef,
                 where:
                   ref.source_id == ^node.id and
                     ref.target_sheet_avatar_id == ^avatar.id
               )
             )
    end
  end

  defp uploaded_image_asset(project, user, filename) do
    content = "#{filename}-content"

    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "image/png"},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          asset.blob_hash,
          BlobStore.ext_from_content_type(asset.content_type)
        )
      )
    end)

    asset
  end
end

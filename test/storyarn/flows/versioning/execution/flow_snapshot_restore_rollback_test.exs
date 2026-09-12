defmodule Storyarn.Flows.Versioning.FlowSnapshotRestoreRollbackTest do
  # ALTER TABLE holds a lock until the sandbox transaction rolls back; keep this
  # case out of the concurrent database suites.
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore

  setup do
    user = user_fixture(%{email: "flow-snapshot-restore-#{Ecto.UUID.generate()}@example.com"})
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "restore_snapshot/3" do
    test "rolls back a copied asset row and object when later localization extraction raises", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "rollback-after-copy.mp3", "rollback after copy", "audio/mpeg")

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker" => "Narrator",
            "text" => "Hello",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Keep this name"})
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      constraint_name = "localized_texts_restore_#{System.unique_integer([:positive])}"
      asset_count_before = project_blob_asset_count(project.id, audio.blob_hash)
      object_keys_before = project_asset_keys(project.id)

      Repo.query!(
        "ALTER TABLE localized_texts ADD CONSTRAINT #{constraint_name} " <>
          "CHECK (project_id <> #{project.id}) NOT VALID"
      )

      assert_raise Postgrex.Error, ~r/#{constraint_name}/, fn ->
        FlowSnapshot.restore_snapshot(modified_flow, snapshot,
          asset_mode: :copy,
          restore_action: {:entity_version_restore, "flow"}
        )
      end

      assert Repo.reload!(modified_flow).name == "Keep this name"
      assert Repo.get!(FlowNode, node.id).flow_id == modified_flow.id
      assert project_blob_asset_count(project.id, audio.blob_hash) == asset_count_before
      assert project_asset_keys(project.id) == object_keys_before
    end
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(
        BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type))
      )
    end)

    asset
  end

  defp project_blob_asset_count(project_id, blob_hash) do
    Repo.aggregate(
      from(asset in Asset,
        where: asset.project_id == ^project_id and asset.blob_hash == ^blob_hash
      ),
      :count
    )
  end

  defp project_asset_keys(project_id) do
    assert {:ok, %{objects: objects, cursor: nil}} =
             ObjectStorage.list_prefix("projects/#{project_id}/assets/", limit: 10_000)

    objects |> Enum.map(& &1.key) |> Enum.sort()
  end
end

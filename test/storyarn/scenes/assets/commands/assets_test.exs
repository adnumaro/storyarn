defmodule Storyarn.Scenes.Assets.Commands.AssetsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Commercial
  alias Storyarn.Platform.ObjectStorage, as: Storage
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Assets.Commands.Assets, as: AssetCommands
  alias Storyarn.Scenes.Assets.Entities.AssetRecord

  test "generated assets use the Scene-owned projection and remain project-scoped" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    binary = File.read!("test/fixtures/images/quadrant_map.png")

    assert {:ok, %AssetRecord{} = asset} =
             AssetCommands.create_generated_asset(binary, binary_attrs("generated-map.png"), project, nil)

    register_storage_cleanup(asset)

    assert asset.project_id == project.id
    assert is_nil(asset.uploaded_by_id)
    assert Scenes.get_asset(project.id, asset.id).id == asset.id
    assert Scenes.get_asset(other_project.id, asset.id) == nil
  end

  test "sanitized SVG writes resolve a scalar actor without entering Projects" do
    user = user_fixture()
    project = project_fixture(user)

    svg = """
    <svg xmlns="http://www.w3.org/2000/svg">
      <script>alert(document.domain)</script>
      <a href="javascript:alert(1)"><circle cx="4" cy="4" r="3"/></a>
    </svg>
    """

    assert {:ok, %AssetRecord{} = asset} =
             Scenes.create_sanitized_svg_asset(
               svg,
               %{filename: "scene-icon.svg", content_type: "image/svg+xml"},
               project,
               user
             )

    register_storage_cleanup(asset)

    assert asset.uploaded_by_id == user.id
    assert asset.metadata["sanitized_svg"] == true
    assert {:ok, stored_svg} = Storage.download(asset.key)
    assert stored_svg =~ "<svg"
    refute stored_svg =~ "<script"
    refute stored_svg =~ "javascript:"
  end

  test "version materialization preserves the local lock, quota, blob and actor contracts" do
    user = user_fixture()
    project = project_fixture(user)
    content = "scene-owned version asset"
    hash = sha256(content)
    source_key = blob_key(project.id, hash, "png")

    assert {:ok, _url, _created?} = Storage.put_if_absent(source_key, content, "image/png")
    on_exit(fn -> Storage.delete(source_key) end)

    metadata = %{
      "filename" => "Restored Scene.png",
      "content_type" => "image/png",
      "size" => byte_size(content)
    }

    assert {:ok, %AssetRecord{} = asset} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               user.id,
               hash,
               source_key,
               metadata
             )

    on_exit(fn -> Storage.delete(asset.key) end)

    assert asset.project_id == project.id
    assert asset.uploaded_by_id == user.id
    assert asset.blob_hash == hash
    assert asset.filename == "Restored Scene.png"
    assert String.ends_with?(asset.key, "/restored_scene.png")
    assert {:ok, ^content} = Storage.download(asset.key)
  end

  test "version materialization rejects SVG that lacks the Scene sanitization proof" do
    user = user_fixture()
    project = project_fixture(user)
    content = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
    hash = sha256(content)

    assert {:error, :invalid_asset_materialization_request} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               user.id,
               hash,
               blob_key(project.id, hash, "svg"),
               %{
                 "filename" => "unsafe.svg",
                 "content_type" => "image/svg+xml",
                 "size" => byte_size(content)
               }
             )
  end

  test "version materialization exposes quota failures as the resolver's two-tuple error contract" do
    user = user_fixture()
    project = project_fixture(user)
    limit = Commercial.entitlement_limit(project.workspace_id, :storage_bytes_per_workspace)
    now = TimeHelpers.now()

    Repo.insert!(%AssetRecord{
      project_id: project.id,
      filename: "quota-filler.bin",
      content_type: "application/octet-stream",
      size: limit,
      key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/quota-filler.bin",
      blob_hash: String.duplicate("f", 64),
      inserted_at: now,
      updated_at: now
    })

    content = "over quota"
    hash = sha256(content)

    assert {:error,
            {:limit_reached,
             %{
               resource: :storage_bytes_per_workspace,
               required: required,
               available: 0
             }}} =
             AssetCommands.create_version_asset_from_storage(
               project.id,
               user.id,
               hash,
               blob_key(project.id, hash, "png"),
               %{
                 "filename" => "restored.png",
                 "content_type" => "image/png",
                 "size" => byte_size(content)
               }
             )

    assert required == byte_size(content)
  end

  test "materialization helpers fail closed around transaction ownership" do
    project = project_fixture(user_fixture())

    assert {:ok, :materialized} =
             AssetCommands.run_asset_materialization_scope(
               [pre_materialized_assets: true],
               fn opts ->
                 assert opts[:pre_materialized_assets] == true
                 {:ok, :materialized}
               end
             )

    assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
             Repo.transaction(fn ->
               AssetCommands.with_asset_copy_tracker([asset_mode: :copy], fn _opts ->
                 flunk("copy callback must not run without the caller-owned tracker")
               end)
             end)

    assert {:error, :materialization_failed} =
             AssetCommands.with_project_storage_lock(project.id, fn ->
               {:error, :materialization_failed}
             end)
  end

  test "a failure after Project registration rolls back the asset row and compensates its object" do
    user = user_fixture()
    project = project_fixture(user)
    content = "scene rollback after registration"
    hash = sha256(content)
    source_key = blob_key(project.id, hash, "png")

    assert {:ok, _url, true} = Storage.put_if_absent(source_key, content, "image/png")
    on_exit(fn -> Storage.delete(source_key) end)

    metadata = %{
      "filename" => "scene-rollback.png",
      "content_type" => "image/png",
      "size" => byte_size(content)
    }

    assert {:error, :forced_after_asset_insert} =
             AssetCommands.run_asset_materialization_scope([], fn opts ->
               AssetCommands.with_project_storage_lock(project.id, fn ->
                 with {:ok, %AssetRecord{} = asset} <-
                        AssetCommands.create_version_asset_from_storage(
                          project.id,
                          user.id,
                          hash,
                          source_key,
                          metadata,
                          opts
                        ) do
                   assert Repo.get(AssetRecord, asset.id)
                   send(self(), {:scene_asset_registered_before_rollback, asset})
                   {:error, :forced_after_asset_insert}
                 end
               end)
             end)

    assert_receive {:scene_asset_registered_before_rollback, asset}
    refute Repo.get(AssetRecord, asset.id)
    assert {:error, _reason} = Storage.download(asset.key)
  end

  defp binary_attrs(filename), do: %{filename: filename, content_type: "image/png"}

  defp register_storage_cleanup(asset) do
    extension = asset.content_type |> String.split("/") |> List.last()
    source_key = blob_key(asset.project_id, asset.blob_hash, extension)

    on_exit(fn ->
      Storage.delete(asset.key)
      Storage.delete(source_key)
    end)
  end

  defp blob_key(project_id, hash, "jpeg"), do: "projects/#{project_id}/blobs/#{hash}.jpg"
  defp blob_key(project_id, hash, extension), do: "projects/#{project_id}/blobs/#{hash}.#{extension}"
  defp sha256(binary), do: :sha256 |> :crypto.hash(binary) |> Base.encode16(case: :lower)
end

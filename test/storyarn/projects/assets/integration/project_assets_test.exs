defmodule Storyarn.Projects.ProjectAssetsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.BlobStore

  test "generated assets stay project-scoped and are available to Scene consumers" do
    user = user_fixture()
    project = project_fixture(user)
    other_project = project_fixture(user)
    binary = File.read!("test/fixtures/images/quadrant_map.png")

    assert {:ok, asset} =
             Projects.create_generated_asset(project.id, binary, %{
               filename: "generated-map.png",
               content_type: "image/png"
             })

    cleanup_asset(project.id, asset, "png")

    assert asset.project_id == project.id
    assert is_nil(asset.uploaded_by_id)
    assert Projects.get_asset(project.id, asset.id).id == asset.id
    assert asset.id in Projects.list_image_asset_ids(project.id)
    assert Projects.get_asset(other_project.id, asset.id) == nil
    refute asset.id in Projects.list_image_asset_ids(other_project.id)
  end

  test "the Project boundary sanitizes SVG assets and resolves the scalar actor" do
    user = user_fixture()
    project = project_fixture(user)

    svg = """
    <svg xmlns="http://www.w3.org/2000/svg">
      <script>alert(document.domain)</script>
      <a href="javascript:alert(1)"><circle cx="4" cy="4" r="3"/></a>
    </svg>
    """

    assert {:ok, asset} =
             Projects.create_sanitized_svg_asset(
               project.id,
               svg,
               %{filename: "scene-icon.svg", content_type: "image/svg+xml"},
               user.id
             )

    cleanup_asset(project.id, asset, "svg")

    assert asset.uploaded_by_id == user.id
    assert asset.metadata["sanitized_svg"] == true
    assert {:ok, stored_svg} = Assets.storage_download(asset.key)
    assert stored_svg =~ "<svg"
    refute stored_svg =~ "<script"
    refute stored_svg =~ "javascript:"
  end

  test "the Project boundary preserves canonical blob materialization semantics" do
    user = user_fixture()
    project = project_fixture(user)
    content = "project-owned asset restore"
    hash = BlobStore.compute_hash(content)
    blob_key = BlobStore.blob_key(project.id, hash, "png")

    assert {:ok, ^blob_key} = BlobStore.ensure_blob(project.id, hash, "png", content)

    metadata = %{
      "filename" => "restored.png",
      "content_type" => "image/png",
      "size" => byte_size(content)
    }

    assert {:ok, asset} =
             Projects.create_asset_from_blob(
               project.id,
               user.id,
               hash,
               blob_key,
               metadata
             )

    cleanup_asset(project.id, asset, "png")

    assert asset.project_id == project.id
    assert asset.uploaded_by_id == user.id
    assert asset.blob_hash == hash
    assert asset.filename == "restored.png"
    assert asset.content_type == "image/png"
    assert asset.size == byte_size(content)
  end

  test "the Project boundary preserves materialization scope and transaction contracts" do
    project = project_fixture(user_fixture())

    assert {:ok, :materialized} =
             Projects.run_asset_materialization_scope(
               [pre_materialized_assets: true],
               fn opts ->
                 assert opts[:pre_materialized_assets] == true
                 {:ok, :materialized}
               end
             )

    assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
             Storyarn.Repo.transaction(fn ->
               Projects.with_asset_copy_tracker([asset_mode: :copy], fn _opts ->
                 flunk("copy callback must not run without the caller-owned transaction tracker")
               end)
             end)

    assert {:error, :materialization_failed} =
             Projects.with_project_storage_lock(project.id, fn ->
               {:error, :materialization_failed}
             end)
  end

  defp cleanup_asset(project_id, asset, extension) do
    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(BlobStore.blob_key(project_id, asset.blob_hash, extension))
    end)
  end
end

defmodule Storyarn.Projects.ProjectAssets do
  @moduledoc false

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Versioning.AssetMaterializationScope
  alias Storyarn.Projects.Versioning.MaterializationHelpers

  def list_image_asset_ids(project_id) do
    Assets.list_asset_ids(project_id, images_only: true)
  end

  def get_asset(project_id, asset_id), do: Assets.get_asset(project_id, asset_id)

  def upload_asset(path, entry, project_id, uploaded_by_id, opts \\ []) do
    Assets.upload_and_create_asset(
      path,
      entry,
      project_id,
      uploaded_by_id,
      opts
    )
  end

  def create_generated_asset(project_id, binary, attrs, uploaded_by_id \\ nil) do
    create_binary_asset(project_id, binary, attrs, uploaded_by_id)
  end

  def create_binary_asset(project_id, binary, attrs, uploaded_by_id \\ nil) do
    Assets.upload_binary_and_create_asset(
      binary,
      attrs,
      project_id,
      uploaded_by_id
    )
  end

  def create_sanitized_svg_asset(project_id, binary, attrs, uploaded_by_id \\ nil) do
    Assets.upload_sanitized_svg_and_create_asset(
      binary,
      attrs,
      project_id,
      uploaded_by_id
    )
  end

  def create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts \\ []) do
    BlobStore.create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts)
  end

  def run_asset_materialization_scope(opts, fun), do: AssetMaterializationScope.run(opts, fun)

  def with_asset_copy_tracker(opts, fun), do: MaterializationHelpers.with_asset_copy_tracker(opts, fun)

  def with_project_storage_lock(project_id, fun) do
    MaterializationHelpers.with_project_storage_lock(project_id, fun)
  end
end

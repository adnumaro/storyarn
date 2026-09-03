defmodule Storyarn.Projects.Assets do
  @moduledoc """
  Public capability facade for Project-owned assets.

  Queries, ordinary commands, trash, uploads, blob verification and exact
  reconstitution are routed through explicit use-case modules. Stable function
  names remain here for callers and persisted worker contracts.
  """

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.AssetBlobVerification
  alias Storyarn.Projects.Assets.AssetOperations
  alias Storyarn.Projects.Assets.AssetReconstitution
  alias Storyarn.Projects.Assets.AssetTrashLifecycle
  alias Storyarn.Projects.Assets.AssetUploadLifecycle
  alias Storyarn.Projects.Assets.Commands.AssetCommands
  alias Storyarn.Projects.Assets.Commands.AssetRegistration
  alias Storyarn.Projects.Assets.ImageProcessor
  alias Storyarn.Projects.Assets.Queries.AssetQueries
  alias Storyarn.Projects.Assets.Queries.AssetUsageQueries
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Assets.StorageKey
  alias Storyarn.Projects.Assets.StorageMultipartInventory
  alias Storyarn.Projects.Assets.UploadPolicy
  alias Storyarn.Projects.Versioning

  defdelegate list_assets(project_id, opts \\ []), to: AssetQueries
  defdelegate list_asset_ids(project_id, opts \\ []), to: AssetQueries
  defdelegate get_asset(asset_id), to: AssetQueries
  defdelegate authorize_download(scope, asset_id), to: AssetQueries
  defdelegate get_asset(project_id, asset_id), to: AssetQueries
  defdelegate get_asset!(project_id, asset_id), to: AssetQueries
  defdelegate get_asset_by_key(project_id, key), to: AssetQueries
  defdelegate get_trashed_asset(project_id, asset_id), to: AssetQueries
  defdelegate count_assets_by_type(project_id), to: AssetQueries
  defdelegate total_storage_size(project_id), to: AssetQueries
  defdelegate get_asset_usages(project_id, asset_id), to: AssetUsageQueries
  defdelegate get_asset_family_usages(project_id, asset_id), to: AssetUsageQueries
  defdelegate count_asset_usages(project_id, asset_id), to: AssetUsageQueries
  defdelegate list_assets_for_export(project_id), to: AssetQueries
  defdelegate count_assets(project_id, opts \\ []), to: AssetQueries
  defdelegate list_image_asset_ids(project_id), to: AssetQueries

  defdelegate create_asset(project, user, attrs), to: AssetCommands
  defdelegate create_asset(project, attrs), to: AssetCommands
  defdelegate update_asset(asset, attrs), to: AssetCommands
  defdelegate delete_asset(asset), to: AssetCommands
  defdelegate change_asset(asset, attrs \\ %{}), to: AssetCommands

  @doc false
  defdelegate register_uploaded_asset(project_id, uploaded_by_id, attrs, upload_kind),
    to: AssetRegistration

  @doc false
  defdelegate register_materialized_asset(project_id, uploaded_by_id, attrs),
    to: AssetRegistration

  @doc false
  defdelegate link_asset_variant(project_id, original_asset_id, variant_asset_id),
    to: AssetRegistration

  defdelegate move_asset_to_trash(project_id, asset_id, actor_id), to: AssetTrashLifecycle
  defdelegate move_assets_to_trash_locked(project_id, actor_id, asset_ids, opts \\ []), to: AssetTrashLifecycle

  defdelegate restore_trashed_asset(project_id, asset_id, expected_generation, actor_id),
    to: AssetTrashLifecycle

  defdelegate purge_trashed_asset(project_id, asset_id, expected_generation, actor_id),
    to: AssetTrashLifecycle

  defdelegate purge_trashed_asset(project_id, asset_id, expected_generation, actor_id, opts),
    to: AssetTrashLifecycle

  defdelegate purge_trashed_assets(project_id, candidates, actor_id), to: AssetTrashLifecycle
  defdelegate prepare_parent_hard_delete_locked(workspace_id, project_scope), to: AssetTrashLifecycle
  defdelegate lock_active_asset_references_for_restore(project_id, owner_ids), to: AssetTrashLifecycle

  defdelegate upload_and_create_asset(path, entry, project, user, opts \\ []), to: AssetUploadLifecycle
  defdelegate inspect_upload(project, attrs), to: AssetUploadLifecycle
  defdelegate inspect_authorized_upload(scope, project_id, attrs), to: AssetUploadLifecycle
  defdelegate materialize_upload_variant(project, user, attrs), to: AssetUploadLifecycle

  defdelegate materialize_authorized_upload_variant(scope, project_id, attrs),
    to: AssetUploadLifecycle

  defdelegate upload_binary_for_purpose(binary_data, attrs, project, user \\ nil),
    to: AssetUploadLifecycle

  defdelegate upload_authorized_binary_for_purpose(scope, project_id, binary_data, attrs),
    to: AssetUploadLifecycle

  defdelegate upload_binary_and_create_asset(binary_data, attrs, project, user \\ nil),
    to: AssetUploadLifecycle

  defdelegate upload_authorized_binary(scope, project_id, binary_data, attrs),
    to: AssetUploadLifecycle

  defdelegate upload_sanitized_svg_and_create_asset(binary_data, attrs, project, user \\ nil),
    to: AssetUploadLifecycle

  defdelegate upload_asset(path, entry, project_id, uploaded_by_id, opts \\ []),
    to: AssetUploadLifecycle

  defdelegate create_generated_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: AssetUploadLifecycle

  defdelegate create_binary_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: AssetUploadLifecycle

  defdelegate create_sanitized_svg_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: AssetUploadLifecycle

  defdelegate create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts \\ []),
    to: AssetUploadLifecycle

  defdelegate ensure_active_asset_blobs(project_id), to: AssetBlobVerification
  defdelegate ensure_asset_blobs(assets), to: AssetBlobVerification
  defdelegate ensure_snapshot_asset_blobs(project_id, blob_specs), to: AssetBlobVerification

  defdelegate with_import_capacity(project, total_bytes, fun), to: AssetReconstitution
  defdelegate import_asset(project, attrs), to: AssetReconstitution
  defdelegate import_snapshot_asset(project, uploaded_by_id, attrs), to: AssetReconstitution

  defdelegate update_imported_snapshot_asset_locked(project, asset, metadata),
    to: AssetReconstitution

  defdelegate import_snapshot_assets_locked(project, uploaded_by_id, attrs_list),
    to: AssetReconstitution

  defdelegate update_imported_snapshot_assets_locked(project, updates), to: AssetReconstitution

  defdelegate update_imported_snapshot_assets_exact_locked(project, updates),
    to: AssetReconstitution

  defdelegate generate_key(project, filename), to: AssetOperations
  defdelegate thumbnail_key(asset_key), to: AssetOperations
  defdelegate sanitize_filename(filename), to: AssetOperations

  defdelegate display_url(asset), to: Asset
  defdelegate image?(asset), to: Asset
  defdelegate audio?(asset), to: Asset
  defdelegate allowed_content_type?(content_type), to: Asset

  defdelegate storage_upload(key, data, content_type), to: Storage, as: :upload
  defdelegate storage_delete(key), to: Storage, as: :delete
  defdelegate storage_download(key), to: Storage, as: :download
  defdelegate image_processor_available?(), to: ImageProcessor, as: :available?
  defdelegate image_processor_get_dimensions(path), to: ImageProcessor, as: :get_dimensions

  defdelegate run_asset_materialization_scope(opts, fun), to: Versioning
  defdelegate with_asset_copy_tracker(opts, fun), to: Versioning
  defdelegate with_project_storage_lock(project_id, fun), to: Versioning
  defdelegate parse_asset_upload_purpose(purpose), to: UploadPolicy, as: :parse_purpose
  defdelegate asset_upload_purpose_supported?(purpose), to: UploadPolicy, as: :supported_purpose?
  defdelegate external_project_storage?(), to: Storage, as: :external_upload?
  defdelegate storage_provider_namespace_fingerprint(), to: Storage, as: :namespace_fingerprint
  defdelegate canonical_storage_key?(key), to: StorageKey, as: :canonical?
  defdelegate project_asset_route_key?(project_id, key), to: StorageKey
  defdelegate project_media_route_key?(project_id, key), to: StorageKey
  defdelegate delete_storage_keys(cleanup_targets), to: StorageCompensation
  defdelegate persist_cleanup_request(cleanup_targets), to: StorageCompensation
  defdelegate enqueue_due_cleanup_request_jobs(), to: StorageCompensation
  defdelegate retry_persisted_cleanup_request_by_id(cleanup_request_id), to: StorageCompensation
  defdelegate emit_storage_cleanup_request_backlog(), to: StorageCompensation, as: :emit_cleanup_request_backlog
  defdelegate inspect_storage_multipart_inventory(), to: StorageMultipartInventory, as: :inspect
  defdelegate retry_persisted_cleanup_requests(), to: StorageCompensation
end

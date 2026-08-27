defmodule Storyarn.Projects.Assets.AssetUploadLifecycle do
  @moduledoc false

  alias Storyarn.Projects.Assets.AssetOperations

  defdelegate upload_and_create_asset(path, entry, project, user, opts \\ []), to: AssetOperations
  defdelegate inspect_upload(project, attrs), to: AssetOperations
  defdelegate inspect_authorized_upload(scope, project_id, attrs), to: AssetOperations
  defdelegate materialize_upload_variant(project, user, attrs), to: AssetOperations
  defdelegate materialize_authorized_upload_variant(scope, project_id, attrs), to: AssetOperations

  defdelegate upload_binary_for_purpose(binary_data, attrs, project, user \\ nil),
    to: AssetOperations

  defdelegate upload_authorized_binary_for_purpose(scope, project_id, binary_data, attrs),
    to: AssetOperations

  defdelegate upload_binary_and_create_asset(binary_data, attrs, project, user \\ nil),
    to: AssetOperations

  defdelegate upload_authorized_binary(scope, project_id, binary_data, attrs), to: AssetOperations

  defdelegate upload_sanitized_svg_and_create_asset(binary_data, attrs, project, user \\ nil),
    to: AssetOperations

  defdelegate upload_asset(path, entry, project_id, uploaded_by_id, opts \\ []), to: AssetOperations
  defdelegate create_generated_asset(project_id, binary, attrs, uploaded_by_id \\ nil), to: AssetOperations
  defdelegate create_binary_asset(project_id, binary, attrs, uploaded_by_id \\ nil), to: AssetOperations

  defdelegate create_sanitized_svg_asset(project_id, binary, attrs, uploaded_by_id \\ nil),
    to: AssetOperations

  defdelegate create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata, opts \\ []),
    to: AssetOperations
end

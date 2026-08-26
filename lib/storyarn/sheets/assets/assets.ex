defmodule Storyarn.Sheets.Assets do
  @moduledoc "Sheet-owned asset reads, writes, restore references, and storage coordination."

  alias Storyarn.Sheets.Assets.Commands.Assets, as: AssetCommands
  alias Storyarn.Sheets.Assets.Commands.References
  alias Storyarn.Sheets.Assets.Data.AssetRecord
  alias Storyarn.Sheets.Assets.Queries.Catalog

  defdelegate list_assets(project_id, opts \\ []), to: Catalog
  defdelegate get_asset(project_id, asset_id), to: Catalog

  defdelegate allowed_asset_content_type?(content_type),
    to: AssetRecord,
    as: :allowed_content_type?

  defdelegate upload_asset(path, entry, project, user, opts \\ []), to: AssetCommands
  defdelegate create_generated_asset(binary, attrs, project, user \\ nil), to: AssetCommands
  defdelegate create_binary_asset(binary, attrs, project, user \\ nil), to: AssetCommands
  defdelegate create_sanitized_svg_asset(binary, attrs, project, user \\ nil), to: AssetCommands

  @doc false
  defdelegate run_asset_materialization_scope(opts, fun), to: AssetCommands

  @doc false
  defdelegate with_asset_copy_tracker(opts, fun), to: AssetCommands

  @doc false
  defdelegate with_project_storage_lock(project_id, fun), to: AssetCommands

  @doc false
  defdelegate create_version_asset_from_storage(
                project_id,
                uploaded_by_id,
                blob_hash,
                source_key,
                metadata,
                opts \\ []
              ),
              to: AssetCommands

  @doc false
  defdelegate lock_active_for_restore(project_id, owner_ids), to: References
end

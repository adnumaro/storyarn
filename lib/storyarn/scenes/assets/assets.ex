defmodule Storyarn.Scenes.Assets do
  @moduledoc """
  Scene asset boundary for catalog reads, materialization and zone imagery.

  Storage and image processing remain private adapters; callers depend on this
  capability rather than their technical implementations.
  """

  alias Storyarn.Scenes.Assets.Commands.Assets, as: AssetCommands
  alias Storyarn.Scenes.Assets.Commands.ZoneImage
  alias Storyarn.Scenes.Assets.Queries.Catalog

  defdelegate list_image_asset_ids(project_id), to: Catalog
  defdelegate get_asset(project_id, asset_id), to: Catalog
  defdelegate asset_options(project_id, kind, opts \\ []), to: Catalog
  defdelegate initial_asset_options(project_id, kind, selected_ids), to: Catalog

  defdelegate upload_asset(path, entry, project, user, opts \\ []), to: AssetCommands
  defdelegate create_generated_asset(binary, attrs, project, user \\ nil), to: AssetCommands
  defdelegate create_binary_asset(binary, attrs, project, user \\ nil), to: AssetCommands
  defdelegate create_sanitized_svg_asset(binary, attrs, project, user \\ nil), to: AssetCommands

  defdelegate run_asset_materialization_scope(opts, fun), to: AssetCommands
  defdelegate with_asset_copy_tracker(opts, fun), to: AssetCommands
  defdelegate with_project_storage_lock(project_id, fun), to: AssetCommands

  defdelegate create_version_asset_from_storage(
                project_id,
                uploaded_by_id,
                blob_hash,
                source_key,
                metadata,
                opts \\ []
              ),
              to: AssetCommands

  defdelegate extract_zone_image(parent_scene, zone, project), to: ZoneImage, as: :extract
  defdelegate zone_bounding_box(vertices), to: ZoneImage, as: :bounding_box

  defdelegate normalize_zone_vertices(vertices),
    to: ZoneImage,
    as: :normalize_vertices_to_bbox
end

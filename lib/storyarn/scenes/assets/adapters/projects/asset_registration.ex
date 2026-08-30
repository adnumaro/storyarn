defmodule Storyarn.Scenes.Assets.Adapters.Projects.AssetRegistration do
  @moduledoc """
  Narrow Scene adapter for Projects-owned asset-row commands.

  Scene workflows retain upload, quota, storage and compensation concerns;
  this adapter exposes only the asset persistence intents they require.
  """

  alias Storyarn.Projects

  @spec register_uploaded_asset(pos_integer(), pos_integer() | nil, map(), :generic | :sanitized_svg) ::
          {:ok, %{asset_id: pos_integer(), project_id: pos_integer()}} | {:error, term()}
  def register_uploaded_asset(project_id, uploaded_by_id, attrs, upload_kind) do
    Projects.register_uploaded_asset(project_id, uploaded_by_id, attrs, upload_kind)
  end

  @spec register_materialized_asset(pos_integer(), pos_integer() | nil, map()) ::
          {:ok, %{asset_id: pos_integer(), project_id: pos_integer()}} | {:error, term()}
  def register_materialized_asset(project_id, uploaded_by_id, attrs) do
    Projects.register_materialized_asset(project_id, uploaded_by_id, attrs)
  end

  @spec link_asset_variant(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, %{asset_id: pos_integer(), project_id: pos_integer()}} | {:error, term()}
  def link_asset_variant(project_id, original_id, variant_id) do
    Projects.link_asset_variant(project_id, original_id, variant_id)
  end
end

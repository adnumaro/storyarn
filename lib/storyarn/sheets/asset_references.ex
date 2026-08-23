defmodule Storyarn.Sheets.AssetReferences do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.ProjectReferenceIntegrity
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  @allowed_owner_keys [:sheet_ids, :block_ids]

  @spec lock_active_for_restore(pos_integer(), keyword()) :: :ok | {:error, term()}
  def lock_active_for_restore(project_id, owner_ids)
      when is_integer(project_id) and project_id > 0 and is_list(owner_ids) do
    with {:ok, normalized} <- normalize_owner_ids(owner_ids),
         specs = sheet_reference_specs(normalized.sheet_ids) ++ block_reference_specs(normalized.block_ids),
         {:ok, _asset_ids} <- ProjectReferenceIntegrity.lock_active_references(project_id, specs) do
      :ok
    end
  end

  def lock_active_for_restore(_project_id, _owner_ids), do: {:error, :invalid_asset_restore_owners}

  defp normalize_owner_ids(owner_ids) do
    with true <- Keyword.keyword?(owner_ids),
         true <- Enum.all?(Keyword.keys(owner_ids), &(&1 in @allowed_owner_keys)),
         normalized =
           Map.new(@allowed_owner_keys, fn key ->
             ids = owner_ids |> Keyword.get(key, []) |> List.wrap()
             {key, Enum.uniq(ids)}
           end),
         true <- Enum.all?(normalized, fn {_key, ids} -> Enum.all?(ids, &(is_integer(&1) and &1 > 0)) end) do
      {:ok, normalized}
    else
      _invalid -> {:error, :invalid_asset_restore_owners}
    end
  end

  defp sheet_reference_specs([]), do: []

  defp sheet_reference_specs(sheet_ids) do
    banners =
      Repo.all(
        from(sheet in Sheet,
          where: sheet.id in ^sheet_ids,
          select: {sheet.id, sheet.banner_asset_id}
        )
      )

    avatars =
      Repo.all(
        from(avatar in SheetAvatar,
          where: avatar.sheet_id in ^sheet_ids,
          select: {avatar.id, avatar.asset_id}
        )
      )

    galleries =
      Repo.all(
        from(image in BlockGalleryImage,
          join: block in Block,
          on: block.id == image.block_id,
          where: block.sheet_id in ^sheet_ids and is_nil(block.deleted_at),
          select: {image.id, image.asset_id}
        )
      )

    Enum.map(banners, fn {sheet_id, asset_id} ->
      {:asset, {:sheet, sheet_id, :banner_asset_id}, asset_id}
    end) ++
      Enum.map(avatars, fn {avatar_id, asset_id} ->
        {:asset, {:sheet_avatar, avatar_id, :asset_id}, asset_id}
      end) ++
      Enum.map(galleries, fn {image_id, asset_id} ->
        {:asset, {:block_gallery_image, image_id, :asset_id}, asset_id}
      end)
  end

  defp block_reference_specs([]), do: []

  defp block_reference_specs(block_ids) do
    from(image in BlockGalleryImage,
      where: image.block_id in ^block_ids,
      select: {image.id, image.asset_id}
    )
    |> Repo.all()
    |> Enum.map(fn {image_id, asset_id} ->
      {:asset, {:block_gallery_image, image_id, :asset_id}, asset_id}
    end)
  end
end

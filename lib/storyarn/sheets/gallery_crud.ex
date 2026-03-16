defmodule Storyarn.Sheets.GalleryCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Sheets.{Block, BlockGalleryImage, Sheet}

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc "Lists all gallery images for a block, ordered by position, with asset preloaded."
  def list_gallery_images(block_id) do
    from(gi in BlockGalleryImage,
      where: gi.block_id == ^block_id,
      order_by: [asc: gi.position],
      preload: [:asset]
    )
    |> Repo.all()
  end

  @doc "Gets a gallery image by ID with asset preloaded."
  def get_gallery_image(id) do
    BlockGalleryImage
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  @doc "Gets the first gallery image for a sheet (any gallery block)."
  def get_first_gallery_image(sheet_id) do
    from(gi in BlockGalleryImage,
      join: b in Block,
      on: gi.block_id == b.id,
      where: b.sheet_id == ^sheet_id and b.type == "gallery" and is_nil(b.deleted_at),
      order_by: [asc: b.position, asc: gi.position],
      limit: 1,
      preload: [:asset]
    )
    |> Repo.one()
  end

  # ===========================================================================
  # Create
  # ===========================================================================

  @doc "Adds a single image to a gallery block."
  def add_gallery_image(%Block{id: block_id, type: "gallery"}, asset_id) do
    position = next_position(block_id)

    %BlockGalleryImage{block_id: block_id}
    |> BlockGalleryImage.create_changeset(%{asset_id: asset_id, position: position})
    |> Repo.insert()
    |> tap(fn
      {:ok, _gallery_image} -> Repo.get(Block, block_id) |> Localization.extract_block()
      _ -> :ok
    end)
  end

  @doc "Adds multiple images to a gallery block in batch."
  def add_gallery_images(%Block{id: _block_id, type: "gallery"} = block, asset_ids)
      when is_list(asset_ids) do
    results =
      Enum.reduce_while(asset_ids, {:ok, []}, fn asset_id, {:ok, acc} ->
        case add_gallery_image(block, asset_id) do
          {:ok, gi} -> {:cont, {:ok, acc ++ [gi]}}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)

    results
  end

  # ===========================================================================
  # Update
  # ===========================================================================

  @doc "Updates a gallery image's label and description."
  def update_gallery_image(%BlockGalleryImage{} = gallery_image, attrs) do
    gallery_image
    |> BlockGalleryImage.update_changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, _updated_image} -> Repo.get(Block, gallery_image.block_id) |> Localization.extract_block()
      _ -> :ok
    end)
  end

  # ===========================================================================
  # Delete
  # ===========================================================================

  @doc "Removes a gallery image (hard delete)."
  def remove_gallery_image(gallery_image_id) do
    case Repo.get(BlockGalleryImage, gallery_image_id) do
      nil ->
        {:error, :not_found}

      gi ->
        Repo.delete(gi)
        |> tap(fn
          {:ok, _deleted_image} -> Repo.get(Block, gi.block_id) |> Localization.extract_block()
          _ -> :ok
        end)
    end
  end

  # ===========================================================================
  # Reorder
  # ===========================================================================

  @doc "Reorders gallery images within a block."
  def reorder_gallery_images(block_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(gi in BlockGalleryImage,
          where: gi.id == ^id and gi.block_id == ^block_id
        )
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ===========================================================================
  # Batch loading (for ContentTab)
  # ===========================================================================

  @doc "Batch-loads gallery images for a project, grouped by sheet_id."
  def batch_load_gallery_data_by_sheet(project_id) do
    from(gi in BlockGalleryImage,
      join: b in Block,
      on: gi.block_id == b.id,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and b.type == "gallery" and is_nil(b.deleted_at) and
          is_nil(s.deleted_at),
      order_by: [asc: gi.position],
      select: {b.sheet_id, gi},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _gi} -> sheet_id end, fn {_, gi} -> gi end)
  end

  @doc "Batch-loads gallery images for multiple block IDs."
  def batch_load_gallery_data(block_ids) when is_list(block_ids) do
    from(gi in BlockGalleryImage,
      where: gi.block_id in ^block_ids,
      order_by: [asc: gi.block_id, asc: gi.position],
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp next_position(block_id) do
    from(gi in BlockGalleryImage,
      where: gi.block_id == ^block_id,
      select: coalesce(max(gi.position), -1)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

end

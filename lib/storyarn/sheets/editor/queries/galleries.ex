defmodule Storyarn.Sheets.Editor.Queries.Galleries do
  @moduledoc """
  Read-only access to gallery images for Sheet editor and batch consumers.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet

  def list(block_id) do
    Repo.all(
      from(image in BlockGalleryImage,
        where: image.block_id == ^block_id,
        order_by: [asc: image.position],
        preload: [:asset]
      )
    )
  end

  def get(id) do
    BlockGalleryImage
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  def get_for_sheet(sheet_id, id) do
    Repo.one(
      from(image in BlockGalleryImage,
        join: block in Block,
        on: image.block_id == block.id,
        where: image.id == ^id and block.sheet_id == ^sheet_id,
        preload: [:asset]
      )
    )
  end

  def get_first_for_sheet(sheet_id) do
    Repo.one(
      from(image in BlockGalleryImage,
        join: block in Block,
        on: image.block_id == block.id,
        where: block.sheet_id == ^sheet_id and block.type == "gallery" and is_nil(block.deleted_at),
        order_by: [asc: block.position, asc: image.position],
        limit: 1,
        preload: [:asset]
      )
    )
  end

  def batch_by_sheet(project_id) do
    from(image in BlockGalleryImage,
      join: block in Block,
      on: image.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and block.type == "gallery" and is_nil(block.deleted_at) and
          is_nil(sheet.deleted_at),
      order_by: [asc: image.position],
      select: {block.sheet_id, image},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _image} -> sheet_id end, fn {_sheet_id, image} -> image end)
  end

  def batch_by_blocks(block_ids) when is_list(block_ids) do
    from(image in BlockGalleryImage,
      where: image.block_id in ^block_ids,
      order_by: [asc: image.block_id, asc: image.position],
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end
end

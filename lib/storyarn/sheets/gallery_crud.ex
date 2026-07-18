defmodule Storyarn.Sheets.GalleryCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc "Lists all gallery images for a block, ordered by position, with asset preloaded."
  def list_gallery_images(block_id) do
    Repo.all(
      from(gi in BlockGalleryImage, where: gi.block_id == ^block_id, order_by: [asc: gi.position], preload: [:asset])
    )
  end

  @doc "Gets a gallery image by ID with asset preloaded."
  def get_gallery_image(id) do
    BlockGalleryImage
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  @doc "Gets a gallery image by ID, verifying it belongs to a block owned by the given sheet."
  def get_gallery_image_for_sheet(sheet_id, id) do
    Repo.one(
      from(gi in BlockGalleryImage,
        join: b in Block,
        on: gi.block_id == b.id,
        where: gi.id == ^id and b.sheet_id == ^sheet_id,
        preload: [:asset]
      )
    )
  end

  @doc "Gets the first gallery image for a sheet (any gallery block)."
  def get_first_gallery_image(sheet_id) do
    Repo.one(
      from(gi in BlockGalleryImage,
        join: b in Block,
        on: gi.block_id == b.id,
        where: b.sheet_id == ^sheet_id and b.type == "gallery" and is_nil(b.deleted_at),
        order_by: [asc: b.position, asc: gi.position],
        limit: 1,
        preload: [:asset]
      )
    )
  end

  # ===========================================================================
  # Create
  # ===========================================================================

  @doc "Adds a single image to a gallery block."
  def add_gallery_image(%Block{id: block_id, type: "gallery"}, asset_id) do
    Repo.transaction(fn ->
      {project_id, sheet_id} = fetch_gallery_owner!(block_id)
      lock_active_project!(project_id)
      sheet = lock_active_sheet!(sheet_id, project_id)
      _block = lock_active_gallery!(block_id, sheet.id)
      normalized_asset_id = sheet.project_id |> lock_gallery_assets!([asset_id]) |> hd()

      insert_gallery_image!(block_id, normalized_asset_id)
    end)
  end

  @doc "Adds multiple images to a gallery block in batch."
  def add_gallery_images(%Block{id: block_id, type: "gallery"}, asset_ids) when is_list(asset_ids) do
    Repo.transaction(fn ->
      {project_id, sheet_id} = fetch_gallery_owner!(block_id)
      lock_active_project!(project_id)
      sheet = lock_active_sheet!(sheet_id, project_id)
      _block = lock_active_gallery!(block_id, sheet.id)
      normalized_asset_ids = lock_gallery_assets!(sheet.project_id, asset_ids)

      Enum.map(normalized_asset_ids, &insert_gallery_image!(block_id, &1))
    end)
  end

  # ===========================================================================
  # Update
  # ===========================================================================

  @doc "Updates a gallery image's label and description."
  def update_gallery_image(%BlockGalleryImage{} = gallery_image, attrs) do
    Repo.transaction(fn ->
      persisted_image =
        lock_active_gallery_image_writer!(
          gallery_image.id,
          expected_block_id: gallery_image.block_id
        )

      case persisted_image
           |> BlockGalleryImage.update_changeset(attrs)
           |> Repo.update() do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ===========================================================================
  # Delete
  # ===========================================================================

  @doc "Removes a gallery image (hard delete), verifying it belongs to a block owned by the given sheet."
  def remove_gallery_image(sheet_id, gallery_image_id)
      when is_integer(sheet_id) and sheet_id > 0 and is_integer(gallery_image_id) and gallery_image_id > 0 do
    Repo.transaction(fn ->
      image =
        lock_active_gallery_image_writer!(
          gallery_image_id,
          expected_sheet_id: sheet_id
        )

      case Repo.delete(image) do
        {:ok, deleted} -> deleted
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def remove_gallery_image(_sheet_id, _gallery_image_id), do: {:error, :not_found}

  # ===========================================================================
  # Reorder
  # ===========================================================================

  @doc "Reorders gallery images within a block."
  def reorder_gallery_images(block_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      normalized_ids = normalize_reorder_ids!(ordered_ids)
      {project_id, sheet_id} = fetch_gallery_owner!(block_id)

      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)
      lock_active_gallery!(block_id, sheet_id)
      locked_ids = lock_gallery_image_ids!(block_id)
      ensure_exact_reorder_set!(normalized_ids, locked_ids, ordered_ids)

      normalized_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        Repo.update_all(from(gi in BlockGalleryImage, where: gi.id == ^id and gi.block_id == ^block_id),
          set: [position: index]
        )
      end)
    end)
  end

  def reorder_gallery_images(_block_id, ordered_ids), do: {:error, {:invalid_gallery_reorder, ordered_ids}}

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

  defp fetch_gallery_owner!(block_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id and block.type == "gallery",
        select: {sheet.project_id, sheet.id}
      )
    ) || Repo.rollback(:gallery_not_found)
  end

  defp fetch_gallery_image_owner!(image_id) do
    Repo.one(
      from(image in BlockGalleryImage,
        join: block in Block,
        on: block.id == image.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: image.id == ^image_id,
        select: {sheet.project_id, sheet.id, block.id}
      )
    ) || Repo.rollback(:not_found)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_active_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in Sheet,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Sheet{} = sheet -> sheet
      nil -> Repo.rollback(:gallery_not_active)
    end
  end

  defp lock_active_gallery!(block_id, sheet_id) do
    case Repo.one(
           from(block in Block,
             where:
               block.id == ^block_id and block.sheet_id == ^sheet_id and
                 block.type == "gallery" and is_nil(block.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Block{} = block -> block
      nil -> Repo.rollback(:gallery_not_active)
    end
  end

  defp lock_gallery_image_ids!(block_id) do
    Repo.all(
      from(image in BlockGalleryImage,
        where: image.block_id == ^block_id,
        order_by: [asc: image.id],
        lock: "FOR UPDATE",
        select: image.id
      )
    )
  end

  defp lock_active_gallery_image_writer!(image_id, opts) do
    {project_id, sheet_id, block_id} = fetch_gallery_image_owner!(image_id)

    if expected_sheet_id = Keyword.get(opts, :expected_sheet_id) do
      if expected_sheet_id != sheet_id, do: Repo.rollback(:not_found)
    end

    if expected_block_id = Keyword.get(opts, :expected_block_id) do
      if expected_block_id != block_id, do: Repo.rollback(:not_found)
    end

    lock_active_project!(project_id)
    lock_active_sheet!(sheet_id, project_id)
    lock_active_gallery!(block_id, sheet_id)

    Repo.one(
      from(image in BlockGalleryImage,
        where: image.id == ^image_id and image.block_id == ^block_id,
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:not_found)
  end

  defp normalize_reorder_ids!(ordered_ids) do
    if Enum.all?(ordered_ids, &(is_integer(&1) and &1 > 0)) and
         length(ordered_ids) == length(Enum.uniq(ordered_ids)) do
      ordered_ids
    else
      Repo.rollback({:invalid_gallery_reorder, ordered_ids})
    end
  end

  defp ensure_exact_reorder_set!(ordered_ids, locked_ids, original_ids) do
    if Enum.sort(ordered_ids) != locked_ids do
      Repo.rollback({:invalid_gallery_reorder, original_ids})
    end
  end

  defp lock_gallery_assets!(project_id, asset_ids) do
    specs = Enum.map(asset_ids, &{:asset, :gallery_asset_id, &1})

    with {:ok, normalized_ids} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, specs),
         :ok <- ensure_gallery_assets_present(normalized_ids),
         :ok <- ensure_gallery_asset_content_types(project_id, normalized_ids) do
      normalized_ids
    else
      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp ensure_gallery_assets_present(asset_ids) do
    if Enum.any?(asset_ids, &is_nil/1),
      do: {:error, {:invalid_project_reference, :gallery_asset_id, nil}},
      else: :ok
  end

  defp ensure_gallery_asset_content_types(project_id, asset_ids) do
    asset_ids
    |> Enum.map(fn asset_id ->
      ProjectReferenceIntegrity.ensure_locked_asset_content_type(
        project_id,
        asset_id,
        :gallery_asset_id,
        "image/%"
      )
    end)
    |> Enum.find(:ok, &match?({:error, _reason}, &1))
  end

  defp insert_gallery_image!(block_id, asset_id) do
    position = next_position(block_id)

    case %BlockGalleryImage{block_id: block_id}
         |> BlockGalleryImage.create_changeset(%{
           asset_id: asset_id,
           position: position
         })
         |> Repo.insert() do
      {:ok, gallery_image} -> gallery_image
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end

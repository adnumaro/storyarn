defmodule Storyarn.Flows.EditorCatalog do
  @moduledoc """
  Consumer-owned read model for the Flow editor's Sheet and Scene catalog.

  The records in `Storyarn.Flows.Persistence` map the shared tables directly.
  This module converts them into the small presentation shape consumed by the
  Flow editor so neither foreign schemas nor storage details cross the Flows
  boundary.
  """

  import Ecto.Query

  alias Storyarn.Flows.Persistence.BlockRecord
  alias Storyarn.Flows.Persistence.GalleryImageRecord
  alias Storyarn.Flows.Persistence.SceneRecord
  alias Storyarn.Flows.Persistence.SheetRecord
  alias Storyarn.Repo

  @type media_ref :: %{id: integer(), filename: String.t() | nil}
  @type avatar :: %{
          id: integer(),
          name: String.t() | nil,
          position: integer(),
          is_default: boolean(),
          asset: media_ref() | nil
        }
  @type sheet :: %{
          id: integer(),
          name: String.t() | nil,
          color: String.t() | nil,
          banner_asset: media_ref() | nil,
          avatars: [avatar()]
        }
  @type gallery_image :: %{
          id: integer(),
          label: String.t() | nil,
          asset: media_ref() | nil
        }
  @type scene_option :: %{id: integer(), name: String.t() | nil}
  @type t :: %{
          sheets: [sheet()],
          gallery_by_sheet: %{optional(integer()) => [gallery_image()]},
          scenes: [scene_option()]
        }

  @doc "Loads every foreign read model needed to start the Flow editor."
  @spec load(integer()) :: t()
  def load(project_id) do
    %{
      sheets: load_sheets(project_id),
      gallery_by_sheet: load_gallery_by_sheet(project_id),
      scenes: load_scenes(project_id)
    }
  end

  defp load_sheets(project_id) do
    from(sheet in SheetRecord,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: sheet.position, asc: sheet.name],
      preload: [:banner_asset, avatars: :asset]
    )
    |> Repo.all()
    |> Enum.map(&to_sheet/1)
  end

  defp load_gallery_by_sheet(project_id) do
    from(image in GalleryImageRecord,
      join: block in BlockRecord,
      on: image.block_id == block.id,
      join: sheet in SheetRecord,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and block.type == "gallery" and
          is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
      order_by: [asc: image.position],
      select: {block.sheet_id, image},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _image} -> sheet_id end, fn {_sheet_id, image} ->
      to_gallery_image(image)
    end)
  end

  defp load_scenes(project_id) do
    Repo.all(
      from(scene in SceneRecord,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        order_by: [asc: scene.position, asc: scene.name, asc: scene.id],
        select: %{id: scene.id, name: scene.name}
      )
    )
  end

  defp to_sheet(sheet) do
    %{
      id: sheet.id,
      name: sheet.name,
      color: sheet.color,
      banner_asset: media_ref(sheet.banner_asset),
      avatars: Enum.map(sheet.avatars, &to_avatar/1)
    }
  end

  defp to_avatar(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      position: avatar.position,
      is_default: avatar.is_default,
      asset: media_ref(avatar.asset)
    }
  end

  defp to_gallery_image(image) do
    %{id: image.id, label: image.label, asset: media_ref(image.asset)}
  end

  defp media_ref(nil), do: nil

  defp media_ref(asset) do
    id =
      case asset.metadata do
        %{"web_asset_id" => web_asset_id} when is_integer(web_asset_id) -> web_asset_id
        _metadata -> asset.id
      end

    %{id: id, filename: asset.filename}
  end
end

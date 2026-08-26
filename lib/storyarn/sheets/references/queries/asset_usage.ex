defmodule Storyarn.Sheets.References.Queries.AssetUsage do
  @moduledoc """
  Reads active Sheet usages of an asset for integrity and usage reporting.

  These queries never mutate assets or authored Sheet state.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  def list_avatar_sheets(project_id, asset_id) do
    Repo.all(
      from(sheet in Sheet,
        join: avatar in SheetAvatar,
        on: avatar.sheet_id == sheet.id and avatar.asset_id == ^asset_id,
        where: sheet.project_id == ^project_id,
        where: is_nil(sheet.deleted_at),
        distinct: true,
        order_by: [asc: sheet.name]
      )
    )
  end

  def list_banner_sheets(project_id, asset_id) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id,
        where: is_nil(sheet.deleted_at),
        where: sheet.banner_asset_id == ^asset_id,
        order_by: [asc: sheet.name]
      )
    )
  end
end

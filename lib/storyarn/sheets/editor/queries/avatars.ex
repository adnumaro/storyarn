defmodule Storyarn.Sheets.Editor.Queries.Avatars do
  @moduledoc """
  Read-only access to Sheet avatars for editor and consumer batch views.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  def list(sheet_id) do
    Repo.all(
      from(avatar in SheetAvatar,
        where: avatar.sheet_id == ^sheet_id,
        order_by: [asc: avatar.position],
        preload: [:asset]
      )
    )
  end

  def get(id) do
    SheetAvatar
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  def get_default(sheet_id) do
    Repo.one(
      from(avatar in SheetAvatar,
        where: avatar.sheet_id == ^sheet_id and avatar.is_default == true,
        preload: [:asset],
        limit: 1
      )
    )
  end

  def batch_by_sheet(project_id) do
    from(avatar in SheetAvatar,
      join: sheet in Sheet,
      on: avatar.sheet_id == sheet.id,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      order_by: [asc: avatar.position],
      select: {avatar.sheet_id, avatar},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _avatar} -> sheet_id end, fn {_sheet_id, avatar} -> avatar end)
  end
end

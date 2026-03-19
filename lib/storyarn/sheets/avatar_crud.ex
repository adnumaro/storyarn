defmodule Storyarn.Sheets.AvatarCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.{Sheet, SheetAvatar}

  # ===========================================================================
  # Queries
  # ===========================================================================

  def list_avatars(sheet_id) do
    from(a in SheetAvatar,
      where: a.sheet_id == ^sheet_id,
      order_by: [asc: a.position],
      preload: [:asset]
    )
    |> Repo.all()
  end

  def get_avatar(id) do
    SheetAvatar
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  def get_default_avatar(sheet_id) do
    from(a in SheetAvatar,
      where: a.sheet_id == ^sheet_id and a.is_default == true,
      preload: [:asset],
      limit: 1
    )
    |> Repo.one()
  end

  # ===========================================================================
  # Create
  # ===========================================================================

  def add_avatar(%Sheet{id: sheet_id}, asset_id, attrs \\ %{}) do
    position = next_position(sheet_id)
    is_first = position == 0

    %SheetAvatar{sheet_id: sheet_id}
    |> SheetAvatar.create_changeset(
      Map.merge(attrs, %{asset_id: asset_id, position: position, is_default: is_first})
    )
    |> Repo.insert()
  end

  # ===========================================================================
  # Update
  # ===========================================================================

  def update_avatar(%SheetAvatar{} = avatar, attrs) do
    avatar
    |> SheetAvatar.update_changeset(attrs)
    |> Repo.update()
  end

  def set_default(%SheetAvatar{} = avatar) do
    Repo.transaction(fn ->
      from(a in SheetAvatar, where: a.sheet_id == ^avatar.sheet_id and a.id != ^avatar.id)
      |> Repo.update_all(set: [is_default: false])

      avatar
      |> Ecto.Changeset.change(is_default: true)
      |> Repo.update!()
    end)
  end

  # ===========================================================================
  # Delete
  # ===========================================================================

  def remove_avatar(avatar_id) do
    case Repo.get(SheetAvatar, avatar_id) do
      nil ->
        {:error, :not_found}

      avatar ->
        result = Repo.delete(avatar)

        case result do
          {:ok, deleted} ->
            if deleted.is_default, do: promote_next_default(deleted.sheet_id)
            result

          _ ->
            result
        end
    end
  end

  # ===========================================================================
  # Reorder
  # ===========================================================================

  def reorder_avatars(sheet_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(a in SheetAvatar,
          where: a.id == ^id and a.sheet_id == ^sheet_id
        )
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ===========================================================================
  # Batch loading (for flow editor)
  # ===========================================================================

  def batch_load_avatars_by_sheet(project_id) do
    from(a in SheetAvatar,
      join: s in Sheet,
      on: a.sheet_id == s.id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: a.position],
      select: {a.sheet_id, a},
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(fn {sheet_id, _a} -> sheet_id end, fn {_, a} -> a end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp next_position(sheet_id) do
    from(a in SheetAvatar,
      where: a.sheet_id == ^sheet_id,
      select: coalesce(max(a.position), -1)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp promote_next_default(sheet_id) do
    case from(a in SheetAvatar,
           where: a.sheet_id == ^sheet_id,
           order_by: [asc: a.position],
           limit: 1
         )
         |> Repo.one() do
      nil -> :ok
      next -> Repo.update!(Ecto.Changeset.change(next, is_default: true))
    end
  end
end

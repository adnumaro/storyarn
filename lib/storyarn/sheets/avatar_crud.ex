defmodule Storyarn.Sheets.AvatarCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  # ===========================================================================
  # Queries
  # ===========================================================================

  def list_avatars(sheet_id) do
    Repo.all(from(a in SheetAvatar, where: a.sheet_id == ^sheet_id, order_by: [asc: a.position], preload: [:asset]))
  end

  def get_avatar(id) do
    SheetAvatar
    |> Repo.get(id)
    |> Repo.preload(:asset)
  end

  def get_default_avatar(sheet_id) do
    Repo.one(from(a in SheetAvatar, where: a.sheet_id == ^sheet_id and a.is_default == true, preload: [:asset], limit: 1))
  end

  # ===========================================================================
  # Create
  # ===========================================================================

  def add_avatar(%Sheet{id: sheet_id}, asset_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      project_id = fetch_sheet_project_id!(sheet_id)
      lock_active_project!(project_id)
      sheet = lock_active_sheet!(sheet_id, project_id)

      normalized_asset_id = lock_avatar_asset!(sheet.project_id, asset_id)

      position = next_position(sheet_id)
      is_first = position == 0

      case %SheetAvatar{sheet_id: sheet_id}
           |> SheetAvatar.create_changeset(
             Map.merge(attrs, %{
               asset_id: normalized_asset_id,
               position: position,
               is_default: is_first
             })
           )
           |> Repo.insert() do
        {:ok, avatar} -> avatar
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ===========================================================================
  # Update
  # ===========================================================================

  def update_avatar(%SheetAvatar{} = avatar, attrs) do
    Repo.transaction(fn ->
      {_sheet, persisted_avatar, _avatars} =
        lock_active_avatar_writer!(avatar.id, avatar.sheet_id)

      case persisted_avatar
           |> SheetAvatar.update_changeset(attrs)
           |> Repo.update() do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def set_default(%SheetAvatar{} = avatar) do
    Repo.transaction(fn ->
      {sheet, target, _avatars} =
        lock_active_avatar_writer!(avatar.id, avatar.sheet_id)

      Repo.update_all(from(a in SheetAvatar, where: a.sheet_id == ^sheet.id and a.id != ^target.id),
        set: [is_default: false]
      )

      target
      |> Ecto.Changeset.change(is_default: true)
      |> Repo.update!()
    end)
  end

  # ===========================================================================
  # Delete
  # ===========================================================================

  def remove_avatar(sheet_id, avatar_id)
      when is_integer(sheet_id) and sheet_id > 0 and is_integer(avatar_id) and avatar_id > 0 do
    Repo.transaction(fn ->
      {_sheet, avatar, _avatars} =
        lock_active_avatar_writer!(avatar_id, sheet_id, not_found_reason: :not_found)

      case AvatarIntegrity.ensure_deletable(avatar.id) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      case Repo.delete(avatar) do
        {:ok, deleted} ->
          if deleted.is_default, do: promote_next_default(deleted.sheet_id)
          deleted

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def remove_avatar(_sheet_id, _avatar_id), do: {:error, :not_found}

  defp lock_active_avatar_writer!(avatar_id, expected_sheet_id, opts \\ []) do
    not_found_reason = Keyword.get(opts, :not_found_reason, :avatar_not_found)
    {project_id, sheet_id} = fetch_avatar_owner!(avatar_id, not_found_reason)

    if expected_sheet_id != sheet_id do
      Repo.rollback(not_found_reason)
    end

    lock_active_project!(project_id)
    sheet = lock_active_sheet!(sheet_id, project_id)
    avatars = lock_sheet_avatars!(sheet_id)

    avatar =
      Enum.find(avatars, &(&1.id == avatar_id)) ||
        Repo.rollback(not_found_reason)

    {sheet, avatar, avatars}
  end

  # ===========================================================================
  # Reorder
  # ===========================================================================

  def reorder_avatars(sheet_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      normalized_ids = normalize_reorder_ids!(ordered_ids, :avatar)
      project_id = fetch_sheet_project_id!(sheet_id)

      lock_active_project!(project_id)
      lock_active_sheet!(sheet_id, project_id)
      locked_ids = lock_sheet_avatar_ids!(sheet_id)
      ensure_exact_reorder_set!(normalized_ids, locked_ids, ordered_ids, :avatar)

      normalized_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        Repo.update_all(from(a in SheetAvatar, where: a.id == ^id and a.sheet_id == ^sheet_id), set: [position: index])
      end)
    end)
  end

  def reorder_avatars(_sheet_id, ordered_ids), do: {:error, {:invalid_avatar_reorder, ordered_ids}}

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

  defp fetch_sheet_project_id!(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where: sheet.id == ^sheet_id,
        select: sheet.project_id
      )
    ) || Repo.rollback(:sheet_not_found)
  end

  defp fetch_avatar_owner!(avatar_id, not_found_reason) do
    Repo.one(
      from(avatar in SheetAvatar,
        join: sheet in Sheet,
        on: sheet.id == avatar.sheet_id,
        where: avatar.id == ^avatar_id,
        select: {sheet.project_id, sheet.id}
      )
    ) || Repo.rollback(not_found_reason)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_avatar_asset!(project_id, asset_id) do
    with {:ok, [normalized_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, [
             {:asset, :avatar_asset_id, asset_id}
           ]),
         :ok <- ensure_avatar_asset_present(normalized_asset_id, asset_id),
         :ok <-
           ProjectReferenceIntegrity.ensure_locked_asset_content_type(
             project_id,
             normalized_asset_id,
             :avatar_asset_id,
             "image/%"
           ) do
      normalized_asset_id
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_avatar_asset_present(nil, original_asset_id),
    do: {:error, {:invalid_project_reference, :avatar_asset_id, original_asset_id}}

  defp ensure_avatar_asset_present(_asset_id, _original_asset_id), do: :ok

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
      nil -> Repo.rollback(:sheet_not_active)
    end
  end

  defp lock_sheet_avatars!(sheet_id) do
    Repo.all(
      from(avatar in SheetAvatar,
        where: avatar.sheet_id == ^sheet_id,
        order_by: [asc: avatar.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_sheet_avatar_ids!(sheet_id) do
    Repo.all(
      from(avatar in SheetAvatar,
        where: avatar.sheet_id == ^sheet_id,
        order_by: [asc: avatar.id],
        lock: "FOR UPDATE",
        select: avatar.id
      )
    )
  end

  defp normalize_reorder_ids!(ordered_ids, type) do
    if Enum.all?(ordered_ids, &(is_integer(&1) and &1 > 0)) and
         length(ordered_ids) == length(Enum.uniq(ordered_ids)) do
      ordered_ids
    else
      Repo.rollback({invalid_reorder_reason(type), ordered_ids})
    end
  end

  defp ensure_exact_reorder_set!(ordered_ids, locked_ids, original_ids, type) do
    if Enum.sort(ordered_ids) != locked_ids do
      Repo.rollback({invalid_reorder_reason(type), original_ids})
    end
  end

  defp invalid_reorder_reason(:avatar), do: :invalid_avatar_reorder

  defp promote_next_default(sheet_id) do
    case Repo.one(from(a in SheetAvatar, where: a.sheet_id == ^sheet_id, order_by: [asc: a.position], limit: 1)) do
      nil -> :ok
      next -> Repo.update!(Ecto.Changeset.change(next, is_default: true))
    end
  end
end

defmodule Storyarn.References.AvatarIntegrity do
  @moduledoc """
  Transactional integrity helpers for `flow_nodes.data["avatar_id"]`.

  `avatar_id` lives inside JSONB, so PostgreSQL cannot enforce it with a
  conventional foreign key. Writers take a key-share lock on the referenced
  avatar before persisting node data. Avatar deleters take an update/delete
  lock first and then call `ensure_deletable/1`. This makes the validation and
  the write/delete mutually serializable.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  @type validation_error ::
          {:invalid_avatar_reference, term()}
          | {:avatar_project_mismatch, integer()}
          | {:avatar_speaker_mismatch, integer(), integer(), integer()}

  @spec lock_and_normalize_node_avatar(integer(), String.t(), map()) ::
          {:ok, map()} | {:error, validation_error()}
  def lock_and_normalize_node_avatar(flow_id, node_type, data) when is_integer(flow_id) and is_map(data) do
    with {:ok, project_id} <- active_flow_project_id(flow_id) do
      lock_and_normalize_node_avatar_for_project(project_id, node_type, data)
    end
  end

  @spec lock_and_normalize_node_avatar_for_project(integer(), String.t(), map()) ::
          {:ok, map()} | {:error, validation_error()}
  def lock_and_normalize_node_avatar_for_project(project_id, _node_type, data)
      when is_integer(project_id) and is_map(data) do
    ensure_transaction!()

    case normalize_optional_id(Map.get(data, "avatar_id")) do
      {:ok, nil} ->
        {:ok, data}

      {:ok, avatar_id} ->
        with {:ok, speaker_sheet_id} <-
               normalize_optional_id(Map.get(data, "speaker_sheet_id")),
             {:ok, avatar_sheet_id} <-
               lock_project_avatar(avatar_id, project_id),
             :ok <-
               validate_avatar_speaker(
                 avatar_id,
                 avatar_sheet_id,
                 speaker_sheet_id
               ) do
          {:ok, Map.put(data, "avatar_id", avatar_id)}
        end

      :error ->
        {:error, {:invalid_avatar_reference, Map.get(data, "avatar_id")}}
    end
  end

  def lock_and_normalize_node_avatar_for_project(_project_id, _node_type, data) do
    value = if is_map(data), do: Map.get(data, "avatar_id"), else: data
    {:error, {:invalid_avatar_reference, value}}
  end

  @doc """
  Locks one avatar for deletion and verifies optional ownership constraints.

  Call `ensure_deletable/1` after this function and before deleting the row.
  """
  @spec lock_avatar_for_delete(integer(), keyword()) ::
          {:ok, SheetAvatar.t()} | {:error, term()}
  def lock_avatar_for_delete(avatar_id, opts \\ []) when is_integer(avatar_id) do
    ensure_transaction!()

    case Repo.one(
           from(avatar in SheetAvatar,
             join: sheet in Sheet,
             on: sheet.id == avatar.sheet_id,
             where: avatar.id == ^avatar_id,
             lock: "FOR UPDATE",
             select: {avatar, sheet.project_id}
           )
         ) do
      nil ->
        {:error, :not_found}

      {%SheetAvatar{} = avatar, project_id} ->
        validate_delete_ownership(avatar, project_id, opts)
    end
  end

  @doc """
  Locks an existing avatar as a reference target.

  This is used by trash-ref restoration before locking its trash rows so lock
  ordering remains avatar -> trash ref -> source node.
  """
  @spec lock_avatar_reference_target(integer()) :: :ok | {:error, term()}
  def lock_avatar_reference_target(avatar_id) when is_integer(avatar_id) do
    ensure_transaction!()

    case Repo.one(
           from(avatar in SheetAvatar,
             where: avatar.id == ^avatar_id,
             lock: "FOR KEY SHARE",
             select: avatar.id
           )
         ) do
      ^avatar_id -> :ok
      nil -> {:error, {:invalid_avatar_reference, avatar_id}}
    end
  end

  @doc """
  Checks that a caller-locked avatar has no node or pending trash refs.

  Soft-deleted nodes and flows deliberately count as references: deleting
  their avatar would make a later trash restore produce a dangling JSONB ID.
  """
  @spec ensure_deletable(integer()) :: :ok | {:error, term()}
  def ensure_deletable(avatar_id) when is_integer(avatar_id) do
    ensure_transaction!()

    pending_ref_ids =
      Repo.all(
        from(ref in EntityTrashRef,
          where: ref.target_sheet_avatar_id == ^avatar_id,
          order_by: [asc: ref.id],
          lock: "FOR UPDATE",
          select: ref.id
        )
      )

    if pending_ref_ids == [] do
      ensure_no_node_references(avatar_id)
    else
      {:error, {:avatar_in_use, avatar_id, {:pending_flow_trash_references, length(pending_ref_ids)}}}
    end
  end

  defp active_flow_project_id(flow_id) do
    case Repo.one(
           from(flow in Flow,
             where: flow.id == ^flow_id and is_nil(flow.deleted_at),
             select: flow.project_id
           )
         ) do
      nil -> {:error, {:invalid_avatar_reference, {:flow_not_active, flow_id}}}
      project_id -> {:ok, project_id}
    end
  end

  defp lock_project_avatar(avatar_id, project_id) do
    case Repo.one(
           from(avatar in SheetAvatar,
             join: sheet in Sheet,
             on: sheet.id == avatar.sheet_id,
             where:
               avatar.id == ^avatar_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR KEY SHARE",
             select: avatar.sheet_id
           )
         ) do
      nil ->
        if Repo.exists?(from(avatar in SheetAvatar, where: avatar.id == ^avatar_id)) do
          {:error, {:avatar_project_mismatch, avatar_id}}
        else
          {:error, {:invalid_avatar_reference, avatar_id}}
        end

      sheet_id ->
        {:ok, sheet_id}
    end
  end

  defp validate_avatar_speaker(_avatar_id, _avatar_sheet_id, nil), do: :ok

  defp validate_avatar_speaker(_avatar_id, avatar_sheet_id, avatar_sheet_id), do: :ok

  defp validate_avatar_speaker(avatar_id, avatar_sheet_id, speaker_sheet_id) do
    {:error, {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, speaker_sheet_id}}
  end

  defp validate_delete_ownership(avatar, project_id, opts) do
    expected_sheet_id = Keyword.get(opts, :sheet_id)
    expected_project_id = Keyword.get(opts, :project_id)

    cond do
      is_integer(expected_sheet_id) and avatar.sheet_id != expected_sheet_id ->
        {:error, :not_found}

      is_integer(expected_project_id) and project_id != expected_project_id ->
        {:error, :not_found}

      true ->
        {:ok, avatar}
    end
  end

  defp ensure_no_node_references(avatar_id) do
    avatar_id_string = Integer.to_string(avatar_id)

    count =
      Repo.aggregate(
        from(node in FlowNode,
          where: fragment("?->>? = ?", node.data, "avatar_id", ^avatar_id_string)
        ),
        :count,
        :id
      )

    if count == 0 do
      :ok
    else
      {:error, {:avatar_in_use, avatar_id, {:referenced_by_flow_nodes, count}}}
    end
  end

  defp normalize_optional_id(nil), do: {:ok, nil}
  defp normalize_optional_id(""), do: {:ok, nil}
  defp normalize_optional_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp normalize_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp normalize_optional_id(_id), do: :error

  defp ensure_transaction! do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "avatar reference integrity checks require an explicit database transaction"
    end
  end
end

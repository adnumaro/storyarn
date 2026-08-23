defmodule Storyarn.Sheets.AvatarIntegrity do
  @moduledoc """
  Sheet-owned deletion veto for sheet avatars.

  An avatar cannot be deleted while a pending Flow trash reference or a live
  flow node still points at it. The Flow rows are read through Sheet-owned
  persistence records so the check needs nothing from other contexts.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Persistence.EntityTrashRefRecord
  alias Storyarn.Sheets.Persistence.FlowNodeRecord

  @spec ensure_deletable(integer()) :: :ok | {:error, term()}
  def ensure_deletable(avatar_id) when is_integer(avatar_id) do
    ensure_transaction!()

    pending_ref_ids =
      Repo.all(
        from(ref in EntityTrashRefRecord,
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

  defp ensure_no_node_references(avatar_id) do
    avatar_id_string = Integer.to_string(avatar_id)

    count =
      Repo.aggregate(
        from(node in FlowNodeRecord,
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

  defp ensure_transaction! do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "avatar reference integrity checks require an explicit database transaction"
    end
  end
end

defmodule Storyarn.Flows.References.Commands.OwnerAuthority do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.References.Projections.ProjectMembershipRecord
  alias Storyarn.Flows.References.Projections.ProjectRecord
  alias Storyarn.Repo

  @type error_reason ::
          :unauthorized | :ownership_invariant_violation | :authorization_transaction_required

  @spec authorize_locked(map(), ProjectRecord.t()) :: :ok | {:error, error_reason()}
  def authorize_locked(%{user: %{id: actor_id}}, %ProjectRecord{id: project_id, owner_id: owner_id})
      when is_integer(actor_id) and actor_id > 0 and is_integer(project_id) and is_integer(owner_id) and owner_id > 0 do
    if Repo.in_transaction?() do
      project_id
      |> lock_owner_memberships()
      |> authorize_canonical_owner(owner_id, actor_id)
    else
      {:error, :authorization_transaction_required}
    end
  end

  def authorize_locked(_scope, %ProjectRecord{}), do: {:error, :unauthorized}

  defp lock_owner_memberships(project_id) do
    Repo.all(
      from(membership in ProjectMembershipRecord,
        where: membership.project_id == ^project_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp authorize_canonical_owner([%ProjectMembershipRecord{user_id: owner_id}], owner_id, owner_id), do: :ok

  defp authorize_canonical_owner([%ProjectMembershipRecord{user_id: owner_id}], owner_id, _actor_id),
    do: {:error, :unauthorized}

  defp authorize_canonical_owner(_memberships, _owner_id, _actor_id), do: {:error, :ownership_invariant_violation}
end

defmodule Storyarn.Accounts.Identity.Commands.RecoveryIdentities do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  # These ports participate in the caller's authorized recovery transaction.
  # No user profile or credentials cross the identity boundary.
  def resolve_locked(identities) when is_map(identities) do
    if Repo.in_transaction?(), do: resolve(identities), else: {:error, :recovery_identity_transaction_required}
  end

  defp resolve(identities) do
    values = Map.values(identities)
    query = from u in User, where: u.recovery_identity in ^values, order_by: u.id, select: {u.recovery_identity, u.id}
    locked = query |> lock("FOR KEY SHARE SKIP LOCKED") |> Repo.all() |> Map.new()
    existing = query |> Repo.all() |> Map.new()

    if MapSet.new(Map.keys(existing)) == MapSet.new(Map.keys(locked)) do
      {:ok, Map.new(identities, fn {id, identity} -> {String.to_integer(id), locked[identity]} end)}
    else
      {:error, :recovery_identities_busy}
    end
  end
end

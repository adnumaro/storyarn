defmodule Storyarn.Accounts.Identity.Queries.RecoveryIdentities do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  def capture(ids) when is_list(ids) do
    if Repo.in_transaction?() do
      identities = Repo.all(from u in User, where: u.id in ^ids, select: {u.id, u.recovery_identity})
      {:ok, Map.new(identities, fn {id, identity} -> {Integer.to_string(id), identity} end)}
    else
      {:error, :recovery_identity_transaction_required}
    end
  end
end

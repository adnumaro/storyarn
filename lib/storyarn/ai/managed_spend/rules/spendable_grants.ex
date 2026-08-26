defmodule Storyarn.AI.ManagedSpend.Rules.SpendableGrants do
  @moduledoc "Canonical definition of allowance units that may still be reserved."

  import Ecto.Query

  alias Storyarn.AI.AllowanceGrant

  @spec query(pos_integer(), DateTime.t()) :: Ecto.Query.t()
  def query(account_id, now) do
    from(grant in AllowanceGrant,
      where:
        grant.account_id == ^account_id and grant.remaining_units > 0 and
          (is_nil(grant.expires_at) or grant.expires_at > ^now)
    )
  end
end

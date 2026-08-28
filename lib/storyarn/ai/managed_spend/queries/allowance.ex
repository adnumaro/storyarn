defmodule Storyarn.AI.ManagedSpend.Queries.Allowance do
  @moduledoc "Authorized allowance summaries and read-only preflight projections."

  import Ecto.Query

  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.ManagedSpend.Rules.SpendableGrants
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @type summary :: %{
          status: String.t(),
          available_units: non_neg_integer(),
          reserved_units: non_neg_integer(),
          committed_units: non_neg_integer()
        }
  @doc """
  Returns a read-only projection of a workspace's spendable units.

  This path never locks and never expires grants. Grants past their expiry are
  excluded from the sum even when the sweeper has not run, while the
  authoritative no-overspend check remains in the reservation command.
  """
  @spec projection(pos_integer()) :: summary()
  def projection(workspace_id) when is_integer(workspace_id) do
    case Repo.get_by(AllowanceAccount, workspace_id: workspace_id) do
      nil -> empty_summary()
      account -> %{account_summary(account) | available_units: spendable_units(account.id)}
    end
  end

  def projection(_workspace_id), do: empty_summary()

  defp spendable_units(account_id) do
    Repo.one(
      from(grant in SpendableGrants.query(account_id, TimeHelpers.now()),
        # Postgres sums integers into numeric; without this cast the result is a
        # Decimal and integer comparisons in preflight silently become invalid.
        select: type(coalesce(sum(grant.remaining_units), 0), :integer)
      )
    )
  end

  @doc false
  @spec account_summary(AllowanceAccount.t() | nil) :: summary()
  def account_summary(nil), do: empty_summary()

  def account_summary(account) do
    %{
      status: account.status,
      available_units: account.available_units,
      reserved_units: account.reserved_units,
      committed_units: account.committed_units
    }
  end

  defp empty_summary do
    %{status: "unavailable", available_units: 0, reserved_units: 0, committed_units: 0}
  end
end

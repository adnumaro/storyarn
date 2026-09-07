defmodule Storyarn.Accounts.Identity.RecoveryIdentitiesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts

  test "ports require a transaction and return only stable identity mappings" do
    user = user_fixture()
    assert {:error, :recovery_identity_transaction_required} = Accounts.capture_recovery_identities([user.id])
    assert {:error, :recovery_identity_transaction_required} = Accounts.resolve_recovery_identities_locked(%{})

    assert {:ok, :checked} =
             Repo.transact(fn ->
               assert {:ok, identities} = Accounts.capture_recovery_identities([user.id, -1])
               assert identities == %{Integer.to_string(user.id) => user.recovery_identity}

               assert {:ok, %{123 => id, 456 => nil}} =
                        Accounts.resolve_recovery_identities_locked(%{
                          "123" => user.recovery_identity,
                          "456" => Ecto.UUID.generate()
                        })

               assert id == user.id
               {:ok, :checked}
             end)
  end
end

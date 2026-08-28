defmodule Storyarn.Accounts.Authentication.Commands.PasswordsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.Accounts.Authentication.Commands.Passwords

  # =============================================================================
  # change/3
  # =============================================================================

  describe "change/3" do
    test "returns a valid changeset for the user" do
      user = user_fixture()
      changeset = Passwords.change(user)
      assert %Ecto.Changeset{data: %{id: id}} = changeset
      assert id == user.id
    end

    test "returns a changeset that processes password input" do
      user = user_fixture()
      changeset = Passwords.change(user, %{password: "new_password!"})
      assert %Ecto.Changeset{} = changeset
      # Password changeset hashes the password into hashed_password
      assert Ecto.Changeset.get_change(changeset, :hashed_password)
    end
  end

  # =============================================================================
  # update/2
  # =============================================================================

  describe "update/2" do
    test "updates the user password" do
      user = user_fixture()

      assert {:ok, {updated_user, expired_tokens}} =
               Passwords.update(user, %{password: "new_valid_password!"})

      assert updated_user.id == user.id
      assert is_list(expired_tokens)
    end

    test "returns error for invalid password" do
      user = user_fixture()

      assert {:error, changeset} =
               Passwords.update(user, %{password: ""})

      assert errors_on(changeset)[:password]
    end
  end
end

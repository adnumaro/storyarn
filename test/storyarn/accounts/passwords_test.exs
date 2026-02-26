defmodule Storyarn.Accounts.PasswordsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Accounts.Passwords

  import Storyarn.AccountsFixtures

  # =============================================================================
  # change_user_password/3
  # =============================================================================

  describe "change_user_password/3" do
    test "returns a valid changeset for the user" do
      user = user_fixture()
      changeset = Passwords.change_user_password(user)
      assert %Ecto.Changeset{data: %{id: id}} = changeset
      assert id == user.id
    end

    test "returns a changeset that processes password input" do
      user = user_fixture()
      changeset = Passwords.change_user_password(user, %{password: "new_password!"})
      assert %Ecto.Changeset{} = changeset
      # Password changeset hashes the password into hashed_password
      assert Ecto.Changeset.get_change(changeset, :hashed_password) != nil
    end
  end

  # =============================================================================
  # update_user_password/2
  # =============================================================================

  describe "update_user_password/2" do
    test "updates the user password" do
      user = user_fixture()

      assert {:ok, {updated_user, expired_tokens}} =
               Passwords.update_user_password(user, %{password: "new_valid_password!"})

      assert updated_user.id == user.id
      assert is_list(expired_tokens)
    end

    test "returns error for invalid password" do
      user = user_fixture()

      assert {:error, changeset} =
               Passwords.update_user_password(user, %{password: ""})

      assert errors_on(changeset)[:password]
    end
  end
end

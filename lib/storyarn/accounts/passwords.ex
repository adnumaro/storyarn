defmodule Storyarn.Accounts.Passwords do
  @moduledoc false

  alias Storyarn.Accounts.{Sessions, User}
  alias Storyarn.Repo

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  """
  def update_user_password(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Sessions.delete_all_user_tokens(user)
        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end

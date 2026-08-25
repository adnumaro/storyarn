defmodule Storyarn.Accounts.Authentication.Commands.Passwords do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Commands.SessionTokens
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @spec change(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @spec update(User.t(), map()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def update(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = SessionTokens.delete_all(user)
        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  @spec reset(User.t(), map()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t()}
  def reset(%User{} = user, attrs), do: update(user, attrs)
end

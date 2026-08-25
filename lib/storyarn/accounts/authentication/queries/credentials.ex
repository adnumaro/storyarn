defmodule Storyarn.Accounts.Authentication.Queries.Credentials do
  @moduledoc false

  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  @spec authenticate(String.t(), String.t()) :: User.t() | nil
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: String.downcase(email))
    if User.valid_password?(user, password), do: user
  end
end

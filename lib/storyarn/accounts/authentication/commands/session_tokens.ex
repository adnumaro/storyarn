defmodule Storyarn.Accounts.Authentication.Commands.SessionTokens do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Authentication.Tokens.Issuer
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @spec generate(map()) :: binary()
  def generate(user) do
    {token, user_token} = Issuer.session(user)
    Repo.insert!(user_token)
    token
  end

  @spec delete(binary()) :: :ok
  def delete(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @spec delete_all(map()) :: [UserToken.t()]
  def delete_all(user) do
    tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)
    Repo.delete_all(from(token in UserToken, where: token.id in ^Enum.map(tokens_to_expire, & &1.id)))
    tokens_to_expire
  end
end

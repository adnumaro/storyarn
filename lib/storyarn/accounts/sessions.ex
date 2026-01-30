defmodule Storyarn.Accounts.Sessions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Deletes all tokens for a user and returns them.
  """
  def delete_all_user_tokens(user) do
    tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)
    Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))
    tokens_to_expire
  end
end

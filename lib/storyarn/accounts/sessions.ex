defmodule Storyarn.Accounts.Sessions do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
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
  Re-authenticates one active session without changing its sudo timestamp.

  Sudo elevation is represented by a separate, short-lived signed grant in the
  web layer. Keeping the primary token unchanged ensures another browser holding
  a copy of it does not inherit the password confirmation.
  """
  def reauthenticate_user_session(%Scope{user: %User{} = user}, token, password)
      when is_binary(token) and is_binary(password) do
    if session_token_active?(%Scope{user: user}, token) do
      if User.valid_password?(user, password),
        do: {:ok, user},
        else: {:error, :invalid_credentials}
    else
      {:error, :invalid_session}
    end
  end

  def reauthenticate_user_session(_scope, _token, password) do
    User.valid_password?(nil, password)
    {:error, :invalid_credentials}
  end

  @doc false
  def session_token_active?(%Scope{user: %User{id: user_id}}, token) when is_binary(token) do
    token
    |> UserToken.valid_session_token_query(user_id)
    |> Repo.exists?()
  end

  def session_token_active?(_scope, _token), do: false

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

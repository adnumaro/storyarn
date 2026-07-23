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

  This verification step does not elevate the existing token. The web layer
  exchanges a short-lived, session-bound handoff for a freshly authenticated
  browser session, while the previous token remains un-elevated. A browser
  holding a copy of the previous token therefore does not inherit confirmation.
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

  @doc false
  def generate_sudo_handoff_nonce(%User{} = user) do
    Repo.delete_all(
      from token in UserToken,
        where: token.user_id == ^user.id,
        where: token.context == "sudo_handoff",
        where: token.inserted_at <= ago(2, "minute")
    )

    {nonce, user_token} = UserToken.build_sudo_handoff_nonce(user)
    Repo.insert!(user_token)
    nonce
  end

  @doc false
  def sudo_handoff_nonce_active?(%Scope{user: %User{id: user_id}}, nonce) when is_binary(nonce) do
    nonce
    |> sudo_handoff_nonce_query(user_id)
    |> Repo.exists?()
  end

  def sudo_handoff_nonce_active?(_scope, _nonce), do: false

  @doc false
  def consume_sudo_handoff_nonce(%Scope{user: %User{id: user_id}}, nonce) when is_binary(nonce) do
    case Repo.delete_all(sudo_handoff_nonce_query(nonce, user_id)) do
      {1, _rows} -> :ok
      _missing_or_consumed -> :error
    end
  end

  def consume_sudo_handoff_nonce(_scope, _nonce), do: :error

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  defp sudo_handoff_nonce_query(nonce, user_id) do
    from token in UserToken,
      where: token.token == ^nonce,
      where: token.context == "sudo_handoff",
      where: token.user_id == ^user_id,
      where: token.inserted_at > ago(2, "minute")
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

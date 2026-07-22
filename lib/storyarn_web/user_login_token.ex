defmodule StoryarnWeb.UserLoginToken do
  @moduledoc false

  @salt "user login"
  @max_age 60

  def sign_user(user, session_nonce) when is_binary(session_nonce) and session_nonce != "" do
    Phoenix.Token.sign(StoryarnWeb.Endpoint, @salt, {user.id, session_nonce})
  end

  def verify(token, session_nonce) when is_binary(token) and is_binary(session_nonce) and session_nonce != "" do
    case Phoenix.Token.verify(StoryarnWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, {user_id, ^session_nonce}} when is_integer(user_id) -> {:ok, user_id}
      _other -> :error
    end
  end

  def verify(_token, _session_nonce), do: :error
end

defmodule StoryarnWeb.UserLoginToken do
  @moduledoc false

  @salt "user login"
  @max_age 60

  @type handoff :: :login | {:registration, String.t() | nil}

  # A LiveView that has just authenticated the person (login) or created their
  # account (registration) hands the browser to UserSessionController with this
  # token. Registration also carries the local destination it already validated.
  def sign_user(user, session_nonce) when is_binary(session_nonce) and session_nonce != "" do
    sign(user, session_nonce, :login)
  end

  def sign_registration(user, session_nonce, return_to)
      when is_binary(session_nonce) and session_nonce != "" and (is_nil(return_to) or is_binary(return_to)) do
    sign(user, session_nonce, {:registration, return_to})
  end

  @spec verify(term(), term()) :: {:ok, pos_integer(), handoff()} | :error
  def verify(token, session_nonce) when is_binary(token) and is_binary(session_nonce) and session_nonce != "" do
    case Phoenix.Token.verify(StoryarnWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, {user_id, ^session_nonce, handoff}} when is_integer(user_id) -> {:ok, user_id, handoff}
      _other -> :error
    end
  end

  def verify(_token, _session_nonce), do: :error

  defp sign(user, session_nonce, handoff) do
    Phoenix.Token.sign(StoryarnWeb.Endpoint, @salt, {user.id, session_nonce, handoff})
  end
end

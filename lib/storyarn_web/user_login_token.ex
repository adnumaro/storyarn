defmodule StoryarnWeb.UserLoginToken do
  @moduledoc false

  @salt "user login"
  @max_age 60

  def sign_user(user) do
    Phoenix.Token.sign(StoryarnWeb.Endpoint, @salt, user.id)
  end

  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(StoryarnWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_token), do: :error
end

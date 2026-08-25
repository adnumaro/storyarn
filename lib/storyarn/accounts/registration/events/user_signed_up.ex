defmodule Storyarn.Accounts.Registration.Events.UserSignedUp do
  @moduledoc false

  alias Storyarn.Accounts.User
  alias Storyarn.Platform

  @auth_methods ~w(password invite)

  def emit(%User{} = user, auth_method) when auth_method in @auth_methods do
    Platform.react_to_event(user, :accounts, :user_signed_up, %{auth_method: auth_method})
  end

  def emit(_user, _auth_method), do: :ok
end

defmodule Storyarn.Accounts.Authentication.Events.UserLoggedIn do
  @moduledoc "Account-owned fact published after a completed login."

  alias Storyarn.Accounts.User
  alias Storyarn.Platform

  @auth_methods ~w(password invite)

  @spec publish(term(), String.t()) :: :ok
  def publish(%User{} = user, auth_method) when auth_method in @auth_methods do
    Platform.react_to_event(user, :accounts, :user_logged_in, %{auth_method: auth_method})
  end

  def publish(_user, _auth_method), do: :ok
end

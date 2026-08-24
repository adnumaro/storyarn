defmodule Storyarn.Accounts.Events do
  @moduledoc """
  Account-owned business event vocabulary.

  Accounts owns the facts and payloads. Platform owns cross-cutting
  reactions such as product metrics.
  """

  alias Storyarn.Accounts.User
  alias Storyarn.Platform

  @event_types [:user_logged_in, :user_signed_up]
  @auth_methods ~w(password invite)

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :accounts, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc "Publishes the product fact for a completed sign-up."
  @spec user_signed_up(term(), String.t()) :: :ok
  def user_signed_up(%User{} = user, auth_method) do
    emit(user, :user_signed_up, %{auth_method: auth_method})
  end

  def user_signed_up(_user, _auth_method), do: :ok

  @doc "Publishes the product fact for a completed login."
  @spec user_logged_in(term(), String.t()) :: :ok
  def user_logged_in(%User{} = user, auth_method) do
    emit(user, :user_logged_in, %{auth_method: auth_method})
  end

  def user_logged_in(_user, _auth_method), do: :ok

  defp valid_payload?(:user_logged_in, %{auth_method: auth_method}), do: auth_method in @auth_methods
  defp valid_payload?(:user_signed_up, %{auth_method: auth_method}), do: auth_method in @auth_methods
  defp valid_payload?(_event_type, _payload), do: false
end

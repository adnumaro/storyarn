defmodule Storyarn.Accounts.Authentication.Queries.Sessions do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Tokens.Verifier
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  @spec get(binary()) :: {User.t(), DateTime.t()} | nil
  def get(token) do
    {:ok, query} = Verifier.session(token)
    Repo.one(query)
  end

  @spec reauthenticate(Scope.t(), binary(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | :invalid_session}
  def reauthenticate(%Scope{user: %User{} = user} = scope, token, password)
      when is_binary(token) and is_binary(password) do
    if active?(scope, token) do
      if User.valid_password?(user, password),
        do: {:ok, user},
        else: {:error, :invalid_credentials}
    else
      {:error, :invalid_session}
    end
  end

  def reauthenticate(_scope, _token, password) do
    User.valid_password?(nil, password)
    {:error, :invalid_credentials}
  end

  @spec active?(Scope.t(), binary()) :: boolean()
  def active?(%Scope{user: %User{id: user_id}}, token) when is_binary(token) do
    token
    |> Verifier.active_session(user_id)
    |> Repo.exists?()
  end

  def active?(_scope, _token), do: false
end

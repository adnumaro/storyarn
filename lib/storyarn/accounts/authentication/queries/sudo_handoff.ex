defmodule Storyarn.Accounts.Authentication.Queries.SudoHandoff do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @spec active?(Scope.t(), binary()) :: boolean()
  def active?(%Scope{user: %User{id: user_id}}, nonce) when is_binary(nonce) do
    nonce
    |> query(user_id)
    |> Repo.exists?()
  end

  def active?(_scope, _nonce), do: false

  @doc false
  @spec query(binary(), integer()) :: Ecto.Query.t()
  def query(nonce, user_id) do
    from token in UserToken,
      where: token.token == ^nonce,
      where: token.context == "sudo_handoff",
      where: token.user_id == ^user_id,
      where: token.inserted_at > ago(2, "minute")
  end
end

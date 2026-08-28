defmodule Storyarn.Accounts.Authentication.Commands.SudoHandoff do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Authentication.Queries.SudoHandoff, as: SudoHandoffQuery
  alias Storyarn.Accounts.Authentication.Tokens.Issuer
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @spec generate(User.t()) :: binary()
  def generate(%User{} = user) do
    Repo.delete_all(
      from token in UserToken,
        where: token.user_id == ^user.id,
        where: token.context == "sudo_handoff",
        where: token.inserted_at <= ago(2, "minute")
    )

    {nonce, user_token} = Issuer.sudo_handoff(user)
    Repo.insert!(user_token)
    nonce
  end

  @spec consume(Scope.t(), binary()) :: :ok | :error
  def consume(%Scope{user: %User{id: user_id}}, nonce) when is_binary(nonce) do
    case Repo.delete_all(SudoHandoffQuery.query(nonce, user_id)) do
      {1, _rows} -> :ok
      _missing_or_consumed -> :error
    end
  end

  def consume(_scope, _nonce), do: :error
end

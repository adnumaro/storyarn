defmodule Storyarn.Accounts.Registration.Tokens.Invitation do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Platform.Shared.TokenGenerator

  @context "invite"
  @validity_in_days 14

  def issue(%User{} = user) do
    {encoded_token, hashed_token} = TokenGenerator.build_hashed_token()

    {encoded_token,
     %UserToken{
       token: hashed_token,
       context: @context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  def verify_query(token) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        query =
          from token in UserToken,
            where: token.token == ^hashed_token,
            where: token.context == @context,
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(@validity_in_days, "day"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end
end

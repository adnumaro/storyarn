defmodule Storyarn.Accounts.Registration.Tokens.Invitation do
  @moduledoc false

  alias Storyarn.Accounts.Registration.Queries.InvitationToken
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Platform.Shared.TokenGenerator

  @context "invite"

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
        {:ok, InvitationToken.by_hash(hashed_token, @context)}

      :error ->
        :error
    end
  end
end

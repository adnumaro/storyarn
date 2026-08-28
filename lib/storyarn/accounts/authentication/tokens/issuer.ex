defmodule Storyarn.Accounts.Authentication.Tokens.Issuer do
  @moduledoc false

  alias Storyarn.Accounts.UserToken
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Platform.Shared.TokenGenerator

  @spec session(map()) :: {binary(), UserToken.t()}
  def session(user) do
    token = :crypto.strong_rand_bytes(32)
    authenticated_at = user.authenticated_at || TimeHelpers.now()

    {token,
     %UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       authenticated_at: authenticated_at
     }}
  end

  @spec sudo_handoff(map()) :: {binary(), UserToken.t()}
  def sudo_handoff(user) do
    nonce = :crypto.strong_rand_bytes(32)
    {nonce, %UserToken{token: nonce, context: "sudo_handoff", user_id: user.id}}
  end

  @spec email(map(), String.t()) :: {String.t(), UserToken.t()}
  def email(user, context) do
    {encoded_token, hashed_token} = TokenGenerator.build_hashed_token()

    {encoded_token,
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end
end

defmodule Storyarn.Shared.TokenGenerator do
  @moduledoc """
  Shared token generation and verification utilities.

  Provides cryptographic token operations used by invitation systems
  and email-based authentication tokens.
  """

  @hash_algorithm :sha256
  @rand_size 32

  @doc """
  Generates a random token and its hash.

  Returns `{encoded_token, hashed_token}` where:
  - `encoded_token` is a URL-safe base64 string to send to the user
  - `hashed_token` is the binary hash to store in the database
  """
  def build_hashed_token do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)
    {Base.url_encode64(token, padding: false), hashed_token}
  end

  @doc """
  Decodes and hashes a user-provided token for verification.

  Returns `{:ok, hashed_token}` if the token is valid base64,
  `:error` otherwise.
  """
  def decode_and_hash(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, decoded_token} ->
        {:ok, :crypto.hash(@hash_algorithm, decoded_token)}

      :error ->
        :error
    end
  end
end

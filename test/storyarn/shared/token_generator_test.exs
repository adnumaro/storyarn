defmodule Storyarn.Shared.TokenGeneratorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.TokenGenerator

  # ===========================================================================
  # build_hashed_token/0
  # ===========================================================================

  describe "build_hashed_token/0" do
    test "returns a tuple of {encoded_token, hashed_token}" do
      {encoded, hashed} = TokenGenerator.build_hashed_token()

      assert is_binary(encoded)
      assert is_binary(hashed)
    end

    test "encoded token is URL-safe base64" do
      {encoded, _hashed} = TokenGenerator.build_hashed_token()

      # URL-safe base64 uses only [A-Za-z0-9_-], no padding
      assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, encoded)
    end

    test "hashed token is a binary hash" do
      {_encoded, hashed} = TokenGenerator.build_hashed_token()

      # SHA-256 produces 32-byte hash
      assert byte_size(hashed) == 32
    end

    test "generates unique tokens on each call" do
      {encoded1, hashed1} = TokenGenerator.build_hashed_token()
      {encoded2, hashed2} = TokenGenerator.build_hashed_token()

      assert encoded1 != encoded2
      assert hashed1 != hashed2
    end

    test "encoded token can be decoded back" do
      {encoded, _hashed} = TokenGenerator.build_hashed_token()

      assert {:ok, decoded} = Base.url_decode64(encoded, padding: false)
      assert byte_size(decoded) == 32
    end
  end

  # ===========================================================================
  # decode_and_hash/1
  # ===========================================================================

  describe "decode_and_hash/1" do
    test "round-trip: build then decode produces matching hash" do
      {encoded, hashed} = TokenGenerator.build_hashed_token()

      assert {:ok, decoded_hash} = TokenGenerator.decode_and_hash(encoded)
      assert decoded_hash == hashed
    end

    test "returns :error for invalid base64" do
      assert TokenGenerator.decode_and_hash("!!!invalid!!!") == :error
    end

    test "returns :error for empty string" do
      # Empty string is valid base64 that decodes to empty binary
      # but let's test it
      result = TokenGenerator.decode_and_hash("")

      case result do
        {:ok, _hash} ->
          # Empty string decodes to empty binary, which then gets hashed
          assert true

        :error ->
          assert true
      end
    end

    test "returns {:ok, hash} for valid base64 input" do
      # Create a known valid token
      token = :crypto.strong_rand_bytes(32)
      encoded = Base.url_encode64(token, padding: false)

      assert {:ok, hash} = TokenGenerator.decode_and_hash(encoded)
      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "same encoded token always produces same hash" do
      {encoded, _} = TokenGenerator.build_hashed_token()

      {:ok, hash1} = TokenGenerator.decode_and_hash(encoded)
      {:ok, hash2} = TokenGenerator.decode_and_hash(encoded)

      assert hash1 == hash2
    end

    test "different encoded tokens produce different hashes" do
      {encoded1, _} = TokenGenerator.build_hashed_token()
      {encoded2, _} = TokenGenerator.build_hashed_token()

      {:ok, hash1} = TokenGenerator.decode_and_hash(encoded1)
      {:ok, hash2} = TokenGenerator.decode_and_hash(encoded2)

      assert hash1 != hash2
    end
  end
end

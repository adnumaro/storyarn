defmodule Storyarn.Accounts.Authentication.Adapters.Encryption.ResetUrl do
  @moduledoc """
  Technical encryption adapter for reset URLs stored in durable job payloads.
  """

  alias Storyarn.Platform.Shared.EncryptedBinary

  @spec encrypt!(String.t()) :: String.t()
  def encrypt!(reset_url) do
    {:ok, encrypted_binary} = EncryptedBinary.dump(reset_url)
    Base.encode64(encrypted_binary)
  end

  @spec decrypt(String.t()) :: {:ok, String.t()} | {:error, :invalid_reset_password_url}
  def decrypt(encrypted_reset_url) when is_binary(encrypted_reset_url) do
    with {:ok, encrypted_binary} <- Base.decode64(encrypted_reset_url),
         {:ok, reset_url} <- EncryptedBinary.load(encrypted_binary) do
      {:ok, reset_url}
    else
      _ -> {:error, :invalid_reset_password_url}
    end
  end
end

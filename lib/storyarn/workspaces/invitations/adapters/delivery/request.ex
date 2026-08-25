defmodule Storyarn.Workspaces.Invitations.Adapters.Delivery.Request do
  @moduledoc """
  Technical adapter that translates a Workspace invitation into Platform's
  durable delivery request.

  The adapter encrypts the bearer token and persists no Workspace business
  decision of its own.
  """

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.EncryptedBinary

  require Logger

  @delivery_context "workspace"

  def enqueue(encoded_token, opts \\ []) do
    with {:ok, encrypted_token} <- encrypt_token(encoded_token) do
      %{
        context: @delivery_context,
        encrypted_token: encrypted_token,
        inviter_name: Keyword.get(opts, :inviter_name),
        locale: Gettext.get_locale(Storyarn.Gettext)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
      |> Platform.enqueue_invitation_delivery()
    end
  end

  defp encrypt_token(encoded_token) do
    encryptor =
      Application.get_env(:storyarn, :invitation_token_encryptor, EncryptedBinary)

    case encryptor.dump(encoded_token) do
      {:ok, encrypted_token} ->
        {:ok, Base.encode64(encrypted_token)}

      _error ->
        Logger.error("Invitation token encryption failed")
        {:error, :encryption_unavailable}
    end
  rescue
    error ->
      Logger.error("Invitation token encryption failed: #{Exception.message(error)}")
      {:error, :encryption_unavailable}
  end
end

defmodule Storyarn.Platform.Shared.EncryptedBinary do
  @moduledoc """
  Encrypted binary type for Ecto schemas.

  Data is automatically encrypted when stored and decrypted when loaded.
  """
  use Cloak.Ecto.Binary, vault: Storyarn.Platform.Vault
end

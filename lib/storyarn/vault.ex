defmodule Storyarn.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest.

  Used to encrypt sensitive fields in the database.
  """
  use Cloak.Vault, otp_app: :storyarn
end

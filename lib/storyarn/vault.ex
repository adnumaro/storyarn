defmodule Storyarn.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest.

  Used to encrypt OAuth tokens and other sensitive fields in the database.
  """
  use Cloak.Vault, otp_app: :storyarn
end

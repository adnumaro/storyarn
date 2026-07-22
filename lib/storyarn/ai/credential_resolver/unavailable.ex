defmodule Storyarn.AI.CredentialResolver.Unavailable do
  @moduledoc false
  @behaviour Storyarn.AI.CredentialResolver

  @impl true
  def resolve(_ref), do: {:error, :credential_unavailable}
end

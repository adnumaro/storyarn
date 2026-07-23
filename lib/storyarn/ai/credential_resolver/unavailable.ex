defmodule Storyarn.AI.CredentialResolver.Unavailable do
  @moduledoc false
  @behaviour Storyarn.AI.CredentialResolver

  @impl true
  def resolve(_ref, _context), do: {:error, :credential_unavailable}

  @impl true
  def record_outcome(_credential, _outcome), do: :ok
end

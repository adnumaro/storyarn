defmodule Storyarn.AI.CredentialResolver.Managed do
  @moduledoc "Resolves provider-scoped operator credentials without persisting them."
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: :managed, reference: reference}, _context) do
    config = Application.get_env(:storyarn, __MODULE__, [])

    with credentials when is_map(credentials) <- config[:credentials],
         api_key when is_binary(api_key) <- Map.get(credentials, reference),
         true <- byte_size(api_key) > 0 do
      {:ok, %ResolvedCredential{kind: :managed, value: api_key}}
    else
      _unavailable -> {:error, :credential_unavailable}
    end
  end

  def resolve(_ref, _context), do: {:error, :credential_unavailable}

  @impl true
  def record_outcome(_credential, _outcome), do: :ok
end

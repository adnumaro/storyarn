defmodule Storyarn.AI.CredentialResolver.Managed do
  @moduledoc "Resolves the single operator-configured managed credential without persisting it."
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: :managed, reference: reference}) do
    config = Application.get_env(:storyarn, __MODULE__, [])

    with ^reference <- config[:reference],
         api_key when is_binary(api_key) <- config[:api_key],
         true <- byte_size(api_key) > 0 do
      {:ok, %ResolvedCredential{kind: :managed, value: api_key}}
    else
      _unavailable -> {:error, :credential_unavailable}
    end
  end

  def resolve(_ref), do: {:error, :credential_unavailable}
end

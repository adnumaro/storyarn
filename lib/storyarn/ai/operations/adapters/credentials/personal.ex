defmodule Storyarn.AI.CredentialResolver.Personal do
  @moduledoc "Checks out only the initiating actor's active, consented personal integration."
  @behaviour Storyarn.AI.CredentialResolver

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.Integrations
  alias Storyarn.AI.ResolvedCredential

  @impl true
  def resolve(%CredentialRef{kind: :personal_byok}, %{operation: operation, task: task, route: route}) do
    case Integrations.checkout_operation(operation, task, route, lock: true) do
      {:ok, integration} ->
        {:ok,
         %ResolvedCredential{
           kind: :personal_byok,
           value: integration.api_key_encrypted,
           metadata: %{
             integration_id: integration.id,
             provider: integration.provider,
             owner_id: integration.user_id
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def resolve(_ref, _context), do: {:error, :credential_unavailable}

  @impl true
  def record_outcome(%ResolvedCredential{kind: :personal_byok, metadata: %{integration_id: integration_id}}, outcome) do
    Integrations.record_provider_outcome(integration_id, outcome)
  end

  def record_outcome(_credential, _outcome), do: :ok
end

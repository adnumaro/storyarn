defmodule Storyarn.AI.CredentialResolver.Personal do
  @moduledoc "Checks out only the initiating actor's active, consented personal integration."
  @behaviour Storyarn.AI.CredentialResolver

  import Ecto.Query

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.ResolvedCredential
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @impl true
  def resolve(%CredentialRef{kind: :personal_byok}, %{operation: operation, task: task, route: route}) do
    case PersonalConsents.checkout_operation(operation, task, route, lock: true) do
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
  def record_outcome(%ResolvedCredential{kind: :personal_byok, metadata: %{integration_id: integration_id}}, {:ok, _}) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(integration in Integration,
        where: integration.id == ^integration_id and is_nil(integration.revoked_at)
      ),
      set: [last_used_at: now, updated_at: now]
    )

    :ok
  end

  def record_outcome(
        %ResolvedCredential{kind: :personal_byok, metadata: %{integration_id: integration_id}},
        {:error, :unauthorized}
      ) do
    case Repo.get(Integration, integration_id) do
      %Integration{} = integration ->
        case IntegrationCrud.revoke_active(integration, :auto_revoked) do
          {:ok, _revoked} -> :ok
          {:error, _reason} -> :ok
        end

      nil ->
        :ok
    end
  end

  def record_outcome(_credential, _outcome), do: :ok
end

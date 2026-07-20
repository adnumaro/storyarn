defmodule Storyarn.AI.IntegrationCrud do
  @moduledoc """
  Create / read / revoke operations for `Storyarn.AI.Integration`.

  The `connect/3` function is the security-critical entry point: it validates
  the API key against the provider BEFORE persisting anything, records an
  audit row on both success and failure paths, and rejects reuse if the user
  already has an active integration for the provider.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Storyarn.Accounts.User
  alias Storyarn.AI.Audit
  alias Storyarn.AI.Integration
  alias Storyarn.AI.Provider
  alias Storyarn.AI.Providers
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @type connect_error ::
          :unknown_provider
          | :already_connected
          | Provider.validation_error()
          | Ecto.Changeset.t()

  @doc "Active integrations for a user, ordered by provider name."
  @spec list_active(User.t() | integer()) :: [Integration.t()]
  def list_active(%User{id: user_id}), do: list_active(user_id)

  def list_active(user_id) when is_integer(user_id) do
    Repo.all(from(i in Integration, where: i.user_id == ^user_id and is_nil(i.revoked_at), order_by: [asc: i.provider]))
  end

  @doc "Fetch a single active integration by user and provider."
  @spec get_active(User.t() | integer(), Provider.id() | String.t()) ::
          Integration.t() | nil
  def get_active(user_or_id, provider) do
    user_id = user_id_of(user_or_id)
    provider_str = to_string(provider)

    Repo.one(
      from(i in Integration, where: i.user_id == ^user_id and i.provider == ^provider_str and is_nil(i.revoked_at))
    )
  end

  @doc """
  Validate the key against the provider, then persist the encrypted key.

  Returns `{:error, :already_connected}` if the user already has an active
  integration for this provider — the caller should disconnect first.
  """
  @spec connect(User.t(), Provider.id() | String.t(), String.t()) ::
          {:ok, Integration.t()} | {:error, connect_error()}
  def connect(%User{id: user_id} = _user, provider, api_key) when is_binary(api_key) do
    with {:ok, adapter} <- Providers.adapter_for(provider),
         :ok <- ensure_not_connected(user_id, adapter.metadata().id),
         {:ok, account_info} <- validate_key(user_id, adapter, api_key),
         {:ok, integration} <- insert_integration(user_id, adapter, api_key, account_info) do
      Audit.log(user_id, adapter.metadata().id, :connected, %{})
      {:ok, integration}
    end
  end

  @doc "Mark an integration as revoked. Preserves history."
  @spec revoke(Integration.t()) :: {:ok, Integration.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%Integration{} = integration) do
    now = TimeHelpers.now()

    Multi.new()
    |> Multi.update(:revoke, Integration.revoke_changeset(integration, now))
    |> Multi.run(:audit, fn _repo, _changes ->
      Audit.log(integration.user_id, integration.provider, :disconnected, %{})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{revoke: updated}} -> {:ok, updated}
      {:error, :revoke, changeset, _changes} -> {:error, changeset}
    end
  end

  # -- private ---------------------------------------------------------------

  defp user_id_of(%User{id: id}), do: id
  defp user_id_of(id) when is_integer(id), do: id

  defp ensure_not_connected(user_id, provider_id) do
    if Repo.exists?(active_query(user_id, provider_id)) do
      {:error, :already_connected}
    else
      :ok
    end
  end

  defp active_query(user_id, provider_id) do
    from(i in Integration,
      where:
        i.user_id == ^user_id and
          i.provider == ^Atom.to_string(provider_id) and
          is_nil(i.revoked_at)
    )
  end

  defp validate_key(user_id, adapter, api_key) do
    case adapter.validate_key(api_key) do
      {:ok, account_info} ->
        {:ok, account_info}

      {:error, reason} = err ->
        Audit.log(user_id, adapter.metadata().id, :validation_failed, %{
          reason: reason_to_metadata(reason)
        })

        err
    end
  end

  defp insert_integration(user_id, adapter, api_key, account_info) do
    now = TimeHelpers.now()

    attrs = %{
      user_id: user_id,
      provider: Atom.to_string(adapter.metadata().id),
      api_key_encrypted: api_key,
      key_last_four: last_four(api_key),
      account_email: Map.get(account_info, :account_email),
      account_display_name: Map.get(account_info, :account_display_name),
      connected_at: now,
      last_validated_at: now
    }

    %Integration{}
    |> Integration.connect_changeset(attrs)
    |> Repo.insert()
  end

  defp last_four(api_key) when byte_size(api_key) >= 4 do
    String.slice(api_key, -4, 4)
  end

  defp last_four(_api_key), do: "----"

  defp reason_to_metadata({:unexpected_status, status}), do: %{unexpected_status: status}
  defp reason_to_metadata(reason) when is_atom(reason), do: %{reason: Atom.to_string(reason)}
end

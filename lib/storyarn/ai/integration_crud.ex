defmodule Storyarn.AI.IntegrationCrud do
  @moduledoc """
  Create / read / revoke operations for `Storyarn.AI.Integration`.

  The `connect/3` function is the security-critical entry point: it validates
  the API key against the provider BEFORE persisting anything, records an
  audit row on both success and failure paths, and rejects reuse if the user
  already has an active integration for the provider.

  Revocation is a conditional update on `revoked_at IS NULL`, so concurrent
  revokes (user click + runtime auto-revoke) transition exactly once and
  produce exactly one audit row.
  """

  import Ecto.Query

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Audit
  alias Storyarn.AI.Integration
  alias Storyarn.AI.Provider
  alias Storyarn.AI.Providers
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @unique_index_name "ai_integrations_user_provider_active_index"

  @type connect_error ::
          :unknown_provider
          | :already_connected
          | Provider.validation_error()
          | Ecto.Changeset.t()

  @doc "Active integrations for a user, ordered by provider name."
  @spec list_active(User.t() | integer()) :: [Integration.t()]
  def list_active(%User{id: user_id}), do: list_active(user_id)

  def list_active(user_id) when is_integer(user_id) do
    Repo.all(
      from(i in Integration,
        where: i.user_id == ^user_id and is_nil(i.revoked_at),
        order_by: [asc: i.provider]
      )
    )
  end

  @doc "Fetch a single active integration by user and provider."
  @spec get_active(User.t() | integer(), Provider.id() | String.t()) ::
          Integration.t() | nil
  def get_active(user_or_id, provider) do
    user_id = user_id_of(user_or_id)
    provider_str = to_string(provider)

    Repo.one(
      from(i in Integration,
        where: i.user_id == ^user_id and i.provider == ^provider_str and is_nil(i.revoked_at)
      )
    )
  end

  @doc """
  Validate the key against the provider, then persist the encrypted key.

  Returns `{:error, :already_connected}` if the user already has an active
  integration for this provider — both from the pre-check and from the
  database unique index when two connects race past the pre-check.
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

  @doc """
  Mark an integration as revoked (user-initiated disconnect).

  Idempotent under concurrency: returns `{:error, :already_revoked}` when
  another process already revoked it, and writes the audit row only on the
  actual transition.
  """
  @spec revoke(Integration.t()) :: {:ok, Integration.t()} | {:error, :already_revoked}
  def revoke(%Integration{} = integration), do: revoke_active(integration, :disconnected)

  @doc """
  Conditional revoke shared by user disconnect (`:disconnected`) and runtime
  auto-revocation (`:auto_revoked`). Audit failures are non-fatal — see
  `Storyarn.AI.Audit`.
  """
  @spec revoke_active(Integration.t(), :disconnected | :auto_revoked) ::
          {:ok, Integration.t()} | {:error, :already_revoked}
  def revoke_active(%Integration{} = integration, action) do
    now = TimeHelpers.now()

    {count, _} =
      Repo.update_all(
        from(i in Integration, where: i.id == ^integration.id and is_nil(i.revoked_at)),
        set: [revoked_at: now, updated_at: now]
      )

    case count do
      1 ->
        Audit.log(integration.user_id, integration.provider, action, %{})
        {:ok, %{integration | revoked_at: now}}

      0 ->
        {:error, :already_revoked}
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
        Audit.log(user_id, adapter.metadata().id, :validation_failed, reason_metadata(reason))
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
    |> normalize_insert_error()
  end

  # Two connects racing past the pre-check hit the partial unique index; the
  # loser gets the same :already_connected as the pre-check path.
  defp normalize_insert_error({:error, %Ecto.Changeset{errors: errors}} = result) do
    unique_race? =
      Enum.any?(errors, fn {_field, {_msg, opts}} ->
        opts[:constraint_name] == @unique_index_name
      end)

    if unique_race?, do: {:error, :already_connected}, else: result
  end

  defp normalize_insert_error(result), do: result

  defp last_four(api_key) when byte_size(api_key) >= 4 do
    String.slice(api_key, -4, 4)
  end

  defp last_four(_api_key), do: "----"

  defp reason_metadata({:unexpected_status, status}), do: %{unexpected_status: status}
  defp reason_metadata(reason) when is_atom(reason), do: %{reason: Atom.to_string(reason)}
end

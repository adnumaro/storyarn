defmodule Storyarn.AI.PersonalConsents do
  @moduledoc "Consent lifecycle and execution-time authorization for personal BYOK."

  import Ecto.Query

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationAssignments
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.PersonalConsent
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @default_policy_text_version "personal-egress-v1"

  @spec policy_text_version() :: String.t()
  def policy_text_version do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:policy_text_version, @default_policy_text_version)
  end

  @spec grant(ExecutionIntent.t(), pos_integer(), String.t()) ::
          {:ok, PersonalConsent.t()} | {:error, atom() | Ecto.Changeset.t()}
  def grant(%ExecutionIntent{} = intent, integration_id, expected_policy_text_version)
      when is_integer(integration_id) and integration_id > 0 and is_binary(expected_policy_text_version) do
    fn ->
      with {:ok, task} <- TaskRegistry.fetch(intent.task_id),
           true <- task.personal_byok_allowed? || {:error, :personal_byok_not_supported},
           :ok <- attended(intent),
           {:ok, _decision} <-
             PolicyDecision.authorize(intent, task, :execute, lane: :personal_byok, lock_policy: true),
           true <- expected_policy_text_version == policy_text_version() || {:error, :consent_version_stale},
           %Integration{} = integration <- lock_owned_integration(integration_id, intent.scope.user.id),
           {:ok, %IntegrationWorkspaceAssignment{}} <-
             active_assignment(
               intent.scope.user.id,
               intent.workspace_id,
               integration.id,
               lock: true
             ),
           {:ok, _provider} <- compatible_provider(integration.provider, task.capability, integration) do
        get_or_insert(intent, integration, task)
      else
        nil -> Repo.rollback(:integration_unavailable)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> unwrap_transaction()
  end

  def grant(%ExecutionIntent{}, _integration_id, _version), do: {:error, :invalid_consent}

  @spec revoke(Storyarn.Accounts.Scope.t(), pos_integer()) ::
          {:ok, PersonalConsent.t()} | {:error, :not_found}
  def revoke(%{user: %{id: user_id}}, consent_id) when is_integer(consent_id) and consent_id > 0 do
    Repo.transaction(fn ->
      consent =
        Repo.one(
          from(consent in PersonalConsent,
            where: consent.id == ^consent_id and consent.user_id == ^user_id and is_nil(consent.revoked_at),
            lock: "FOR UPDATE"
          )
        )

      case consent do
        %PersonalConsent{} -> consent |> PersonalConsent.revoke_changeset(TimeHelpers.now()) |> Repo.update!()
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  def revoke(_scope, _consent_id), do: {:error, :not_found}

  @doc false
  def active_for(user_id, workspace_id, integration_id, task, opts \\ []) do
    query =
      from(consent in PersonalConsent,
        where:
          consent.user_id == ^user_id and consent.workspace_id == ^workspace_id and
            consent.integration_id == ^integration_id and consent.capability == ^Atom.to_string(task.capability) and
            consent.cost_class == ^task.personal_cost_class and
            consent.policy_text_version == ^policy_text_version() and is_nil(consent.revoked_at)
      )

    query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  @doc false
  def authorize_operation(operation, task, route, opts \\ [])

  def authorize_operation(operation, task, %ExecutionRoute{lane: :personal_byok} = route, opts) do
    case checkout_operation(operation, task, route, opts) do
      {:ok, _integration} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_operation(_operation, _task, %ExecutionRoute{}, _opts), do: :ok

  @doc false
  def checkout_operation(operation, task, %ExecutionRoute{lane: :personal_byok} = route, opts \\ []) do
    lock? = Keyword.get(opts, :lock, false)

    with :ok <- attended_operation(operation),
         true <- task.personal_byok_allowed? || {:error, :personal_byok_not_supported},
         {:ok, integration_id} <- integration_id(route.credential_ref),
         {:ok, integration} <-
           owned_integration(integration_id, operation.actor_id, route.provider, lock?),
         {:ok, _assignment} <-
           IntegrationAssignments.authorize_route(
             operation.actor_id,
             operation.workspace_id_snapshot,
             integration,
             route.provider_configuration,
             lock: lock?
           ),
         {:ok, provider_config} <-
           compatible_provider(route.provider, route.model, task.capability, integration),
         :ok <- validate_route_configuration(route.provider_configuration, integration, task, provider_config),
         {:ok, consent} <-
           active_consent(operation.actor_id, operation.workspace_id_snapshot, integration.id, task, lock?),
         true <-
           consent.id == route.provider_configuration["personal_consent_id"] ||
             {:error, :consent_revoked} do
      {:ok, integration}
    else
      false -> {:error, :consent_revoked}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def revoke_for_integration(integration_id, revoked_at) do
    Repo.update_all(
      from(consent in PersonalConsent,
        where: consent.integration_id == ^integration_id and is_nil(consent.revoked_at)
      ),
      set: [revoked_at: revoked_at, updated_at: revoked_at]
    )
  end

  defp get_or_insert(intent, integration, task) do
    case active_for(intent.scope.user.id, intent.workspace_id, integration.id, task, lock: true) do
      %PersonalConsent{} = consent ->
        consent

      nil ->
        attrs = %{
          user_id: intent.scope.user.id,
          workspace_id: intent.workspace_id,
          integration_id: integration.id,
          provider: integration.provider,
          capability: Atom.to_string(task.capability),
          cost_class: task.personal_cost_class,
          policy_text_version: policy_text_version(),
          granted_at: TimeHelpers.now()
        }

        case %PersonalConsent{} |> PersonalConsent.grant_changeset(attrs) |> Repo.insert() do
          {:ok, consent} -> consent
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp lock_owned_integration(integration_id, user_id) do
    Repo.one(
      from(integration in Integration,
        where: integration.id == ^integration_id and integration.user_id == ^user_id and is_nil(integration.revoked_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp owned_integration(integration_id, user_id, provider, lock?) do
    query =
      from(integration in Integration,
        where:
          integration.id == ^integration_id and integration.user_id == ^user_id and
            integration.provider == ^provider and is_nil(integration.revoked_at)
      )

    query = if lock?, do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      %Integration{} = integration -> {:ok, integration}
      nil -> {:error, :integration_unavailable}
    end
  end

  defp active_consent(user_id, workspace_id, integration_id, task, lock?) do
    case active_for(user_id, workspace_id, integration_id, task, lock: lock?) do
      %PersonalConsent{} = consent -> {:ok, consent}
      nil -> {:error, :consent_revoked}
    end
  end

  defp compatible_provider(provider, capability, integration) do
    configs =
      capability
      |> PersonalProviders.for_capability()
      |> Enum.filter(&(&1.provider == provider))

    case Enum.find(configs, &(PersonalProviders.model_status(&1, integration) == :ready)) do
      nil -> {:error, unavailable_provider_reason(configs, integration)}
      config -> {:ok, config}
    end
  end

  defp compatible_provider(provider, model, capability, integration) do
    with {:ok, config} <- PersonalProviders.fetch(provider, model),
         true <- capability in config.catalog.capabilities,
         :ready <- PersonalProviders.model_status(config, integration) do
      {:ok, config}
    else
      false -> {:error, :capability_mismatch}
      {:error, :provider_unavailable} -> {:error, :model_unavailable}
      status when status in [:model_deprecated, :model_unavailable] -> {:error, status}
      _unavailable -> {:error, :capability_mismatch}
    end
  end

  defp unavailable_provider_reason([], _integration), do: :capability_mismatch

  defp unavailable_provider_reason(configs, integration) do
    statuses = Enum.map(configs, &PersonalProviders.model_status(&1, integration))

    if Enum.all?(statuses, &(&1 == :model_deprecated)),
      do: :model_deprecated,
      else: :model_unavailable
  end

  defp attended(%ExecutionIntent{scheduled?: false}), do: :ok
  defp attended(%ExecutionIntent{}), do: {:error, :personal_byok_unattended}

  defp attended_operation(%{policy_decision: %{"scheduled" => true}}), do: {:error, :personal_byok_unattended}

  defp attended_operation(_operation), do: :ok

  defp active_assignment(user_id, workspace_id, integration_id, opts) do
    case IntegrationAssignments.active_for(user_id, workspace_id, integration_id, opts) do
      %IntegrationWorkspaceAssignment{} = assignment -> {:ok, assignment}
      nil -> {:error, :assignment_required}
    end
  end

  defp validate_route_configuration(configuration, integration, task, provider_config) when is_map(configuration) do
    if route_configuration_valid?(configuration, integration, task, provider_config) do
      :ok
    else
      {:error, :consent_revoked}
    end
  end

  defp validate_route_configuration(_configuration, _integration, _task, _provider_config), do: {:error, :consent_revoked}

  defp route_configuration_valid?(configuration, integration, task, provider_config) do
    Enum.all?([
      configuration["personal_consent_version"] == policy_text_version(),
      configuration["capability"] == Atom.to_string(task.capability),
      configuration["cost_class"] == task.personal_cost_class,
      configuration["integration_id"] == integration.id,
      is_integer(configuration["workspace_assignment_id"]),
      configuration["model_catalog_version"] == provider_config.catalog.catalog_version,
      configuration["model_pricing_version"] == provider_config.catalog.pricing_version,
      configuration["data_scope"] == Atom.to_string(task.data_scope),
      configuration["processing_location"] == provider_config.processing_location,
      configuration["response_mode"] == provider_config.response_mode
    ])
  end

  defp integration_id(%CredentialRef{kind: :personal_byok, reference: reference}) do
    case Integer.parse(reference) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> {:error, :invalid_credential_ref}
    end
  end

  defp integration_id(_ref), do: {:error, :invalid_credential_ref}

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end

defmodule Storyarn.AI.PersonalPreferences do
  @moduledoc """
  Actor/workspace-scoped provider and model preferences for personal AI.

  Preference writes require an active actor-owned connection, an active
  workspace assignment, current workspace eligibility, and a curated model.
  Configuration-only media models may be saved ahead of their dedicated
  execution slice, but the resolver never treats them as executable. Reads
  preserve broken preferences as explicit repair states.
  """

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.Audit
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationAssignments
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.ModelCatalog.Entry
  alias Storyarn.AI.PersonalPreference
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.PersonalRoles
  alias Storyarn.AI.Policy
  alias Storyarn.AI.Providers
  alias Storyarn.AI.Task
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.FeatureFlags
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @lock_namespace 981_007

  @type mutation_error ::
          :feature_disabled
          | :workspace_unavailable
          | :workspace_policy_disabled
          | :integration_unavailable
          | :assignment_required
          | :model_unavailable
          | :model_deprecated
          | :capability_mismatch
          | :invalid_preference_slot
          | :preference_not_found
          | Ecto.Changeset.t()

  @spec overview(Scope.t()) :: {:ok, map()} | {:error, mutation_error()}
  def overview(%Scope{user: %{id: user_id}} = scope) do
    with :ok <- feature_enabled(scope) do
      workspace_entries = Workspaces.list_workspaces(scope)
      workspace_ids = Enum.map(workspace_entries, & &1.workspace.id)
      data = overview_data(user_id, workspace_ids)

      workspaces =
        Enum.map(workspace_entries, fn %{workspace: workspace, role: role} ->
          overview_workspace(workspace, role, data)
        end)

      {:ok, %{workspaces: workspaces}}
    end
  end

  @spec summary(Scope.t(), pos_integer()) :: {:ok, map()} | {:error, mutation_error()}
  def summary(%Scope{user: %{id: user_id}} = scope, workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    with :ok <- feature_enabled(scope),
         {:ok, workspace, membership} <- workspace_access(scope, workspace_id),
         :ok <- require_workspace_membership(membership.role) do
      policy = Policy.get_effective(workspace.id)
      policy_allowed? = eligible?(membership.role, policy)
      preferences = preferences_by_slot(user_id, workspace.id)
      options = if policy_allowed?, do: available_options(user_id, workspace.id), else: []

      slots =
        Enum.map(PersonalRoles.public_slots(), fn definition ->
          slot = String.to_existing_atom(definition.slot)
          preference = Map.get(preferences, slot)
          slot_options = Enum.filter(options, &PersonalRoles.assignable?(slot, &1.catalog))

          Map.merge(definition, %{
            preference: public_preference(preference, policy_allowed?),
            options: Enum.map(slot_options, &public_option/1)
          })
        end)

      {:ok,
       %{
         workspace: %{id: workspace.id, name: workspace.name, slug: workspace.slug},
         policy_allowed: policy_allowed?,
         slots: slots
       }}
    end
  end

  def summary(%Scope{}, _workspace_id), do: {:error, :workspace_unavailable}

  @doc """
  Return the actor-visible role preferences affected by one actor-owned active
  integration.

  This is a read-only impact report for credential rotation. It exposes no
  credential material and keeps broken selections visible as repair states.
  """
  @spec impacts(Scope.t(), pos_integer()) :: {:ok, [map()]} | {:error, mutation_error()}
  def impacts(%Scope{user: %{id: user_id}} = scope, integration_id)
      when is_integer(integration_id) and integration_id > 0 do
    with :ok <- feature_enabled(scope),
         %Integration{revoked_at: nil} <- get_integration(user_id, integration_id) do
      impacts =
        from(preference in PersonalPreference,
          join: workspace in Workspace,
          on: workspace.id == preference.workspace_id,
          join: membership in WorkspaceMembership,
          on:
            membership.workspace_id == preference.workspace_id and
              membership.user_id == preference.user_id,
          where:
            preference.user_id == ^user_id and
              preference.integration_id == ^integration_id,
          order_by: [asc: workspace.name, asc: preference.slot],
          select: {preference, workspace, membership.role}
        )
        |> Repo.all()
        |> Enum.map(fn {preference, workspace, role} ->
          policy_allowed? = eligible?(role, Policy.get_effective(workspace.id))

          %{
            preference_id: preference.id,
            workspace_id: workspace.id,
            workspace_name: workspace.name,
            workspace_slug: workspace.slug,
            slot: preference.slot,
            provider: preference.provider,
            model: preference.model,
            implementation_status: implementation_status(preference.provider, preference.model),
            status: Atom.to_string(preference_status(preference, policy_allowed?))
          }
        end)

      {:ok, impacts}
    else
      {:error, :feature_disabled} = error -> error
      _unavailable -> {:error, :integration_unavailable}
    end
  end

  def impacts(%Scope{}, _integration_id), do: {:error, :integration_unavailable}

  @spec put(Scope.t(), pos_integer(), atom() | String.t(), pos_integer(), String.t()) ::
          {:ok, PersonalPreference.t()} | {:error, mutation_error()}
  def put(%Scope{user: %{id: user_id}} = scope, workspace_id, slot, integration_id, model)
      when is_integer(workspace_id) and workspace_id > 0 and is_integer(integration_id) and integration_id > 0 and
             is_binary(model) do
    with :ok <- feature_enabled(scope),
         {:ok, slot} <- PersonalRoles.normalize_slot(slot) do
      fn -> put_locked(scope, user_id, workspace_id, slot, integration_id, model) end
      |> Repo.transaction()
      |> unwrap_transaction()
    end
  end

  def put(%Scope{}, _workspace_id, _slot, _integration_id, _model), do: {:error, :integration_unavailable}

  @spec delete(Scope.t(), pos_integer(), atom() | String.t()) ::
          {:ok, PersonalPreference.t()} | {:error, mutation_error()}
  def delete(%Scope{user: %{id: user_id}} = scope, workspace_id, slot)
      when is_integer(workspace_id) and workspace_id > 0 do
    with :ok <- feature_enabled(scope),
         {:ok, slot} <- PersonalRoles.normalize_slot(slot) do
      fn -> delete_locked(scope, user_id, workspace_id, slot) end
      |> Repo.transaction()
      |> unwrap_transaction()
    end
  end

  def delete(%Scope{}, _workspace_id, _slot), do: {:error, :preference_not_found}

  defp put_locked(scope, user_id, workspace_id, slot, integration_id, model) do
    with {:ok, workspace, membership} <- workspace_access(scope, workspace_id),
         policy = Policy.get_effective(workspace.id, lock: true),
         :ok <- require_eligible(membership.role, policy),
         {:ok, integration} <- owned_active_integration(user_id, integration_id),
         {:ok, _assignment} <-
           active_assignment(user_id, workspace.id, integration.id, lock: true),
         {:ok, entry} <- ModelCatalog.fetch(integration.provider, String.trim(model)),
         :ok <- authorize_model(entry, integration),
         :ok <- configurable_provider(integration.provider, entry.model),
         true <- PersonalRoles.assignable?(slot, entry) || {:error, :capability_mismatch} do
      lock_preference!(user_id, workspace.id, slot)
      upsert_preference(user_id, workspace.id, slot, integration, entry.model)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp delete_locked(scope, user_id, workspace_id, slot) do
    with {:ok, workspace, membership} <- workspace_access(scope, workspace_id),
         :ok <- require_workspace_membership(membership.role),
         {:ok, preference} <- locked_preference(user_id, workspace.id, slot),
         {:ok, deleted} <- Repo.delete(preference) do
      audit!(deleted, :preference_deleted)
      deleted
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp locked_preference(user_id, workspace_id, slot) do
    case lock_preference(user_id, workspace_id, slot) do
      %PersonalPreference{} = preference -> {:ok, preference}
      nil -> {:error, :preference_not_found}
    end
  end

  @doc false
  @spec resolve(pos_integer(), pos_integer(), Task.t()) :: map()
  def resolve(user_id, workspace_id, %Task{} = task) when is_integer(user_id) and is_integer(workspace_id) do
    case PersonalRoles.role_for_capability(task.capability) do
      role when role in [:general_assistant, :writing_assistant, :illustrator, :voice] ->
        resolve_role(user_id, workspace_id, role, task)

      _reserved_or_unknown ->
        %{
          status: :role_unavailable,
          slot: nil,
          assignment_source: nil,
          preference_id: nil,
          integration_id: nil,
          provider: nil,
          model: nil
        }
    end
  end

  @doc false
  @spec public_resolution(map()) :: map()
  def public_resolution(resolution) when is_map(resolution) do
    Map.take(resolution, [
      :status,
      :slot,
      :assignment_source,
      :preference_id,
      :integration_id,
      :provider,
      :model
    ])
  end

  defp resolve_role(user_id, workspace_id, role, task) do
    case get_preference(user_id, workspace_id, role) do
      %PersonalPreference{} = preference ->
        resolve_preference(preference, task, "personal_role")

      nil ->
        %{
          status: :choose_required,
          slot: role,
          assignment_source: nil,
          preference_id: nil,
          integration_id: nil,
          provider: nil,
          model: nil
        }
    end
  end

  defp resolve_preference(preference, task, assignment_source) do
    base = %{
      status: :ready,
      slot: String.to_existing_atom(preference.slot),
      assignment_source: assignment_source,
      preference_id: preference.id,
      integration_id: preference.integration_id,
      provider: preference.provider,
      model: preference.model
    }

    with %Integration{} = integration <-
           get_integration(preference.user_id, preference.integration_id),
         true <- is_nil(integration.revoked_at) || {:error, :provider_disconnected},
         %IntegrationWorkspaceAssignment{} = assignment <-
           IntegrationAssignments.active_for(
             preference.user_id,
             preference.workspace_id,
             preference.integration_id
           ),
         {:ok, entry} <- ModelCatalog.fetch(preference.provider, preference.model),
         true <- not entry.deprecated? || {:error, :model_deprecated},
         :ok <- normalize_model_authorization(ModelCatalog.authorize(entry, integration)),
         :ok <- executable_entry(entry),
         {:ok, config} <- provider_config(preference.provider, preference.model),
         true <- PersonalRoles.supports_task?(entry, task.capability) || {:error, :capability_mismatch},
         true <-
           PersonalRoles.assignable?(String.to_existing_atom(preference.slot), entry) ||
             {:error, :capability_mismatch} do
      Map.merge(base, %{
        integration: integration,
        workspace_assignment: assignment,
        catalog: entry,
        provider_config: config
      })
    else
      nil -> Map.put(base, :status, :assignment_required)
      false -> Map.put(base, :status, :capability_mismatch)
      {:error, reason} -> Map.put(base, :status, reason)
    end
  end

  defp upsert_preference(user_id, workspace_id, slot, integration, model) do
    attrs = %{
      user_id: user_id,
      workspace_id: workspace_id,
      integration_id: integration.id,
      slot: Atom.to_string(slot),
      provider: integration.provider,
      model: model
    }

    case lock_preference(user_id, workspace_id, slot) do
      %PersonalPreference{} = preference ->
        if same_route?(preference, attrs) do
          preference
        else
          preference
          |> PersonalPreference.update_route_changeset(attrs)
          |> Repo.update()
          |> finish_preference_write(:preference_updated)
        end

      nil ->
        %PersonalPreference{}
        |> PersonalPreference.create_changeset(attrs)
        |> Repo.insert()
        |> finish_preference_write(:preference_created)
    end
  end

  defp finish_preference_write({:ok, preference}, audit_action) do
    audit!(preference, audit_action)
    preference
  end

  defp finish_preference_write({:error, changeset}, _audit_action), do: Repo.rollback(changeset)

  defp same_route?(preference, attrs) do
    preference.integration_id == attrs.integration_id and
      preference.provider == attrs.provider and
      preference.model == attrs.model
  end

  defp overview_data(_user_id, []), do: %{policies: %{}, preferences: %{}, integrations: %{}, assignments: MapSet.new()}

  defp overview_data(user_id, workspace_ids) do
    policies =
      from(policy in WorkspacePolicy, where: policy.workspace_id in ^workspace_ids)
      |> Repo.all()
      |> Map.new(&{&1.workspace_id, &1})

    preferences =
      Repo.all(
        from(preference in PersonalPreference,
          where: preference.user_id == ^user_id and preference.workspace_id in ^workspace_ids
        )
      )

    integration_ids = preferences |> Enum.map(& &1.integration_id) |> Enum.uniq()

    integrations =
      from(integration in Integration,
        where:
          integration.user_id == ^user_id and
            integration.id in ^integration_ids
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    assignments =
      from(assignment in IntegrationWorkspaceAssignment,
        where:
          assignment.user_id == ^user_id and
            assignment.workspace_id in ^workspace_ids and
            assignment.integration_id in ^integration_ids and
            is_nil(assignment.revoked_at),
        select: {assignment.workspace_id, assignment.integration_id}
      )
      |> Repo.all()
      |> MapSet.new()

    %{
      policies: policies,
      preferences: Enum.group_by(preferences, & &1.workspace_id),
      integrations: integrations,
      assignments: assignments
    }
  end

  defp overview_workspace(workspace, role, data) do
    policy =
      Map.get(
        data.policies,
        workspace.id,
        %WorkspacePolicy{workspace_id: workspace.id, allowed_lanes: []}
      )

    policy_allowed? = eligible?(role, policy)
    can_configure? = policy_allowed?

    preferences =
      data.preferences
      |> Map.get(workspace.id, [])
      |> Map.new(&{String.to_existing_atom(&1.slot), &1})

    slots =
      Enum.map(PersonalRoles.public_slots(), fn definition ->
        slot = String.to_existing_atom(definition.slot)
        preference = Map.get(preferences, slot)

        definition
        |> Map.put(:available, role_available?(slot))
        |> Map.put(
          :preference,
          overview_preference(preference, role, policy_allowed?, data)
        )
      end)

    %{
      id: workspace.id,
      name: workspace.name,
      slug: workspace.slug,
      role: role,
      policy_allowed: policy_allowed?,
      can_configure: can_configure?,
      slots: slots
    }
  end

  defp overview_preference(nil, _role, _policy_allowed?, _data), do: nil
  defp overview_preference(_preference, nil, _policy_allowed?, _data), do: nil

  defp overview_preference(preference, role, policy_allowed?, data) do
    status = overview_preference_status(preference, role, policy_allowed?, data)

    %{
      provider: preference.provider,
      provider_name: provider_name(preference.provider),
      model: preference.model,
      implementation_status: implementation_status(preference.provider, preference.model),
      status: Atom.to_string(status),
      payer: "personal_provider_account"
    }
  end

  defp overview_preference_status(_preference, nil, _policy_allowed?, _data), do: :workspace_access_limited

  defp overview_preference_status(_preference, _role, false, _data), do: :workspace_policy_denied

  defp overview_preference_status(preference, _role, true, data) do
    slot = String.to_existing_atom(preference.slot)
    integration = Map.get(data.integrations, preference.integration_id)

    with %Integration{} = integration <- integration,
         true <- is_nil(integration.revoked_at) || {:error, :provider_disconnected},
         true <-
           MapSet.member?(
             data.assignments,
             {preference.workspace_id, preference.integration_id}
           ) || {:error, :assignment_required},
         {:ok, entry} <- ModelCatalog.fetch(preference.provider, preference.model),
         true <- not entry.deprecated? || {:error, :model_deprecated},
         :ok <- normalize_model_authorization(ModelCatalog.authorize(entry, integration)),
         {:ok, config} <- configurable_provider_config(preference.provider, preference.model),
         true <- PersonalRoles.assignable?(slot, entry) || {:error, :capability_mismatch} do
      configuration_status(config)
    else
      nil -> :provider_disconnected
      {:error, reason} -> reason
    end
  end

  defp public_preference(nil, _policy_allowed?), do: nil

  defp public_preference(%PersonalPreference{} = preference, policy_allowed?) do
    status = preference_status(preference, policy_allowed?)

    %{
      id: preference.id,
      slot: preference.slot,
      integration_id: preference.integration_id,
      provider: preference.provider,
      provider_name: provider_name(preference.provider),
      model: preference.model,
      implementation_status: implementation_status(preference.provider, preference.model),
      status: Atom.to_string(status),
      payer: "personal_provider_account"
    }
  end

  defp preference_status(_preference, false), do: :workspace_policy_denied

  defp preference_status(preference, true) do
    slot = String.to_existing_atom(preference.slot)

    with %Integration{} = integration <-
           get_integration(preference.user_id, preference.integration_id),
         true <- is_nil(integration.revoked_at) || {:error, :provider_disconnected},
         {:ok, _assignment} <-
           active_assignment(
             preference.user_id,
             preference.workspace_id,
             preference.integration_id
           ),
         {:ok, entry} <- ModelCatalog.fetch(preference.provider, preference.model),
         true <- not entry.deprecated? || {:error, :model_deprecated},
         :ok <- normalize_model_authorization(ModelCatalog.authorize(entry, integration)),
         {:ok, config} <- configurable_provider_config(preference.provider, preference.model),
         true <- PersonalRoles.assignable?(slot, entry) || {:error, :capability_mismatch} do
      configuration_status(config)
    else
      nil -> :provider_disconnected
      {:error, reason} -> reason
    end
  end

  defp available_options(user_id, workspace_id) do
    user_id
    |> active_assigned_integrations(workspace_id)
    |> Enum.flat_map(&options_for_assignment/1)
    |> Enum.sort_by(&{provider_name(&1.integration.provider), &1.catalog.model})
  end

  defp options_for_assignment({integration, assignment}) do
    integration.provider
    |> ModelCatalog.for_provider(include_deprecated: false)
    |> Enum.flat_map(&option_for_entry(integration, assignment, &1))
  end

  defp option_for_entry(integration, assignment, entry) do
    with :ok <- normalize_model_authorization(ModelCatalog.authorize(entry, integration)),
         {:ok, config} <- configurable_provider_config(integration.provider, entry.model) do
      [
        %{
          integration: integration,
          assignment: assignment,
          catalog: entry,
          provider_config: config
        }
      ]
    else
      _unavailable -> []
    end
  end

  defp public_option(option) do
    %{
      integration_id: option.integration.id,
      assignment_id: option.assignment.id,
      provider: option.integration.provider,
      provider_name: provider_name(option.integration.provider),
      model: option.catalog.model,
      capabilities: Enum.map(option.catalog.capabilities, &Atom.to_string/1),
      input_modalities: Enum.map(option.catalog.input_modalities, &Atom.to_string/1),
      output_modalities: Enum.map(option.catalog.output_modalities, &Atom.to_string/1),
      implementation_status: Atom.to_string(option.catalog.implementation_status),
      release_stage: Atom.to_string(option.catalog.release_stage),
      payer: "personal_provider_account"
    }
  end

  defp preferences_by_slot(user_id, workspace_id) do
    from(preference in PersonalPreference,
      where:
        preference.user_id == ^user_id and
          preference.workspace_id == ^workspace_id
    )
    |> Repo.all()
    |> Map.new(&{String.to_existing_atom(&1.slot), &1})
  end

  defp active_assigned_integrations(user_id, workspace_id) do
    Repo.all(
      from(assignment in IntegrationWorkspaceAssignment,
        join: integration in Integration,
        on:
          integration.id == assignment.integration_id and
            integration.user_id == assignment.user_id,
        where:
          assignment.user_id == ^user_id and
            assignment.workspace_id == ^workspace_id and
            is_nil(assignment.revoked_at) and
            is_nil(integration.revoked_at),
        select: {integration, assignment}
      )
    )
  end

  defp get_preference(user_id, workspace_id, slot) do
    Repo.one(
      from(preference in PersonalPreference,
        where:
          preference.user_id == ^user_id and
            preference.workspace_id == ^workspace_id and
            preference.slot == ^Atom.to_string(slot)
      )
    )
  end

  defp lock_preference(user_id, workspace_id, slot) do
    Repo.one(
      from(preference in PersonalPreference,
        where:
          preference.user_id == ^user_id and
            preference.workspace_id == ^workspace_id and
            preference.slot == ^Atom.to_string(slot),
        lock: "FOR UPDATE"
      )
    )
  end

  defp owned_active_integration(user_id, integration_id) do
    case Repo.one(
           from(integration in Integration,
             where:
               integration.id == ^integration_id and
                 integration.user_id == ^user_id and
                 is_nil(integration.revoked_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Integration{} = integration -> {:ok, integration}
      nil -> {:error, :integration_unavailable}
    end
  end

  defp get_integration(user_id, integration_id) do
    Repo.one(
      from(integration in Integration,
        where:
          integration.id == ^integration_id and
            integration.user_id == ^user_id
      )
    )
  end

  defp lock_preference!(user_id, workspace_id, slot) do
    lock_key = :erlang.phash2({user_id, workspace_id, slot}, 2_147_483_647)
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, lock_key])
  end

  defp authorize_model(%Entry{deprecated?: true}, %Integration{}), do: {:error, :model_deprecated}

  defp authorize_model(%Entry{} = entry, %Integration{} = integration) do
    normalize_model_authorization(ModelCatalog.authorize(entry, integration))
  end

  defp normalize_model_authorization(:ok), do: :ok
  defp normalize_model_authorization({:error, :model_deprecated}), do: {:error, :model_deprecated}
  defp normalize_model_authorization({:error, :model_unavailable}), do: {:error, :model_unavailable}

  defp executable_entry(%Entry{implementation_status: :executable, api_family: :structured_text}), do: :ok

  defp executable_entry(%Entry{implementation_status: :configuration_only}), do: {:error, :configuration_only}

  defp executable_entry(%Entry{}), do: {:error, :model_unavailable}

  defp active_assignment(user_id, workspace_id, integration_id, opts \\ []) do
    case IntegrationAssignments.active_for(user_id, workspace_id, integration_id, opts) do
      %IntegrationWorkspaceAssignment{} = assignment -> {:ok, assignment}
      nil -> {:error, :assignment_required}
    end
  end

  defp executable_provider(provider, model) do
    case provider_config(provider, model) do
      {:ok, _config} -> :ok
      {:error, :model_unavailable} -> {:error, :model_unavailable}
    end
  end

  defp configurable_provider(provider, model) do
    case configurable_provider_config(provider, model) do
      {:ok, _config} -> :ok
      {:error, :model_unavailable} -> {:error, :model_unavailable}
    end
  end

  defp provider_config(provider, model) do
    case PersonalProviders.fetch(provider, model) do
      {:ok, config} -> {:ok, config}
      {:error, :provider_unavailable} -> {:error, :model_unavailable}
    end
  end

  defp configurable_provider_config(provider, model) do
    case PersonalProviders.fetch_configurable(provider, model) do
      {:ok, config} -> {:ok, config}
      {:error, :provider_unavailable} -> {:error, :model_unavailable}
    end
  end

  defp configuration_status(%{catalog: %{implementation_status: :configuration_only}}), do: :configured

  defp configuration_status(%{provider: provider, model: model}) do
    case executable_provider(provider, model) do
      :ok -> :ready
      {:error, :model_unavailable} -> :model_unavailable
    end
  end

  defp implementation_status(provider, model) do
    case ModelCatalog.fetch(provider, model) do
      {:ok, entry} -> Atom.to_string(entry.implementation_status)
      {:error, :model_unavailable} -> nil
    end
  end

  defp provider_name(provider) do
    case Enum.find(Providers.metadata_list(), &(Atom.to_string(&1.id) == provider)) do
      nil -> provider
      metadata -> metadata.name
    end
  end

  defp role_available?(slot) do
    slot
    |> PersonalRoles.required_capabilities()
    |> Enum.flat_map(&ModelCatalog.for_capability/1)
    |> Enum.uniq_by(&{&1.provider, &1.model})
    |> Enum.any?(fn entry ->
      PersonalRoles.assignable?(slot, entry) and
        not entry.deprecated? and
        configurable_provider(entry.provider, entry.model) == :ok
    end)
  end

  defp feature_enabled(%Scope{user: user}) do
    if FeatureFlags.enabled?(:ai_integrations, for: user),
      do: :ok,
      else: {:error, :feature_disabled}
  end

  defp workspace_access(scope, workspace_id) do
    case Workspaces.get_workspace(scope, workspace_id) do
      {:ok, workspace, membership} -> {:ok, workspace, membership}
      _error -> {:error, :workspace_unavailable}
    end
  end

  defp eligible?(nil, %WorkspacePolicy{}), do: false
  defp eligible?("owner", %WorkspacePolicy{}), do: true

  defp eligible?(role, %WorkspacePolicy{allowed_lanes: lanes}) do
    Workspaces.can?(role, :use_ai) and "personal_byok" in lanes
  end

  defp require_workspace_membership(nil), do: {:error, :workspace_unavailable}
  defp require_workspace_membership(role) when is_binary(role), do: :ok

  defp require_eligible(nil, %WorkspacePolicy{}), do: {:error, :workspace_unavailable}

  defp require_eligible(role, policy) do
    if eligible?(role, policy), do: :ok, else: {:error, :workspace_policy_disabled}
  end

  defp audit!(preference, action) do
    metadata = %{
      integration_id: preference.integration_id,
      workspace_id: preference.workspace_id,
      preference_id: preference.id,
      slot: preference.slot,
      model: preference.model
    }

    case Audit.log(preference.user_id, preference.provider, action, metadata) do
      {:ok, _audit} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end

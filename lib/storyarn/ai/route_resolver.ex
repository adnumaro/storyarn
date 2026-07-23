defmodule Storyarn.AI.RouteResolver do
  @moduledoc """
  Central provider-neutral route resolver.

  It emits only immutable, explicit choices. Actor/workspace role preferences
  select a primary personal route, but never trigger an automatic fallback.
  """

  alias Storyarn.AI.ConfigMap
  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.IntegrationAssignments
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalPreferences
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task

  @type resolution :: %{
          routes: [ExecutionRoute.t()],
          personal_choices: [map()],
          personal_preference: map()
        }

  @spec preflight_options(PolicyDecision.t(), Task.t()) :: resolution()
  def preflight_options(%PolicyDecision{} = decision, %Task{} = task) do
    personal = personal_resolution(decision, task)

    routes =
      Enum.flat_map(decision.allowed_lanes, fn
        :personal_byok ->
          ready_personal_routes(personal.choices)

        lane ->
          route_for_lane(lane, decision, task)
      end)

    %{
      routes: routes,
      personal_choices: personal.choices,
      personal_preference: personal.preference
    }
  end

  @spec routes(PolicyDecision.t(), Task.t()) :: [ExecutionRoute.t()]
  def routes(%PolicyDecision{} = decision, %Task{} = task) do
    preflight_options(decision, task).routes
  end

  @spec personal_choices(PolicyDecision.t(), Task.t()) :: [map()]
  def personal_choices(%PolicyDecision{} = decision, %Task{} = task) do
    personal_resolution(decision, task).choices
  end

  @spec personal_preference(PolicyDecision.t(), Task.t()) :: map()
  def personal_preference(%PolicyDecision{} = decision, %Task{} = task) do
    personal_resolution(decision, task).preference
  end

  defp personal_resolution(%PolicyDecision{} = decision, %Task{} = task) do
    if :personal_byok in decision.allowed_lanes and task.personal_byok_allowed? and not decision.scheduled? do
      preference = PersonalPreferences.resolve(decision.actor_id, decision.workspace_id, task)

      integrations =
        decision.actor_id
        |> IntegrationCrud.list_active()
        |> Map.new(&{&1.provider, &1})

      choices =
        task.capability
        |> PersonalProviders.for_capability()
        |> Enum.map(
          &personal_choice(
            &1,
            Map.get(integrations, &1.provider),
            decision,
            task,
            preference
          )
        )

      %{choices: choices, preference: public_preference(preference, choices)}
    else
      %{choices: [], preference: unavailable_personal_preference()}
    end
  end

  defp public_preference(resolution, choices) do
    status =
      case Enum.find(choices, &preference_choice?(&1, resolution)) do
        nil -> resolution.status
        choice -> choice.status
      end

    resolution
    |> PersonalPreferences.public_resolution()
    |> Map.put(:status, status)
  end

  defp unavailable_personal_preference do
    %{
      status: :not_available,
      slot: nil,
      assignment_source: nil,
      preference_id: nil,
      integration_id: nil,
      provider: nil,
      model: nil
    }
  end

  defp ready_personal_routes(choices) do
    Enum.flat_map(choices, fn
      %{status: :ready, route: route} -> [route]
      _blocked -> []
    end)
  end

  @spec current?(PolicyDecision.t(), Task.t(), ExecutionRoute.t()) :: boolean()
  def current?(%PolicyDecision{} = decision, %Task{} = task, %ExecutionRoute{} = route) do
    Enum.any?(routes(decision, task), &(&1 == route))
  end

  @spec managed_provenance() :: map() | nil
  def managed_provenance do
    config = config()[:managed]

    with true <- is_list(config),
         true <- config[:enabled] == true,
         true <- config[:verified_zdr] == true,
         true <- config[:verified_no_training] == true,
         provider when is_binary(provider) <- config[:provider],
         model when is_binary(model) <- config[:model],
         {:ok, provider_configuration} <- provider_configuration(config) do
      %{
        provider: provider,
        model: model,
        region: provider_configuration["region"],
        data_retention: provider_configuration["data_retention"],
        training_usage: provider_configuration["training_usage"]
      }
    else
      _unavailable -> nil
    end
  end

  defp route_for_lane(:managed, decision, task) do
    config = config()[:managed]

    with true <- is_list(config),
         true <- Settlement.available?(:managed),
         provider when is_binary(provider) <- config[:provider],
         model when is_binary(model) <- config[:model],
         true <- config[:enabled] == true,
         true <- config[:verified_zdr] == true,
         true <- config[:verified_no_training] == true,
         reference when is_binary(reference) <- config[:credential_ref],
         {:ok, credential_ref} <- CredentialRef.new(:managed, reference),
         {:ok, provider_configuration} <- provider_configuration(config),
         %{id: price_id, version: price_version, units: price_units} <- task.managed_price do
      [
        %ExecutionRoute{
          lane: :managed,
          provider: provider,
          model: model,
          credential_ref: credential_ref,
          payer: config[:payer] || "storyarn",
          assignment_source: config[:assignment_source] || "operator_default",
          consent_basis: config[:consent_basis] || "workspace_policy",
          policy_version: decision.policy_version,
          price_id: price_id,
          price_version: price_version,
          price_units: price_units,
          provider_configuration: provider_configuration
        }
      ]
    else
      _unavailable -> []
    end
  end

  defp route_for_lane(_lane, _decision, _task), do: []

  defp personal_choice(config, nil, _decision, task, preference) do
    status = if config.catalog.deprecated?, do: :model_deprecated, else: :connect_required
    choice(config, task, status, nil, nil, nil, preference)
  end

  defp personal_choice(config, integration, decision, task, preference) do
    assignment =
      IntegrationAssignments.active_for(
        decision.actor_id,
        decision.workspace_id,
        integration.id
      )

    if is_nil(assignment) do
      choice(config, task, :assignment_required, integration.id, nil, nil, preference)
    else
      personal_choice_with_assignment(
        config,
        integration,
        assignment,
        decision,
        task,
        preference
      )
    end
  end

  defp personal_choice_with_assignment(config, integration, assignment, decision, task, preference) do
    case PersonalProviders.model_status(config, integration) do
      :ready ->
        personal_choice_with_consent(
          config,
          integration,
          assignment,
          decision,
          task,
          preference
        )

      status when status in [:model_deprecated, :model_unavailable] ->
        choice(config, task, status, integration.id, assignment.id, nil, preference)
    end
  end

  defp personal_choice_with_consent(config, integration, assignment, decision, task, preference) do
    case PersonalConsents.active_for(decision.actor_id, decision.workspace_id, integration.id, task) do
      nil ->
        choice(
          config,
          task,
          :consent_required,
          integration.id,
          assignment.id,
          nil,
          preference
        )

      consent ->
        preferred_choice(
          config,
          integration,
          assignment,
          consent,
          decision,
          task,
          preference
        )
    end
  end

  defp preferred_choice(config, integration, assignment, consent, decision, task, preference) do
    assignment_source =
      if preference_match?(preference, config, integration),
        do: preference.assignment_source,
        else: "explicit_invocation"

    route =
      personal_route(
        config,
        integration,
        assignment,
        consent,
        decision,
        task,
        assignment_source,
        preference
      )

    choice(
      config,
      task,
      :ready,
      integration.id,
      assignment.id,
      route,
      preference
    )
  end

  defp choice(config, task, status, integration_id, assignment_id, route, preference) do
    preferred? =
      preference_match?(preference, config, %{id: integration_id})

    %{
      lane: :personal_byok,
      provider: config.provider,
      provider_name: config.metadata.name,
      model: config.model,
      payer: "personal_provider_account",
      status: status,
      integration_id: integration_id,
      workspace_assignment_id: assignment_id,
      capability: task.capability,
      cost_class: task.personal_cost_class,
      data_scope: task.data_scope,
      processing_location: config.processing_location,
      model_catalog: ModelCatalog.public_summary(config.catalog),
      consent_policy_version: PersonalConsents.policy_text_version(),
      preferred: preferred?,
      assignment_source: if(preferred?, do: preference.assignment_source, else: "explicit_invocation"),
      route: route
    }
  end

  defp personal_route(config, integration, assignment, consent, decision, task, assignment_source, preference) do
    {:ok, credential_ref} = CredentialRef.new(:personal_byok, Integer.to_string(integration.id))

    %ExecutionRoute{
      lane: :personal_byok,
      provider: config.provider,
      model: config.model,
      credential_ref: credential_ref,
      payer: "personal_provider_account",
      assignment_source: assignment_source,
      consent_basis: "personal_consent:#{consent.id}:#{consent.policy_text_version}",
      policy_version: decision.policy_version,
      price_id: nil,
      price_version: nil,
      price_units: nil,
      provider_configuration:
        maybe_put_preference(
          %{
            "personal_consent_id" => consent.id,
            "personal_consent_version" => consent.policy_text_version,
            "workspace_assignment_id" => assignment.id,
            "integration_id" => integration.id,
            "model_catalog_version" => config.catalog.catalog_version,
            "model_pricing_version" => config.catalog.pricing_version,
            "capability" => Atom.to_string(task.capability),
            "cost_class" => task.personal_cost_class,
            "data_scope" => Atom.to_string(task.data_scope),
            "processing_location" => config.processing_location,
            "response_mode" => config.response_mode
          },
          preference,
          assignment_source
        )
    }
  end

  defp preference_choice?(choice, resolution) do
    not is_nil(resolution.preference_id) and
      choice.provider == resolution.provider and
      choice.model == resolution.model and
      choice.integration_id == resolution.integration_id
  end

  defp preference_match?(preference, config, integration) do
    not is_nil(preference.preference_id) and
      preference.provider == config.provider and
      preference.model == config.model and
      preference.integration_id == integration.id
  end

  defp maybe_put_preference(configuration, preference, assignment_source) when assignment_source == "personal_role" do
    configuration
    |> Map.put("personal_preference_id", preference.preference_id)
    |> Map.put("personal_preference_slot", Atom.to_string(preference.slot))
  end

  defp maybe_put_preference(configuration, _preference, _assignment_source), do: configuration

  defp config do
    Application.get_env(:storyarn, __MODULE__, [])
  end

  defp provider_configuration(config) do
    endpoint = config[:endpoint]
    region = config[:region]
    provider_price = ConfigMap.normalize(config[:provider_price])
    budget = ConfigMap.normalize(config[:budget])

    with true <- valid_https_endpoint?(endpoint),
         true <- is_binary(region) and byte_size(region) > 0,
         true <- valid_provider_price?(provider_price),
         true <- valid_budget?(budget) do
      {:ok,
       %{
         "region" => region,
         "data_retention" => "zero_data_retention",
         "training_usage" => "disabled",
         "provider_price" => provider_price,
         "budget" => budget
       }}
    else
      _invalid -> {:error, :managed_route_invalid}
    end
  end

  defp valid_https_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{
        scheme: "https",
        host: host,
        userinfo: nil,
        query: nil,
        fragment: nil
      }
      when is_binary(host) and host != "" ->
        true

      _invalid ->
        false
    end
  end

  defp valid_https_endpoint?(_endpoint), do: false

  defp valid_provider_price?(%{
         "version" => version,
         "currency" => currency,
         "input_per_million" => input_rate,
         "output_per_million" => output_rate,
         "max_estimated_cost" => estimate
       }) do
    with true <- is_integer(version) and version > 0,
         true <- is_binary(currency) and currency != "",
         {:ok, input_rate} <- decimal(input_rate),
         {:ok, output_rate} <- decimal(output_rate),
         {:ok, estimate} <- decimal(estimate) do
      free? = zero?(input_rate) and zero?(output_rate)
      free? or positive?(estimate)
    else
      _invalid -> false
    end
  end

  defp valid_provider_price?(_price), do: false

  defp valid_budget?(%{"global_daily" => daily, "global_monthly" => monthly, "workspace_daily" => workspace}) do
    Enum.all?([daily, monthly, workspace], fn value ->
      case decimal(value) do
        {:ok, decimal} -> positive?(decimal)
        {:error, :invalid_decimal} -> false
      end
    end)
  end

  defp valid_budget?(_budget), do: false

  defp decimal(%Decimal{} = value), do: nonnegative_decimal(value)
  defp decimal(value) when is_integer(value), do: value |> Decimal.new() |> nonnegative_decimal()

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> nonnegative_decimal(decimal)
      _invalid -> {:error, :invalid_decimal}
    end
  end

  defp decimal(_value), do: {:error, :invalid_decimal}

  defp nonnegative_decimal(decimal) do
    if Decimal.compare(decimal, Decimal.new(0)) in [:eq, :gt],
      do: {:ok, decimal},
      else: {:error, :invalid_decimal}
  end

  defp zero?(decimal), do: Decimal.compare(decimal, Decimal.new(0)) == :eq
  defp positive?(decimal), do: Decimal.compare(decimal, Decimal.new(0)) == :gt
end

defmodule Storyarn.AI.RouteResolver do
  @moduledoc """
  Minimal Slice-2 route resolver.

  It exposes only operator-configured routes. Slice 5 replaces the single
  managed assignment with central routing and personal preferences.
  """

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.IntegrationCrud
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PersonalProviders
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task

  @spec routes(PolicyDecision.t(), Task.t()) :: [ExecutionRoute.t()]
  def routes(%PolicyDecision{} = decision, %Task{} = task) do
    Enum.flat_map(decision.allowed_lanes, &route_for_lane(&1, decision, task))
  end

  @spec personal_choices(PolicyDecision.t(), Task.t()) :: [map()]
  def personal_choices(%PolicyDecision{} = decision, %Task{} = task) do
    if :personal_byok in decision.allowed_lanes and task.personal_byok_allowed? and not decision.scheduled? do
      integrations =
        decision.actor_id
        |> IntegrationCrud.list_active()
        |> Map.new(&{&1.provider, &1})

      task.capability
      |> PersonalProviders.for_capability()
      |> Enum.map(&personal_choice(&1, Map.get(integrations, &1.provider), decision, task))
    else
      []
    end
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

  defp route_for_lane(:personal_byok, decision, task) do
    decision
    |> personal_choices(task)
    |> Enum.flat_map(fn
      %{status: :ready, route: route} -> [route]
      _blocked -> []
    end)
  end

  defp route_for_lane(_lane, _decision, _task), do: []

  defp personal_choice(config, nil, _decision, task) do
    choice(config, task, :connect_required, nil, nil)
  end

  defp personal_choice(config, integration, decision, task) do
    case PersonalConsents.active_for(decision.actor_id, decision.workspace_id, integration.id, task) do
      nil ->
        choice(config, task, :consent_required, integration.id, nil)

      consent ->
        route = personal_route(config, integration, consent, decision, task)
        choice(config, task, :ready, integration.id, route)
    end
  end

  defp choice(config, task, status, integration_id, route) do
    %{
      lane: :personal_byok,
      provider: config.provider,
      provider_name: config.metadata.name,
      model: config.model,
      payer: "personal_provider_account",
      status: status,
      integration_id: integration_id,
      capability: task.capability,
      cost_class: task.personal_cost_class,
      data_scope: task.data_scope,
      processing_location: config.processing_location,
      consent_policy_version: PersonalConsents.policy_text_version(),
      route: route
    }
  end

  defp personal_route(config, integration, consent, decision, task) do
    {:ok, credential_ref} = CredentialRef.new(:personal_byok, Integer.to_string(integration.id))

    %ExecutionRoute{
      lane: :personal_byok,
      provider: config.provider,
      model: config.model,
      credential_ref: credential_ref,
      payer: "personal_provider_account",
      assignment_source: "explicit_invocation",
      consent_basis: "personal_consent:#{consent.id}:#{consent.policy_text_version}",
      policy_version: decision.policy_version,
      price_id: nil,
      price_version: nil,
      price_units: nil,
      provider_configuration: %{
        "personal_consent_id" => consent.id,
        "personal_consent_version" => consent.policy_text_version,
        "integration_id" => integration.id,
        "capability" => Atom.to_string(task.capability),
        "cost_class" => task.personal_cost_class,
        "data_scope" => Atom.to_string(task.data_scope),
        "processing_location" => config.processing_location,
        "response_mode" => config.response_mode
      }
    }
  end

  defp config do
    Application.get_env(:storyarn, __MODULE__, [])
  end

  defp provider_configuration(config) do
    endpoint = config[:endpoint]
    region = config[:region]
    provider_price = normalize_map(config[:provider_price])
    budget = normalize_map(config[:budget])

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

  defp normalize_map(value) when is_list(value), do: value |> Map.new() |> normalize_map()
  defp normalize_map(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), item} end)
  defp normalize_map(_value), do: %{}
end

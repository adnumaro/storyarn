defmodule Storyarn.AI.RouteResolver do
  @moduledoc """
  Minimal Slice-2 route resolver.

  It exposes only operator-configured routes. Slice 5 replaces the single
  managed assignment with central routing and personal preferences.
  """

  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Settlement
  alias Storyarn.AI.Task

  @spec routes(PolicyDecision.t(), Task.t()) :: [ExecutionRoute.t()]
  def routes(%PolicyDecision{} = decision, %Task{} = task) do
    Enum.flat_map(decision.allowed_lanes, &route_for_lane(&1, decision, task))
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
         true <- config[:verified_eu_region] == true,
         true <- config[:verified_zdr] == true,
         provider when is_binary(provider) <- config[:provider],
         model when is_binary(model) <- config[:model],
         {:ok, provider_configuration} <- provider_configuration(config) do
      %{
        provider: provider,
        model: model,
        region: provider_configuration["region"],
        data_retention: provider_configuration["data_retention"]
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
         true <- config[:verified_eu_region] == true,
         true <- config[:verified_zdr] == true,
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

  # Slice 4 adds the personal route through this same resolver contract.
  defp route_for_lane(_lane, _decision, _task), do: []

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
         "endpoint" => endpoint,
         "region" => region,
         "data_retention" => "zero_data_retention",
         "provider_price" => provider_price,
         "budget" => budget
       }}
    else
      _invalid -> {:error, :managed_route_invalid}
    end
  end

  defp valid_https_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _invalid -> false
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
    is_integer(version) and version > 0 and is_binary(currency) and currency != "" and
      Enum.all?([input_rate, output_rate, estimate], &valid_decimal?/1)
  end

  defp valid_provider_price?(_price), do: false

  defp valid_budget?(%{"global_daily" => daily, "global_monthly" => monthly, "workspace_daily" => workspace}) do
    Enum.all?([daily, monthly, workspace], &valid_positive_decimal?/1)
  end

  defp valid_budget?(_budget), do: false

  defp valid_decimal?(value) do
    case Decimal.parse(to_string(value)) do
      {decimal, ""} -> Decimal.compare(decimal, Decimal.new(0)) in [:eq, :gt]
      _invalid -> false
    end
  end

  defp valid_positive_decimal?(value) do
    case Decimal.parse(to_string(value)) do
      {decimal, ""} -> Decimal.compare(decimal, Decimal.new(0)) == :gt
      _invalid -> false
    end
  end

  defp normalize_map(value) when is_list(value), do: value |> Map.new() |> normalize_map()
  defp normalize_map(value) when is_map(value), do: Map.new(value, fn {key, item} -> {to_string(key), item} end)
  defp normalize_map(_value), do: %{}
end

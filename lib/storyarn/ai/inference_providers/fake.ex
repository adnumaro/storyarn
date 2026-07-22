defmodule Storyarn.AI.InferenceProviders.Fake do
  @moduledoc """
  Deterministic contract adapter. It is never operator-routed in production.

  Scenarios are fixed by registered task configuration, not by caller routing
  fields. This makes success, classified failure and unknown outcome testable
  without a real provider or secret.
  """

  @behaviour Storyarn.AI.InferenceProvider

  @impl true
  def generate(_credential, %{input: input, provider_options: options}) do
    case Map.get(options, :scenario, Map.get(options, "scenario", :success)) do
      scenario when scenario in [:success, "success"] ->
        {:ok,
         %{
           output: %{"echo" => input},
           provider_request_id: "fake-deterministic-request",
           input_units: 1,
           output_units: 1,
           provider_cost: Decimal.new("0"),
           provider_cost_currency: "USD"
         }}

      scenario when scenario in [:failure, "failure"] ->
        {:error, :provider_error}

      scenario when scenario in [:unknown, "unknown"] ->
        {:error, {:unknown, :transport_outcome_unproven}}

      scenario when scenario in [:invalid_metrics, "invalid_metrics"] ->
        {:ok, %{output: %{"echo" => input}, input_units: -1}}

      scenario when scenario in [:crash, "crash"] ->
        exit(:simulated_provider_crash)

      _scenario ->
        {:error, :provider_error}
    end
  end
end

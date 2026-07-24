defmodule Storyarn.AI.InferenceProviders.Fake do
  @moduledoc """
  Deterministic contract adapter. It is never operator-routed in production.

  Scenarios are fixed by registered task configuration, not by caller routing
  fields. This makes success, classified failure and unknown outcome testable
  without a real provider or secret.
  """

  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.Context.ModelLimits

  @impl true
  def generate(_credential, %{input: input, contextual?: contextual?, provider_options: options})
      when is_boolean(contextual?) do
    with {:ok, echo_input} <- unwrap_context_input(input, contextual?) do
      case Map.get(options, :scenario, Map.get(options, "scenario", :success)) do
        scenario when scenario in [:success, "success"] ->
          {:ok,
           %{
             output: %{"echo" => echo_input},
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
          {:ok, %{output: %{"echo" => echo_input}, input_units: -1}}

        scenario when scenario in [:crash, "crash"] ->
          exit(:simulated_provider_crash)

        _scenario ->
          {:error, :provider_error}
      end
    end
  end

  def generate(_credential, _request), do: {:error, :provider_error}

  defp unwrap_context_input(input, false), do: {:ok, input}

  defp unwrap_context_input(%{"request" => request} = input, true) do
    if ModelLimits.contextual_input?(input),
      do: {:ok, request},
      else: {:error, :provider_error}
  end

  defp unwrap_context_input(_input, true), do: {:error, :provider_error}
end

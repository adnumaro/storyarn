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
  def generate(_credential, %{
        input: input,
        contextual?: contextual?,
        context_policy: context_policy,
        provider_options: options
      })
      when is_boolean(contextual?) do
    with {:ok, echo_input} <- unwrap_context_input(input, contextual?, context_policy) do
      case Map.get(options, :scenario, Map.get(options, "scenario", default_scenario(options))) do
        # A task that declares a response schema and no test scenario gets a
        # minimal instance OF ITS OWN CONTRACT back, so a deterministic run
        # exercises the real validate_output/1 instead of an echo shape no
        # production task would accept.
        scenario when scenario in [:schema, "schema"] ->
          schema_success(options)

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

  defp schema_success(options) do
    case schema_instance(Map.get(options, :response_schema, Map.get(options, "response_schema"))) do
      {:ok, output} ->
        {:ok,
         %{
           output: output,
           provider_request_id: "fake-deterministic-request",
           input_units: 1,
           output_units: 1,
           provider_cost: Decimal.new("0"),
           provider_cost_currency: "USD"
         }}

      :error ->
        {:error, :provider_error}
    end
  end

  # Deliberately narrow: only the JSON-schema subset registered tasks are
  # allowed to declare. An unsupported shape fails closed rather than inventing
  # a value the task's own validator would then have to reject.
  defp schema_instance(%{"type" => "object", "properties" => properties, "required" => required})
       when is_map(properties) and is_list(required) do
    Enum.reduce_while(required, {:ok, %{}}, fn key, {:ok, acc} ->
      case properties |> Map.get(key) |> property_instance(key) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp schema_instance(_schema), do: :error

  # Answering a task's own contract is only possible when it declares one. A task
  # that declares NO schema keeps the echo success it always had; defaulting to
  # :schema there would fail closed for no reason.
  #
  # Presence, not truthiness: `response_schema: nil` is a malformed declaration,
  # not an absent one, and must still fail closed.
  defp default_scenario(options) do
    if Map.has_key?(options, :response_schema) or Map.has_key?(options, "response_schema"),
      do: :schema,
      else: :success
  end

  # An enum names the only accepted values, so generic text would fail the task's
  # own validator. Enum specs also declare a type, hence the clause order.
  defp property_instance(%{"enum" => [value | _rest]}, _key), do: {:ok, value}

  defp property_instance(%{"type" => "string"} = spec, key), do: {:ok, bounded_text(key, spec["maxLength"])}

  defp property_instance(%{"type" => "array", "items" => %{"type" => "string"} = items}, key),
    do: {:ok, [bounded_text(key, items["maxLength"])]}

  defp property_instance(_spec, _key), do: :error

  defp bounded_text(key, nil), do: "deterministic #{key}"

  defp bounded_text(key, max_length) when is_integer(max_length) and max_length > 0,
    do: key |> bounded_text(nil) |> String.slice(0, max_length)

  defp bounded_text(key, _max_length), do: bounded_text(key, nil)

  defp unwrap_context_input(input, false, _context_policy), do: {:ok, input}

  defp unwrap_context_input(%{"request" => request} = input, true, context_policy) do
    if ModelLimits.contextual_input?(input, context_policy),
      do: {:ok, request},
      else: {:error, :provider_error}
  end

  defp unwrap_context_input(_input, true, _context_policy), do: {:error, :provider_error}
end

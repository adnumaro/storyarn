defmodule Storyarn.AI.Executor do
  @moduledoc "Runs one operation with zero automatic provider retries."

  alias Storyarn.Shared.CanonicalJSON
  alias Storyarn.AI.CredentialResolver
  alias Storyarn.AI.InferenceProviders
  alias Storyarn.AI.Operations
  alias Storyarn.AI.Result
  alias Storyarn.AI.Task
  alias Storyarn.Repo

  @spec run(pos_integer()) :: :ok | {:error, term()}
  def run(operation_id) do
    case Operations.claim(operation_id) do
      {:ok, operation, task, route} -> run_claimed(operation, task, route)
      {:cancelled, _operation} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_claimed(operation, task, route) do
    with {:ok, provider} <- InferenceProviders.fetch(route.provider),
         {:ok, input} <- load_input(operation.id),
         {:ok, usage, credential} <- normalize_attempt(Operations.start_attempt(operation, task, route)) do
      started = System.monotonic_time(:millisecond)
      result = call_provider(provider, credential, task, route, input, operation)
      latency = max(System.monotonic_time(:millisecond) - started, 0)
      :ok = CredentialResolver.record_outcome(credential, result)
      finalize(result, operation, task, usage, latency)
    else
      {:cancelled, _operation} -> :ok
      {:error, reason} -> Operations.fail_before_attempt(operation, reason)
    end
  end

  defp load_input(operation_id) do
    case Repo.get_by(Result, operation_id: operation_id) do
      %Result{input_encrypted: encrypted} -> Jason.decode(encrypted)
      nil -> {:error, :temporary_input_missing}
    end
  end

  defp normalize_attempt({:ok, usage, credential}), do: {:ok, usage, credential}
  defp normalize_attempt({:cancelled, operation}), do: {:cancelled, operation}
  defp normalize_attempt({:error, reason}), do: {:error, reason}

  defp call_provider(provider, credential, task, route, input, operation) do
    request = %{
      task_id: task.id,
      model: route.model,
      input: input,
      contextual?: is_binary(operation.context_hash),
      max_output_bytes: task.max_output_bytes,
      provider_options: task.provider_options,
      provider_configuration: route.provider_configuration
    }

    async =
      Elixir.Task.Supervisor.async_nolink(Storyarn.TaskSupervisor, fn ->
        provider.generate(credential, request)
      end)

    case Elixir.Task.yield(async, task.timeout_ms) || Elixir.Task.shutdown(async, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, {:unknown, :timeout}}
      {:exit, _reason} -> {:error, {:unknown, :provider_process_exit}}
    end
  end

  defp finalize({:ok, response}, operation, task, usage, latency) when is_map(response) do
    output = response[:output]

    with :ok <- Task.validate_output(task, output),
         {:ok, encoded} <- CanonicalJSON.encode(output),
         true <- byte_size(encoded) <= task.max_output_bytes,
         {:ok, metrics} <- usage_metrics(response, latency) do
      Operations.finish_success(operation, usage, output, metrics)
    else
      false -> Operations.finish_failure(operation, usage, :output_too_large, %{latency_ms: latency})
      {:error, reason} -> Operations.finish_failure(operation, usage, reason, %{latency_ms: latency})
    end
  end

  defp finalize({:error, {:unknown, reason}}, operation, _task, usage, latency) do
    Operations.finish_unknown(operation, usage, reason, %{latency_ms: latency})
  end

  defp finalize({:error, reason}, operation, _task, usage, latency) do
    Operations.finish_failure(operation, usage, reason, %{latency_ms: latency})
  end

  defp finalize(_invalid, operation, _task, usage, latency) do
    Operations.finish_failure(operation, usage, :invalid_provider_response, %{latency_ms: latency})
  end

  defp usage_metrics(response, latency) do
    metrics = %{
      provider_request_id: response[:provider_request_id],
      input_units: response[:input_units],
      output_units: response[:output_units],
      provider_cost: response[:provider_cost],
      provider_cost_currency: response[:provider_cost_currency],
      latency_ms: latency
    }

    if valid_metrics?(metrics) do
      {:ok, Map.reject(metrics, fn {_key, value} -> is_nil(value) end)}
    else
      {:error, :invalid_provider_response}
    end
  end

  defp valid_metrics?(metrics) do
    optional_bounded_string?(metrics.provider_request_id, 255) and
      optional_nonnegative_integer?(metrics.input_units) and
      optional_nonnegative_integer?(metrics.output_units) and
      optional_nonnegative_decimal?(metrics.provider_cost) and
      optional_bounded_string?(metrics.provider_cost_currency, 12)
  end

  defp optional_bounded_string?(nil, _max), do: true
  defp optional_bounded_string?(value, max), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max

  defp optional_nonnegative_integer?(nil), do: true
  defp optional_nonnegative_integer?(value), do: is_integer(value) and value >= 0

  defp optional_nonnegative_decimal?(nil), do: true

  defp optional_nonnegative_decimal?(%Decimal{} = value) do
    Decimal.compare(value, Decimal.new(0)) in [:eq, :gt]
  end

  defp optional_nonnegative_decimal?(_value), do: false
end

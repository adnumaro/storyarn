defmodule Storyarn.AI.Context.ModelLimits do
  @moduledoc """
  Fails closed before contextual input can exceed a curated model contract.

  The catalog is the authority for limits. Storyarn uses the encoded request
  byte size as a conservative upper bound for input tokens and still leaves a
  small safety margin for provider-side framing and tokenizer differences.
  """

  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.ModelCatalog
  alias Storyarn.AI.ModelCatalog.Entry
  alias Storyarn.AI.Task

  @safety_margin_tokens 1_024
  @context_limit_errors [
    :model_context_limits_unavailable,
    :model_context_window_exceeded,
    :model_output_limit_exceeded
  ]

  @spec validate_context(Task.t(), ExecutionRoute.t(), map() | list(), nil | map()) ::
          :ok
          | {:error,
             :model_context_limits_unavailable
             | :model_context_window_exceeded
             | :model_output_limit_exceeded}
  def validate_context(%Task{}, %ExecutionRoute{}, _input, nil), do: :ok

  def validate_context(%Task{}, %ExecutionRoute{provider: "fake"}, _input, %{package: %Package{}}), do: :ok

  def validate_context(%Task{} = task, %ExecutionRoute{} = route, input, %{package: %Package{} = package}) do
    contextual_input = %{"request" => input, "context" => package.payload}

    with {:ok, entry} <- executable_entry(route.provider, route.model),
         true <- task.capability in entry.capabilities || {:error, :model_context_limits_unavailable} do
      validate_material(entry, task.provider_options, %{
        input: contextual_input,
        provider_options: task.provider_options
      })
    end
  end

  @spec validate_provider_request(String.t(), map(), map()) ::
          :ok
          | {:error,
             :model_context_limits_unavailable
             | :model_context_window_exceeded
             | :model_output_limit_exceeded}
  def validate_provider_request(provider, %{contextual?: true, input: input} = request, body)
      when is_binary(provider) and is_map(body) do
    with true <- contextual_input?(input) || {:error, :model_context_limits_unavailable},
         {:ok, entry} <- executable_entry(provider, request.model) do
      validate_material(entry, request.provider_options, body)
    end
  end

  def validate_provider_request(provider, %{contextual?: false}, body) when is_binary(provider) and is_map(body), do: :ok

  def validate_provider_request(_provider, _request, _body), do: {:error, :model_context_limits_unavailable}

  @doc """
  Identifies the bounded, content-free errors that can safely block one route
  without invalidating unrelated preflight choices.
  """
  @spec context_limit_error?(term()) :: boolean()
  def context_limit_error?(reason), do: reason in @context_limit_errors

  @doc """
  Converts an internal model-limit failure into its content-free public choice
  status. No sizes, limits or request material cross the preflight boundary.
  """
  @spec public_status(atom()) :: atom()
  def public_status(reason) when reason in @context_limit_errors, do: reason

  @spec contextual_input?(term()) :: boolean()
  def contextual_input?(
        %{
          "request" => request,
          "context" => %{"version" => "storyarn-context-v1", "scope" => scope, "entities" => entities} = context
        } = input
      )
      when map_size(input) == 2 and map_size(context) == 3 and (is_map(request) or is_list(request)) and
             scope in ["dialogue", "flow_neighborhood", "sheet", "structural_finding"] and is_list(entities), do: true

  def contextual_input?(_input), do: false

  defp executable_entry(provider, model) do
    case ModelCatalog.fetch(provider, model) do
      {:ok,
       %Entry{
         implementation_status: :executable,
         context_window: context_window,
         max_output_tokens: max_output_tokens
       } = entry}
      when is_integer(context_window) and context_window > 0 and is_integer(max_output_tokens) and
             max_output_tokens > 0 ->
        {:ok, entry}

      _unavailable ->
        {:error, :model_context_limits_unavailable}
    end
  end

  defp validate_material(entry, provider_options, material) do
    with {:ok, requested_output_tokens} <- requested_output_tokens(provider_options),
         :ok <- output_limit(entry, requested_output_tokens),
         {:ok, encoded} <- Jason.encode(material),
         :ok <- context_limit(entry, byte_size(encoded), requested_output_tokens) do
      :ok
    else
      {:error, reason}
      when reason in @context_limit_errors ->
        {:error, reason}

      _invalid ->
        {:error, :model_context_limits_unavailable}
    end
  end

  defp requested_output_tokens(options) when is_map(options) do
    value = Map.get(options, :max_output_tokens, Map.get(options, "max_output_tokens"))

    if is_integer(value) and value > 0,
      do: {:ok, value},
      else: {:error, :model_context_limits_unavailable}
  end

  defp requested_output_tokens(_options), do: {:error, :model_context_limits_unavailable}

  defp output_limit(%Entry{max_output_tokens: limit}, requested) do
    if requested <= limit, do: :ok, else: {:error, :model_output_limit_exceeded}
  end

  defp context_limit(%Entry{context_window: window}, encoded_bytes, requested_output_tokens) do
    upper_bound = encoded_bytes + requested_output_tokens + @safety_margin_tokens

    if upper_bound <= window,
      do: :ok,
      else: {:error, :model_context_window_exceeded}
  end
end

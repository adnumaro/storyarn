defmodule Storyarn.AI.InferenceProviders.Together do
  @moduledoc "Together structured-output adapter for the verified managed route."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.ResolvedCredential

  @impl true
  def generate(%ResolvedCredential{kind: :managed, value: api_key}, request) when is_binary(api_key) do
    with {:ok, endpoint, price_snapshot} <- route_configuration(request.provider_configuration),
         {:ok, body} <- request_body(request),
         {:ok, response} <- post(endpoint, api_key, body),
         {:ok, output} <- extract_output(response.body),
         {:ok, metrics} <- metrics(response.body, price_snapshot) do
      {:ok, Map.merge(%{output: output}, metrics)}
    end
  end

  def generate(_credential, _request), do: {:error, :unauthorized}

  defp route_configuration(%{
         "endpoint" => endpoint,
         "data_retention" => "zero_data_retention",
         "provider_price" => price_snapshot
       })
       when is_binary(endpoint) and is_map(price_snapshot) do
    {:ok, endpoint, price_snapshot}
  end

  defp route_configuration(_configuration), do: {:error, :provider_error}

  defp request_body(request) do
    options = request.provider_options
    system_prompt = option(options, :system_prompt)
    response_schema = option(options, :response_schema)
    schema_name = option(options, :schema_name)
    max_tokens = option(options, :max_output_tokens)

    with true <- is_binary(system_prompt) and system_prompt != "",
         true <- is_map(response_schema),
         true <- is_binary(schema_name) and schema_name != "",
         true <- is_integer(max_tokens) and max_tokens > 0,
         {:ok, input_json} <- Jason.encode(request.input) do
      {:ok,
       %{
         model: request.model,
         messages: [
           %{role: "system", content: system_prompt},
           %{role: "user", content: input_json}
         ],
         max_tokens: max_tokens,
         temperature: option(options, :temperature) || 0,
         response_format: %{
           type: "json_schema",
           json_schema: %{name: schema_name, schema: response_schema}
         }
       }}
    else
      _invalid -> {:error, :provider_error}
    end
  end

  defp post(endpoint, api_key, body) do
    options =
      [
        url: endpoint,
        json: body,
        headers: [{"authorization", "Bearer #{api_key}"}],
        retry: false
      ] ++ req_options()

    case Req.post(options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, %Req.Response{status: 401}} -> {:error, :unauthorized}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{}} -> {:error, :provider_error}
      {:error, _transport_error} -> {:error, {:unknown, :transport_outcome_unproven}}
    end
  end

  defp extract_output(%{"choices" => [%{"message" => %{"content" => content}} | _]}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, output} when is_map(output) or is_list(output) -> {:ok, output}
      _invalid -> {:error, :invalid_output}
    end
  end

  defp extract_output(_body), do: {:error, :invalid_output}

  defp metrics(body, price_snapshot) do
    with %{"prompt_tokens" => input, "completion_tokens" => output} <- body["usage"],
         true <- is_integer(input) and input >= 0 and is_integer(output) and output >= 0,
         {:ok, input_rate} <- decimal(price_snapshot["input_per_million"]),
         {:ok, output_rate} <- decimal(price_snapshot["output_per_million"]),
         currency when is_binary(currency) <- price_snapshot["currency"] do
      cost =
        input_rate
        |> Decimal.mult(input)
        |> Decimal.add(Decimal.mult(output_rate, output))
        |> Decimal.div(1_000_000)

      {:ok,
       %{
         provider_request_id: body["id"],
         input_units: input,
         output_units: output,
         provider_cost: cost,
         provider_cost_currency: currency
       }}
    else
      _invalid -> {:error, :invalid_output}
    end
  end

  defp option(options, key), do: Map.get(options, key, Map.get(options, Atom.to_string(key)))

  defp decimal(%Decimal{} = value), do: {:ok, value}

  defp decimal(value) do
    case Decimal.parse(to_string(value)) do
      {decimal, ""} -> {:ok, decimal}
      _invalid -> {:error, :invalid_decimal}
    end
  end

  defp req_options do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end

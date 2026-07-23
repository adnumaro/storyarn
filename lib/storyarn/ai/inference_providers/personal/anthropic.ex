defmodule Storyarn.AI.InferenceProviders.Personal.Anthropic do
  @moduledoc "Anthropic Messages structured-output adapter for actor-owned API keys."
  @behaviour Storyarn.AI.InferenceProvider

  alias Storyarn.AI.ResolvedCredential

  @anthropic_version "2023-06-01"

  @impl true
  def generate(%ResolvedCredential{kind: :personal_byok, value: api_key}, request) when is_binary(api_key) do
    with :ok <- valid_route?(request.provider_configuration),
         {:ok, endpoint} <- endpoint(),
         {:ok, body} <- request_body(request),
         {:ok, response} <- post(endpoint, api_key, body),
         {:ok, output} <- extract_output(response.body),
         {:ok, metrics} <- metrics(response.body) do
      {:ok, Map.merge(%{output: output}, metrics)}
    end
  end

  def generate(_credential, _request), do: {:error, :unauthorized}

  defp valid_route?(%{
         "personal_consent_id" => consent_id,
         "personal_consent_version" => consent_version,
         "response_mode" => "json_schema"
       })
       when is_integer(consent_id) and consent_id > 0 and is_binary(consent_version), do: :ok

  defp valid_route?(_configuration), do: {:error, :provider_error}

  defp request_body(request) do
    options = request.provider_options
    system_prompt = option(options, :system_prompt)
    response_schema = option(options, :response_schema)
    max_tokens = option(options, :max_output_tokens)

    with true <- is_binary(system_prompt) and system_prompt != "",
         true <- is_map(response_schema),
         true <- is_integer(max_tokens) and max_tokens > 0,
         {:ok, input_json} <- Jason.encode(request.input) do
      {:ok,
       %{
         model: request.model,
         system: system_prompt,
         messages: [%{role: "user", content: input_json}],
         max_tokens: max_tokens,
         temperature: option(options, :temperature) || 0,
         output_config: %{format: %{type: "json_schema", schema: response_schema}}
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
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", @anthropic_version}
        ],
        retry: false,
        redirect: false
      ] ++ req_options()

    case Req.post(options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 -> {:ok, response}
      {:ok, %Req.Response{status: 401}} -> {:error, :unauthorized}
      {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
      {:ok, %Req.Response{}} -> {:error, :provider_error}
      {:error, _transport_error} -> {:error, {:unknown, :transport_outcome_unproven}}
    end
  end

  defp extract_output(%{"content" => content}) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "text" and is_binary(&1["text"]))) do
      %{"text" => text} ->
        case Jason.decode(text) do
          {:ok, output} when is_map(output) or is_list(output) -> {:ok, output}
          _invalid -> {:error, :invalid_output}
        end

      nil ->
        {:error, :invalid_output}
    end
  end

  defp extract_output(_body), do: {:error, :invalid_output}

  defp metrics(%{"id" => request_id, "usage" => %{"input_tokens" => input, "output_tokens" => output}})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0 do
    {:ok, %{provider_request_id: request_id, input_units: input, output_units: output}}
  end

  defp metrics(_body), do: {:error, :invalid_output}

  defp option(options, key), do: Map.get(options, key, Map.get(options, Atom.to_string(key)))

  defp endpoint do
    endpoint =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:endpoint)

    if is_binary(endpoint) and endpoint != "", do: {:ok, endpoint}, else: {:error, :provider_error}
  end

  defp req_options do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end

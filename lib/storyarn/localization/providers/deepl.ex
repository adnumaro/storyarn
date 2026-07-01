defmodule Storyarn.Localization.Providers.DeepL do
  @moduledoc false

  @behaviour Storyarn.Localization.TranslationProvider

  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.ProviderConfig

  require Logger

  @max_texts_per_request 50

  # =============================================================================
  # TranslationProvider callbacks
  # =============================================================================

  @impl true
  def translate(texts, source_lang, target_lang, config, opts \\ []) do
    api_key = config.api_key_encrypted

    with {:ok, base_url} <- ProviderConfig.api_endpoint_or_default(config) do
      translate_with_endpoint(texts, source_lang, target_lang, config, api_key, base_url, opts)
    end
  end

  @impl true
  def get_usage(config) do
    api_key = config.api_key_encrypted

    with {:ok, base_url} <- ProviderConfig.api_endpoint_or_default(config) do
      case Req.get("#{base_url}/v2/usage",
             headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok,
           %{
             character_count: body["character_count"],
             character_limit: body["character_limit"]
           }}

        {:ok, %{status: 403}} ->
          {:error, :invalid_api_key}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @impl true
  def supported_languages(config) do
    api_key = config.api_key_encrypted

    with {:ok, base_url} <- ProviderConfig.api_endpoint_or_default(config) do
      case Req.get("#{base_url}/v2/languages",
             headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
             params: [type: "target"],
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, Enum.map(body, &language_from_response/1)}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @impl true
  def create_glossary(name, source_lang, target_lang, entries, config) do
    api_key = config.api_key_encrypted

    with {:ok, base_url} <- ProviderConfig.api_endpoint_or_default(config) do
      # DeepL expects TSV format for entries
      entries_tsv =
        Enum.map_join(entries, "\n", fn {source, target} -> "#{source}\t#{target}" end)

      case Req.post("#{base_url}/v2/glossaries",
             headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
             json: %{
               name: name,
               source_lang: normalize_lang(source_lang),
               target_lang: normalize_lang(target_lang),
               entries: entries_tsv,
               entries_format: "tsv"
             },
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: 201, body: body}} ->
          {:ok, body["glossary_id"]}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @impl true
  def delete_glossary(glossary_id, config) do
    api_key = config.api_key_encrypted

    with {:ok, base_url} <- ProviderConfig.api_endpoint_or_default(config) do
      case Req.delete("#{base_url}/v2/glossaries/#{glossary_id}",
             headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: 204}} -> :ok
        {:ok, %{status: 404}} -> :ok
        {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
        {:error, reason} -> {:error, {:request_failed, reason}}
      end
    end
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp translate_with_endpoint(texts, source_lang, target_lang, config, api_key, base_url, opts) do
    has_html = Enum.any?(texts, &HtmlHandler.html?/1)

    texts
    |> preprocess_texts(has_html)
    |> Enum.chunk_every(@max_texts_per_request)
    |> translate_chunks([], source_lang, target_lang, api_key, base_url,
      glossary_id: get_glossary_id(config, source_lang, target_lang),
      tag_handling: if(has_html, do: "html"),
      formality: opts[:formality]
    )
    |> postprocess_translations(has_html)
  end

  defp preprocess_texts(texts, true), do: Enum.map(texts, &HtmlHandler.pre_translate/1)
  defp preprocess_texts(texts, false), do: texts

  defp translate_chunks([], acc, _source_lang, _target_lang, _api_key, _base_url, _opts) do
    {:ok, acc}
  end

  defp translate_chunks([chunk | chunks], acc, source_lang, target_lang, api_key, base_url, opts) do
    case do_translate(chunk, source_lang, target_lang, api_key, base_url, opts) do
      {:ok, translations} ->
        translate_chunks(chunks, acc ++ translations, source_lang, target_lang, api_key, base_url, opts)

      {:error, _} = error ->
        error
    end
  end

  defp postprocess_translations({:ok, translations}, true) do
    {:ok,
     Enum.map(translations, fn translation ->
       %{translation | text: HtmlHandler.post_translate(translation.text)}
     end)}
  end

  defp postprocess_translations(result, _has_html), do: result

  defp do_translate(texts, source_lang, target_lang, api_key, base_url, opts) do
    body =
      %{
        text: texts,
        target_lang: normalize_lang(target_lang)
      }
      |> maybe_put(:source_lang, if(source_lang, do: normalize_lang(source_lang)))
      |> maybe_put(:tag_handling, opts[:tag_handling])
      |> maybe_put(:glossary_id, opts[:glossary_id])
      |> maybe_put(:formality, opts[:formality])

    case Req.post("#{base_url}/v2/translate",
           headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
           json: body,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: 200, body: %{"translations" => translations}}} ->
        results =
          Enum.map(translations, fn t ->
            %{
              text: t["text"],
              detected_source_lang: t["detected_source_language"]
            }
          end)

        {:ok, results}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: 456}} ->
        {:error, :quota_exceeded}

      {:ok, %{status: 403}} ->
        {:error, :invalid_api_key}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("DeepL API error: status=#{status} body=#{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.warning("DeepL request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_glossary_id(config, source_lang, target_lang) when is_binary(source_lang) and is_binary(target_lang) do
    pair = "#{normalize_lang(source_lang)}-#{normalize_lang(target_lang)}"
    Map.get(config.deepl_glossary_ids || %{}, pair)
  end

  defp get_glossary_id(_config, _source_lang, _target_lang), do: nil

  defp language_from_response(lang) do
    %{code: lang["language"], name: lang["name"]}
  end

  # DeepL uses uppercase language codes (EN, ES, JA) or with region (EN-US, PT-BR)
  defp normalize_lang(code) when is_binary(code) do
    String.upcase(code)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

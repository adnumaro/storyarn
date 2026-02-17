defmodule Storyarn.Localization.Providers.DeepL do
  @moduledoc false

  @behaviour Storyarn.Localization.TranslationProvider

  alias Storyarn.Localization.HtmlHandler

  require Logger

  @max_texts_per_request 50

  # =============================================================================
  # TranslationProvider callbacks
  # =============================================================================

  @impl true
  def translate(texts, source_lang, target_lang, config, opts \\ []) do
    api_key = config.api_key_encrypted
    base_url = config.api_endpoint || "https://api-free.deepl.com"

    glossary_id = get_glossary_id(config, source_lang, target_lang)
    has_html = Enum.any?(texts, &HtmlHandler.html?/1)

    # Pre-process HTML texts
    processed_texts =
      if has_html do
        Enum.map(texts, &HtmlHandler.pre_translate/1)
      else
        texts
      end

    # Chunk into groups of 50 (DeepL limit)
    chunks = Enum.chunk_every(processed_texts, @max_texts_per_request)

    results =
      Enum.reduce_while(chunks, {:ok, []}, fn chunk, {:ok, acc} ->
        case do_translate(chunk, source_lang, target_lang, api_key, base_url,
               glossary_id: glossary_id,
               tag_handling: if(has_html, do: "html"),
               formality: opts[:formality]
             ) do
          {:ok, translations} -> {:cont, {:ok, acc ++ translations}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    # Post-process HTML in results
    case results do
      {:ok, translations} when has_html ->
        {:ok, Enum.map(translations, fn t -> %{t | text: HtmlHandler.post_translate(t.text)} end)}

      other ->
        other
    end
  end

  @impl true
  def get_usage(config) do
    api_key = config.api_key_encrypted
    base_url = config.api_endpoint || "https://api-free.deepl.com"

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

  @impl true
  def supported_languages(config) do
    api_key = config.api_key_encrypted
    base_url = config.api_endpoint || "https://api-free.deepl.com"

    case Req.get("#{base_url}/v2/languages",
           headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}],
           params: [type: "target"],
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: 200, body: body}} ->
        languages =
          Enum.map(body, fn lang ->
            %{code: lang["language"], name: lang["name"]}
          end)

        {:ok, languages}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def create_glossary(name, source_lang, target_lang, entries, config) do
    api_key = config.api_key_encrypted
    base_url = config.api_endpoint || "https://api-free.deepl.com"

    # DeepL expects TSV format for entries
    entries_tsv =
      entries
      |> Enum.map(fn {source, target} -> "#{source}\t#{target}" end)
      |> Enum.join("\n")

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

  @impl true
  def delete_glossary(glossary_id, config) do
    api_key = config.api_key_encrypted
    base_url = config.api_endpoint || "https://api-free.deepl.com"

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

  # =============================================================================
  # Private
  # =============================================================================

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

  defp get_glossary_id(config, source_lang, target_lang)
       when is_binary(source_lang) and is_binary(target_lang) do
    pair = "#{normalize_lang(source_lang)}-#{normalize_lang(target_lang)}"
    Map.get(config.deepl_glossary_ids || %{}, pair)
  end

  defp get_glossary_id(_config, _source_lang, _target_lang), do: nil

  # DeepL uses uppercase language codes (EN, ES, JA) or with region (EN-US, PT-BR)
  defp normalize_lang(code) when is_binary(code) do
    String.upcase(code)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

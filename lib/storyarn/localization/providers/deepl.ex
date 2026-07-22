defmodule Storyarn.Localization.Providers.DeepL do
  @moduledoc false

  @behaviour Storyarn.Localization.TranslationProvider

  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.ProviderConfig

  require Logger

  @max_texts_per_request 50
  @max_request_body_bytes 120 * 1024

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
      case Req.get(
             "#{base_url}/v2/usage",
             request_options(api_key)
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
      case Req.get(
             "#{base_url}/v2/languages",
             request_options(api_key, params: [type: "target"])
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
      entries_tsv =
        Enum.map_join(entries, "\n", fn {source, target} -> "#{source}\t#{target}" end)

      body = %{
        name: name,
        dictionaries: [
          %{
            source_lang: normalize_glossary_lang(source_lang),
            target_lang: normalize_glossary_lang(target_lang),
            entries: entries_tsv,
            entries_format: "tsv"
          }
        ]
      }

      case Req.post(
             "#{base_url}/v3/glossaries",
             request_options(api_key, json: body)
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
      case Req.delete(
             "#{base_url}/v3/glossaries/#{glossary_id}",
             request_options(api_key)
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

  defp translate_with_endpoint([], _source_lang, _target_lang, _config, _api_key, _base_url, _opts), do: {:ok, []}

  defp translate_with_endpoint(texts, source_lang, target_lang, config, api_key, base_url, opts) do
    request = {source_lang, target_lang, config, api_key, base_url, opts}

    texts
    |> Enum.with_index()
    |> Enum.group_by(fn {text, _index} -> handling_mode(text) end)
    |> Enum.reduce_while({:ok, []}, &translate_group(&1, &2, request))
    |> case do
      {:ok, grouped_translations} ->
        translations =
          grouped_translations
          |> List.flatten()
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(&elem(&1, 1))

        {:ok, translations}

      {:error, _reason} = error ->
        error
    end
  end

  defp translate_group({_mode, segment}, {:ok, acc}, {source_lang, target_lang, config, api_key, base_url, opts}) do
    case translate_segment(segment, source_lang, target_lang, config, api_key, base_url, opts) do
      {:ok, translations} ->
        indexed_translations =
          Enum.zip_with(segment, translations, fn {_text, index}, translation ->
            {index, translation}
          end)

        {:cont, {:ok, [indexed_translations | acc]}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp translate_segment(segment, source_lang, target_lang, config, api_key, base_url, opts) do
    mode = segment |> hd() |> elem(0) |> handling_mode()

    entries =
      Enum.map(segment, fn {text, index} ->
        %{original: text, prepared: preprocess_text(text, mode), index: index}
      end)

    base_body =
      %{
        target_lang: normalize_lang(target_lang)
      }
      |> maybe_put(:source_lang, if(source_lang, do: normalize_lang(source_lang)))
      |> maybe_put(:tag_handling, if(mode == :html, do: "html"))
      |> maybe_put(:glossary_id, get_glossary_id(config, source_lang, target_lang))
      |> maybe_put(:formality, opts[:formality] || config_setting(config, "formality"))
      |> maybe_put(:model_type, opts[:model_type] || config_setting(config, "model_type"))

    with {:ok, chunks} <- chunk_entries(entries, base_body),
         {:ok, translations} <- translate_chunks(chunks, [], base_body, api_key, base_url) do
      validate_translations(entries, translations, mode)
    end
  end

  defp handling_mode(text) do
    if HtmlHandler.html?(text) or HtmlHandler.placeholders(text) != [], do: :html, else: :plain
  end

  defp preprocess_text(text, :html), do: HtmlHandler.pre_translate(text)
  defp preprocess_text(text, :plain), do: text

  defp chunk_entries(entries, base_body) do
    entries
    |> Enum.reduce_while({:ok, [], []}, fn entry, {:ok, chunks, current} ->
      candidate = current ++ [entry]

      cond do
        chunk_fits?(candidate, base_body) ->
          {:cont, {:ok, chunks, candidate}}

        current == [] ->
          {:halt, {:error, {:text_too_large, entry.index}}}

        chunk_fits?([entry], base_body) ->
          {:cont, {:ok, [current | chunks], [entry]}}

        true ->
          {:halt, {:error, {:text_too_large, entry.index}}}
      end
    end)
    |> case do
      {:ok, chunks, []} -> {:ok, Enum.reverse(chunks)}
      {:ok, chunks, current} -> {:ok, Enum.reverse([current | chunks])}
      {:error, _reason} = error -> error
    end
  end

  defp chunk_fits?(entries, base_body) do
    length(entries) <= @max_texts_per_request and
      request_body_size(entries, base_body) <= @max_request_body_bytes
  end

  defp request_body_size(entries, base_body) do
    base_body
    |> Map.put(:text, Enum.map(entries, & &1.prepared))
    |> Jason.encode_to_iodata!()
    |> IO.iodata_length()
  end

  defp translate_chunks([], acc, _base_body, _api_key, _base_url) do
    {:ok, acc |> Enum.reverse() |> List.flatten()}
  end

  defp translate_chunks([chunk | chunks], acc, base_body, api_key, base_url) do
    body = Map.put(base_body, :text, Enum.map(chunk, & &1.prepared))

    case do_translate(body, api_key, base_url) do
      {:ok, translations} ->
        translate_chunks(chunks, [translations | acc], base_body, api_key, base_url)

      {:error, _} = error ->
        error
    end
  end

  defp validate_translations(entries, translations, mode) when length(entries) == length(translations) do
    entries
    |> Enum.zip(translations)
    |> Enum.reduce_while({:ok, []}, fn {entry, translation}, {:ok, acc} ->
      translated_text = postprocess_text(translation.text, mode)

      case HtmlHandler.validate_placeholders(entry.original, translated_text) do
        :ok ->
          {:cont, {:ok, [%{translation | text: translated_text} | acc]}}

        {:error, details} ->
          {:halt, {:error, {:placeholder_mismatch, entry.index, details}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _reason} = error -> error
    end
  end

  defp validate_translations(entries, translations, _mode) do
    {:error, {:unexpected_translation_count, length(entries), length(translations)}}
  end

  defp postprocess_text(text, :html), do: HtmlHandler.post_translate(text)
  defp postprocess_text(text, :plain), do: text

  defp do_translate(body, api_key, base_url) do
    case Req.post(
           "#{base_url}/v2/translate",
           request_options(api_key, json: body)
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
    %{
      code: lang["language"],
      name: lang["name"],
      supports_formality: Map.get(lang, "supports_formality", false)
    }
  end

  # DeepL uses uppercase language codes (EN, ES, JA) or with region (EN-US, PT-BR)
  defp normalize_lang(code) when is_binary(code) do
    String.upcase(code)
  end

  defp normalize_glossary_lang(code) when is_binary(code) do
    code
    |> String.split("-", parts: 2)
    |> hd()
    |> String.downcase()
  end

  defp config_setting(%ProviderConfig{settings: settings}, key) when is_map(settings), do: settings[key]
  defp config_setting(_config, _key), do: nil

  defp request_options(api_key, extra \\ []) do
    defaults =
      Keyword.merge([headers: [{"Authorization", "DeepL-Auth-Key #{api_key}"}], retry: :transient, max_retries: 2], extra)

    Keyword.merge(defaults, Application.get_env(:storyarn, :deepl_req_options, []))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule Storyarn.Localization.BatchTranslator do
  @moduledoc false

  alias Storyarn.Localization.LanguageCrud
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.DeepL
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @default_batch_size 100
  @max_batch_size 500

  @type result :: %{
          translated: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [term()]
        }

  @doc """
  Translates all pending/untranslated texts for a project and locale using DeepL.

  Options:
  - `:source_type` - Only translate texts of this source type
  - `:status` - Only translate texts with this status (default: "pending")
  - `:limit` - Max number of texts to translate in this batch
  - `:batch_size` - Max number of texts to load per database page

  Returns `{:ok, %{translated: N, failed: M, errors: []}}` or `{:error, reason}`.
  """
  @spec translate_batch(integer(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def translate_batch(project_id, target_locale, opts \\ []) do
    with {:ok, config} <- get_provider_config(project_id),
         {:ok, source_lang} <- get_source_locale(project_id) do
      status_filter = opts[:status] || "pending"

      filter_opts = maybe_add([locale_code: target_locale, status: status_filter], :source_type, opts[:source_type])

      max_id = TextCrud.max_text_id_for_batch_translation(project_id, filter_opts)

      if is_nil(max_id) do
        {:ok, %{translated: 0, failed: 0, errors: []}}
      else
        batch_size = normalize_batch_size(opts[:batch_size])
        limit = normalize_limit(opts[:limit])
        translator = Keyword.get(opts, :translator, DeepL)

        translate_pages(project_id, filter_opts, source_lang, target_locale, config, translator, %{
          after_id: 0,
          max_id: max_id,
          batch_size: batch_size,
          remaining: limit,
          cancelled?: Keyword.get(opts, :cancelled?, fn -> false end),
          progress_callback: Keyword.get(opts, :progress_callback, fn _result -> :ok end),
          result: %{translated: 0, failed: 0, errors: []}
        })
      end
    end
  end

  @doc """
  Translates a single localized text entry using DeepL.
  Returns `{:ok, updated_text}` or `{:error, reason}`.
  """
  @spec translate_single(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def translate_single(project_id, text_id) do
    with {:ok, config} <- get_provider_config(project_id),
         {:ok, source_lang} <- get_source_locale(project_id),
         text when not is_nil(text) <- TextCrud.get_text(project_id, text_id) do
      do_translate_single(text, source_lang, config)
    else
      nil -> {:error, :text_not_found}
      error -> error
    end
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp do_translate_single(text, source_lang, config) do
    source_text = text.source_text

    if source_text && String.trim(source_text) != "" do
      case DeepL.translate([source_text], source_lang, text.locale_code, config) do
        {:ok, [%{text: translated}]} ->
          now = TimeHelpers.now()

          TextCrud.update_text(text, %{
            "translated_text" => translated,
            "status" => "draft",
            "machine_translated" => true,
            "last_translated_at" => now
          })

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :empty_source_text}
    end
  end

  defp translate_pages(_project_id, _filter_opts, _source_lang, _target_locale, _config, _translator, %{
         remaining: 0,
         result: result
       }) do
    {:ok, result}
  end

  defp translate_pages(project_id, filter_opts, source_lang, target_locale, config, translator, state) do
    if state.cancelled?.() do
      {:error, :cancelled}
    else
      translate_next_page(project_id, filter_opts, source_lang, target_locale, config, translator, state)
    end
  end

  defp translate_next_page(project_id, filter_opts, source_lang, target_locale, config, translator, state) do
    page_limit = page_limit(state.batch_size, state.remaining)

    texts =
      TextCrud.list_texts_for_batch_translation(
        project_id,
        filter_opts
        |> Keyword.put(:after_id, state.after_id)
        |> Keyword.put(:max_id, state.max_id)
        |> Keyword.put(:limit, page_limit)
      )

    case texts do
      [] ->
        {:ok, state.result}

      texts ->
        last_id = texts |> List.last() |> Map.fetch!(:id)

        case do_batch_translate(texts, source_lang, target_locale, config, translator) do
          {:ok, result} ->
            merged_result = merge_results(state.result, result)
            state.progress_callback.(merged_result)

            translate_pages(project_id, filter_opts, source_lang, target_locale, config, translator, %{
              state
              | after_id: last_id,
                remaining: decrement_remaining(state.remaining, length(texts)),
                result: merged_result
            })

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp do_batch_translate(texts, source_lang, target_locale, config, translator) do
    # Filter out nil/empty texts — track their indices
    {indexed_texts, skipped_count} =
      texts
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {text, idx}, {acc, skipped} ->
        if text.source_text && String.trim(text.source_text) != "" do
          {[{text, idx} | acc], skipped}
        else
          {acc, skipped + 1}
        end
      end)

    indexed_texts = Enum.reverse(indexed_texts)

    if indexed_texts == [] do
      {:ok, %{translated: 0, failed: skipped_count, errors: []}}
    else
      translatable_texts = Enum.map(indexed_texts, fn {text, _idx} -> text.source_text end)

      case translator.translate(translatable_texts, source_lang, target_locale, config) do
        {:ok, translations} ->
          now = TimeHelpers.now()
          {translated, failed, errors} = apply_translations(indexed_texts, translations, now)

          {:ok,
           %{
             translated: translated,
             failed: failed + skipped_count,
             errors: errors
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp merge_results(left, right) do
    %{
      translated: left.translated + right.translated,
      failed: left.failed + right.failed,
      errors: left.errors ++ right.errors
    }
  end

  defp apply_translations(indexed_texts, translations, now) do
    indexed_texts
    |> Enum.zip(translations)
    |> Enum.reduce({0, 0, []}, fn {{text, _idx}, %{text: translated}}, {ok, fail, errs} ->
      case TextCrud.update_text(text, %{
             "translated_text" => translated,
             "status" => "draft",
             "machine_translated" => true,
             "last_translated_at" => now
           }) do
        {:ok, _} ->
          {ok + 1, fail, errs}

        {:error, reason} ->
          {ok, fail + 1, [{text.id, reason} | errs]}
      end
    end)
  end

  defp get_provider_config(project_id) do
    case Repo.get_by(ProviderConfig, project_id: project_id, provider: "deepl") do
      nil -> {:error, :no_provider_configured}
      %{is_active: false} -> {:error, :provider_disabled}
      %{api_key_encrypted: nil} -> {:error, :no_api_key}
      config -> {:ok, config}
    end
  end

  defp get_source_locale(project_id) do
    case LanguageCrud.get_source_language(project_id) do
      nil -> {:error, :no_source_language}
      lang -> {:ok, lang.locale_code}
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_batch_size(value) when is_integer(value) and value > 0 do
    min(value, @max_batch_size)
  end

  defp normalize_batch_size(_value), do: @default_batch_size

  defp normalize_limit(value) when is_integer(value) and value >= 0, do: value
  defp normalize_limit(_value), do: :infinity

  defp page_limit(batch_size, :infinity), do: batch_size
  defp page_limit(batch_size, remaining), do: min(batch_size, remaining)

  defp decrement_remaining(:infinity, _count), do: :infinity
  defp decrement_remaining(remaining, count), do: max(remaining - count, 0)
end

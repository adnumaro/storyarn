defmodule Storyarn.Localization.BatchTranslator do
  @moduledoc false

  alias Storyarn.Localization.{LanguageCrud, Providers.DeepL, TextCrud}
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

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

  Returns `{:ok, %{translated: N, failed: M, errors: []}}` or `{:error, reason}`.
  """
  @spec translate_batch(integer(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def translate_batch(project_id, target_locale, opts \\ []) do
    with {:ok, config} <- get_provider_config(project_id),
         {:ok, source_lang} <- get_source_locale(project_id) do
      status_filter = opts[:status] || "pending"

      filter_opts =
        [locale_code: target_locale, status: status_filter]
        |> maybe_add(:source_type, opts[:source_type])
        |> maybe_add(:limit, opts[:limit])

      texts = TextCrud.list_texts(project_id, filter_opts)

      if texts == [] do
        {:ok, %{translated: 0, failed: 0, errors: []}}
      else
        do_batch_translate(texts, source_lang, target_locale, config)
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

  defp do_batch_translate(texts, source_lang, target_locale, config) do
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

      case DeepL.translate(translatable_texts, source_lang, target_locale, config) do
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
end

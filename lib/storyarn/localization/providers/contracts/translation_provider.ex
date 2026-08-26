defmodule Storyarn.Localization.TranslationProvider do
  @moduledoc """
  Behaviour for translation provider adapters.

  Each provider (DeepL, etc.) implements this behaviour to provide
  translation services. The behaviour abstracts away provider-specific
  API details.
  """

  @type config :: map()
  @type translation_result :: %{text: String.t(), detected_source_lang: String.t() | nil}
  @type usage_result :: %{character_count: integer(), character_limit: integer()}
  @type language_info :: %{code: String.t(), name: String.t()}

  @doc """
  Translates a list of texts from source language to target language.
  Returns translated texts in the same order.
  """
  @callback translate(
              texts :: [String.t()],
              source_lang :: String.t() | nil,
              target_lang :: String.t(),
              config :: config(),
              opts :: keyword()
            ) ::
              {:ok, [translation_result()]} | {:error, term()}

  @doc """
  Gets the current API usage for the provider account.
  """
  @callback get_usage(config :: config()) ::
              {:ok, usage_result()} | {:error, term()}

  @doc """
  Returns the list of supported languages for the provider.
  """
  @callback supported_languages(config :: config()) ::
              {:ok, [language_info()]} | {:error, term()}

  @doc """
  Creates a glossary on the provider service.
  """
  @callback create_glossary(
              name :: String.t(),
              source_lang :: String.t(),
              target_lang :: String.t(),
              entries :: [{String.t(), String.t()}],
              config :: config()
            ) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Deletes a glossary from the provider service.
  """
  @callback delete_glossary(glossary_id :: String.t(), config :: config()) ::
              :ok | {:error, term()}

  @optional_callbacks [create_glossary: 5, delete_glossary: 2]
end

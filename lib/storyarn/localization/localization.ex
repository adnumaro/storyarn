defmodule Storyarn.Localization do
  @moduledoc """
  The Localization context.

  Manages content localization for projects: languages, translations,
  glossary entries, and translation provider configurations.

  This module serves as a facade, delegating to specialized submodules:
  - `LanguageCrud` - CRUD operations for project languages
  - `TextCrud` - CRUD operations and queries for localized texts
  - `BatchTranslator` - Batch translation orchestrator
  """

  alias Storyarn.Localization.{
    BatchTranslator,
    ExportImport,
    GlossaryCrud,
    GlossaryEntry,
    LanguageCrud,
    LocalizedText,
    ProjectLanguage,
    ProviderConfig,
    Reports,
    TextCrud,
    TextExtractor
  }

  alias Storyarn.Projects.Project

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type project_language :: ProjectLanguage.t()
  @type localized_text :: LocalizedText.t()
  @type glossary_entry :: GlossaryEntry.t()
  @type provider_config :: ProviderConfig.t()
  @type id :: integer()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  # =============================================================================
  # Project Languages
  # =============================================================================

  @doc "Lists all languages for a project, ordered by position then name."
  @spec list_languages(id()) :: [project_language()]
  defdelegate list_languages(project_id), to: LanguageCrud

  @doc "Gets a single language by ID within a project."
  @spec get_language(id(), id()) :: project_language() | nil
  defdelegate get_language(project_id, language_id), to: LanguageCrud

  @doc "Gets a language by locale code within a project."
  @spec get_language_by_locale(id(), String.t()) :: project_language() | nil
  defdelegate get_language_by_locale(project_id, locale_code), to: LanguageCrud

  @doc "Gets the source language for a project."
  @spec get_source_language(id()) :: project_language() | nil
  defdelegate get_source_language(project_id), to: LanguageCrud

  @doc "Gets all target (non-source) languages for a project."
  @spec get_target_languages(id()) :: [project_language()]
  defdelegate get_target_languages(project_id), to: LanguageCrud

  @doc "Adds a new language to a project."
  @spec add_language(Project.t(), attrs()) :: {:ok, project_language()} | {:error, changeset()}
  defdelegate add_language(project, attrs), to: LanguageCrud

  @doc "Updates a project language."
  @spec update_language(project_language(), attrs()) ::
          {:ok, project_language()} | {:error, changeset()}
  defdelegate update_language(language, attrs), to: LanguageCrud

  @doc "Removes a language from a project."
  @spec remove_language(project_language()) :: {:ok, project_language()} | {:error, changeset()}
  defdelegate remove_language(language), to: LanguageCrud

  @doc "Sets a language as the source language (unsets any existing source)."
  @spec set_source_language(project_language()) :: {:ok, project_language()}
  defdelegate set_source_language(language), to: LanguageCrud

  @doc "Reorders languages by the given list of IDs."
  @spec reorder_languages(id(), [id()]) :: {:ok, any()}
  defdelegate reorder_languages(project_id, language_ids), to: LanguageCrud

  @doc "Ensures a source language exists for the project (auto-creates from workspace if missing)."
  @spec ensure_source_language(Project.t()) :: {:ok, project_language()} | {:error, changeset()}
  defdelegate ensure_source_language(project), to: LanguageCrud

  # =============================================================================
  # Localized Texts
  # =============================================================================

  @doc "Lists localized texts for a project with optional filters."
  @spec list_texts(id(), keyword()) :: [localized_text()]
  defdelegate list_texts(project_id, opts \\ []), to: TextCrud

  @doc "Counts localized texts for a project with optional filters."
  @spec count_texts(id(), keyword()) :: non_neg_integer()
  defdelegate count_texts(project_id, opts \\ []), to: TextCrud

  @doc "Gets a single localized text by ID."
  @spec get_text(id()) :: localized_text() | nil
  defdelegate get_text(id), to: TextCrud

  @doc "Gets a single localized text by ID, raises if not found."
  @spec get_text!(id()) :: localized_text()
  defdelegate get_text!(id), to: TextCrud

  @doc "Gets a localized text by its composite source key."
  @spec get_text_by_source(String.t(), id(), String.t(), String.t()) :: localized_text() | nil
  defdelegate get_text_by_source(source_type, source_id, source_field, locale_code), to: TextCrud

  @doc "Gets all localized texts for a source entity across all locales."
  @spec get_texts_for_source(String.t(), id()) :: [localized_text()]
  defdelegate get_texts_for_source(source_type, source_id), to: TextCrud

  @doc "Gets translation progress stats for a project and locale."
  @spec get_progress(id(), String.t()) :: map()
  defdelegate get_progress(project_id, locale_code), to: TextCrud

  @doc "Creates a new localized text."
  @spec create_text(id(), attrs()) :: {:ok, localized_text()} | {:error, changeset()}
  defdelegate create_text(project_id, attrs), to: TextCrud

  @doc "Updates a localized text."
  @spec update_text(localized_text(), attrs()) :: {:ok, localized_text()} | {:error, changeset()}
  defdelegate update_text(text, attrs), to: TextCrud

  @doc "Upserts a localized text by its composite key."
  @spec upsert_text(id(), attrs()) :: {:ok, localized_text()} | {:error, changeset()}
  defdelegate upsert_text(project_id, attrs), to: TextCrud

  @doc "Deletes all localized texts for a source entity."
  @spec delete_texts_for_source(String.t(), id()) :: {non_neg_integer(), nil}
  defdelegate delete_texts_for_source(source_type, source_id), to: TextCrud

  @doc "Deletes all localized texts for a specific source field."
  @spec delete_texts_for_source_field(String.t(), id(), String.t()) :: {non_neg_integer(), nil}
  defdelegate delete_texts_for_source_field(source_type, source_id, source_field), to: TextCrud

  # =============================================================================
  # Text Extraction
  # =============================================================================

  @doc "Extracts all localizable texts for a project (flows, nodes, sheets, blocks)."
  @spec extract_all(id()) :: {:ok, non_neg_integer()}
  defdelegate extract_all(project_id), to: TextExtractor

  # =============================================================================
  # Translation
  # =============================================================================

  @doc "Translates all pending texts for a project and locale using DeepL."
  @spec translate_batch(id(), String.t(), keyword()) ::
          {:ok, BatchTranslator.result()} | {:error, term()}
  defdelegate translate_batch(project_id, target_locale, opts \\ []), to: BatchTranslator

  @doc "Translates a single localized text entry using DeepL."
  @spec translate_single(id(), id()) :: {:ok, localized_text()} | {:error, term()}
  defdelegate translate_single(project_id, text_id), to: BatchTranslator

  # =============================================================================
  # Export / Import
  # =============================================================================

  @doc "Exports localized texts to Excel (.xlsx) binary."
  @spec export_xlsx(id(), keyword()) :: {:ok, binary()}
  defdelegate export_xlsx(project_id, opts), to: ExportImport

  @doc "Exports localized texts to CSV string."
  @spec export_csv(id(), keyword()) :: {:ok, String.t()}
  defdelegate export_csv(project_id, opts), to: ExportImport

  @doc "Imports translations from CSV content."
  @spec import_csv(String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate import_csv(csv_content), to: ExportImport

  # =============================================================================
  # Glossary
  # =============================================================================

  @doc "Lists glossary entries for a project."
  @spec list_glossary_entries(id(), keyword()) :: [glossary_entry()]
  defdelegate list_glossary_entries(project_id, opts \\ []), to: GlossaryCrud, as: :list_entries

  @doc "Gets a single glossary entry."
  @spec get_glossary_entry(id()) :: glossary_entry() | nil
  defdelegate get_glossary_entry(id), to: GlossaryCrud, as: :get_entry

  @doc "Gets glossary entries for a language pair as tuples."
  @spec get_glossary_entries_for_pair(id(), String.t(), String.t()) ::
          [{String.t(), String.t()}]
  defdelegate get_glossary_entries_for_pair(project_id, source_locale, target_locale),
    to: GlossaryCrud,
    as: :get_entries_for_pair

  @doc "Creates a glossary entry."
  @spec create_glossary_entry(Project.t(), attrs()) ::
          {:ok, glossary_entry()} | {:error, changeset()}
  defdelegate create_glossary_entry(project, attrs), to: GlossaryCrud, as: :create_entry

  @doc "Updates a glossary entry."
  @spec update_glossary_entry(glossary_entry(), attrs()) ::
          {:ok, glossary_entry()} | {:error, changeset()}
  defdelegate update_glossary_entry(entry, attrs), to: GlossaryCrud, as: :update_entry

  @doc "Deletes a glossary entry."
  @spec delete_glossary_entry(glossary_entry()) :: {:ok, glossary_entry()} | {:error, changeset()}
  defdelegate delete_glossary_entry(entry), to: GlossaryCrud, as: :delete_entry

  # =============================================================================
  # Reports
  # =============================================================================

  @doc "Returns translation progress per language."
  @spec progress_by_language(id()) :: [map()]
  defdelegate progress_by_language(project_id), to: Reports

  @doc "Returns word counts per speaker for a locale."
  @spec word_counts_by_speaker(id(), String.t()) :: [map()]
  defdelegate word_counts_by_speaker(project_id, locale_code), to: Reports

  @doc "Returns VO progress for a locale."
  @spec vo_progress(id(), String.t()) :: map()
  defdelegate vo_progress(project_id, locale_code), to: Reports

  @doc "Returns counts by source type for a locale."
  @spec counts_by_source_type(id(), String.t()) :: map()
  defdelegate counts_by_source_type(project_id, locale_code), to: Reports

  # =============================================================================
  # Provider Configuration
  # =============================================================================

  @doc "Gets the translation provider config for a project. Returns nil if not configured."
  @spec get_provider_config(id(), String.t()) :: provider_config() | nil
  def get_provider_config(project_id, provider \\ "deepl") do
    Storyarn.Repo.get_by(ProviderConfig, project_id: project_id, provider: provider)
  end

  @doc "Returns true if the project has an active provider with an API key."
  @spec has_active_provider?(id()) :: boolean()
  def has_active_provider?(project_id) do
    case get_provider_config(project_id) do
      %{is_active: true, api_key_encrypted: key} when not is_nil(key) -> true
      _ -> false
    end
  end

  @doc "Creates or updates a provider config for a project."
  @spec upsert_provider_config(Project.t(), map()) ::
          {:ok, provider_config()} | {:error, changeset()}
  def upsert_provider_config(%Project{} = project, attrs) do
    case get_provider_config(project.id) do
      nil ->
        %ProviderConfig{project_id: project.id}
        |> ProviderConfig.changeset(Map.put(attrs, "provider", "deepl"))
        |> Storyarn.Repo.insert()

      config ->
        config
        |> ProviderConfig.changeset(attrs)
        |> Storyarn.Repo.update()
    end
  end
end

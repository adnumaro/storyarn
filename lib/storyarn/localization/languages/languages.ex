defmodule Storyarn.Localization.Languages do
  @moduledoc false

  alias Storyarn.Localization.Languages.Commands.Add
  alias Storyarn.Localization.Languages.Commands.ChangeSource
  alias Storyarn.Localization.Languages.Commands.EnsureSource
  alias Storyarn.Localization.Languages.Commands.Import
  alias Storyarn.Localization.Languages.Commands.Remove
  alias Storyarn.Localization.Languages.Commands.Reorder
  alias Storyarn.Localization.Languages.Commands.Update
  alias Storyarn.Localization.Languages.Queries.Languages, as: LanguageQueries
  alias Storyarn.Localization.Languages.ReferenceData.Catalog

  defdelegate list_languages(project_id), to: LanguageQueries, as: :list
  defdelegate list_languages_for_backup(project_id), to: LanguageQueries, as: :list_for_backup
  defdelegate get_language(project_id, language_id), to: LanguageQueries, as: :get
  defdelegate get_language_by_locale(project_id, locale_code), to: LanguageQueries, as: :get_by_locale
  defdelegate get_source_language(project_id), to: LanguageQueries, as: :get_source
  defdelegate get_target_languages(project_id), to: LanguageQueries, as: :get_targets

  defdelegate add_language(project, attrs), to: Add, as: :run
  defdelegate add_language(actor_scope, project, attrs), to: Add, as: :run
  defdelegate add_language_with_count(project, attrs), to: Add, as: :run_with_count
  defdelegate add_language_with_count(actor_scope, project, attrs), to: Add, as: :run_with_count
  defdelegate update_language(language, attrs), to: Update, as: :run
  defdelegate remove_language(language), to: Remove, as: :run
  defdelegate remove_language(actor_scope, language), to: Remove, as: :run
  defdelegate set_source_language(language), to: ChangeSource, as: :set
  defdelegate change_source_language(project, locale_code), to: ChangeSource, as: :run
  defdelegate change_source_language(first, second, third), to: ChangeSource, as: :run

  defdelegate change_source_language(actor_scope, project, locale_code, opts),
    to: ChangeSource,
    as: :run

  defdelegate reorder_languages(project_id, language_ids), to: Reorder, as: :run
  defdelegate ensure_source_language(project), to: EnsureSource, as: :run
  defdelegate import_language(project_id, attrs), to: Import, as: :run

  defdelegate all(), to: Catalog
  defdelegate get(code), to: Catalog
  defdelegate name(code), to: Catalog
  defdelegate flag_code(code), to: Catalog
  defdelegate short_label(code), to: Catalog
  defdelegate options_for_select(opts \\ []), to: Catalog
end

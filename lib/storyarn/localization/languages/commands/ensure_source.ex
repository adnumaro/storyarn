defmodule Storyarn.Localization.Languages.Commands.EnsureSource do
  @moduledoc false

  alias Storyarn.Localization.Languages.Commands.Add
  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.Languages.Queries.Languages, as: LanguageQueries
  alias Storyarn.Localization.Languages.ReferenceData.Catalog
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.Texts
  alias Storyarn.Repo

  def run(%{id: project_id}) when is_integer(project_id) and project_id > 0 do
    case LanguageQueries.get_source(project_id) do
      %ProjectLanguage{} = language ->
        {:ok, language}

      nil ->
        Repo.transaction(fn -> ensure_source_in_transaction!(project_id) end)
    end
  end

  defp ensure_source_in_transaction!(project_id) do
    locked_project = Locks.lock_project!(project_id)
    :ok = Texts.lock_inventory!(project_id)

    case LanguageQueries.get_source(project_id) do
      %ProjectLanguage{} = language ->
        language

      nil ->
        project = Repo.preload(locked_project, :workspace)
        locale = LocaleCode.normalize(project.workspace.source_locale || "en")

        case Add.run(project, %{
               "locale_code" => locale,
               "name" => Catalog.name(locale),
               "is_source" => true
             }) do
          {:ok, language} -> language
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end
end

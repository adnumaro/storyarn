defmodule Storyarn.Localization.Languages.Commands.EnsureSource do
  @moduledoc false

  alias Storyarn.Localization.Languages.Commands.Add
  alias Storyarn.Localization.Languages.Data.Catalog
  alias Storyarn.Localization.Languages.Data.ProjectRecord
  alias Storyarn.Localization.Languages.Queries.Languages, as: LanguageQueries
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo

  def run(%{id: project_id}) when is_integer(project_id) and project_id > 0 do
    case LanguageQueries.get_source(project_id) do
      %ProjectLanguage{} = language ->
        {:ok, language}

      nil ->
        project = ProjectRecord |> Repo.get!(project_id) |> Repo.preload(:workspace)
        locale = project.workspace.source_locale || "en"
        name = Catalog.name(locale)

        Add.run(project, %{
          "locale_code" => locale,
          "name" => name,
          "is_source" => true
        })
    end
  end
end

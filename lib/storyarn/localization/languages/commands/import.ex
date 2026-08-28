defmodule Storyarn.Localization.Languages.Commands.Import do
  @moduledoc false

  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo

  def run(project_id, attrs) do
    %ProjectLanguage{project_id: project_id}
    |> ProjectLanguage.create_changeset(attrs)
    |> Repo.insert()
  end
end

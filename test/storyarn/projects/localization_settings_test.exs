defmodule Storyarn.Projects.LocalizationSettingsTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  test "ensure_source_language reactivates an archived workspace locale" do
    user = user_fixture()
    workspace = workspace_fixture(user, %{source_locale: "pt-BR"})
    project = project_fixture(user, %{workspace: workspace})

    archived =
      %ProjectLanguageRecord{project_id: project.id}
      |> ProjectLanguageRecord.create_changeset(%{
        locale_code: "pt-BR",
        name: "Archived Portuguese",
        is_source: false,
        position: 4,
        archived_at: TimeHelpers.now()
      })
      |> Repo.insert!()

    assert {:ok, source} = Projects.ensure_source_language(project)
    assert source.id == archived.id
    assert source.locale_code == "pt-br"
    assert source.name == "Portuguese (Brazil)"
    assert source.is_source
    assert is_nil(source.archived_at)

    assert [%ProjectLanguageRecord{id: persisted_id}] =
             Repo.all(
               from(language in ProjectLanguageRecord,
                 where: language.project_id == ^project.id and language.locale_code == "pt-br"
               )
             )

    assert persisted_id == source.id
  end
end

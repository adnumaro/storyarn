defmodule Storyarn.Localization.Languages.Commands.EnsureSourceTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  test "ensure_source_language returns the existing source without changing it" do
    user = user_fixture()
    project = project_fixture(user)
    source = source_language_fixture(project, %{name: "Existing English"})

    assert {:ok, first} = Localization.ensure_source_language(project)
    assert {:ok, second} = Localization.ensure_source_language(project)

    assert first.id == source.id
    assert second.id == source.id
    assert second.name == "Existing English"

    assert Repo.aggregate(
             from(language in ProjectLanguage,
               where:
                 language.project_id == ^project.id and language.is_source == true and
                   is_nil(language.archived_at)
             ),
             :count
           ) == 1
  end

  test "ensure_source_language reactivates an archived workspace locale" do
    user = user_fixture()
    workspace = workspace_fixture(user, %{source_locale: "pt-BR"})
    project = project_fixture(user, %{workspace: workspace})

    archived =
      %ProjectLanguage{project_id: project.id}
      |> ProjectLanguage.create_changeset(%{
        locale_code: "pt-BR",
        name: "Archived Portuguese",
        is_source: false,
        position: 4,
        archived_at: TimeHelpers.now()
      })
      |> Repo.insert!()

    assert {:ok, source} = Localization.ensure_source_language(project)
    assert source.id == archived.id
    assert source.locale_code == "pt-br"
    assert source.name == "Portuguese (Brazil)"
    assert source.is_source
    assert is_nil(source.archived_at)

    assert [%ProjectLanguage{id: persisted_id}] =
             Repo.all(
               from(language in ProjectLanguage,
                 where: language.project_id == ^project.id and language.locale_code == "pt-br"
               )
             )

    assert persisted_id == source.id
  end

  test "ensure_source_language preserves the normalized fallback name for a valid locale outside the catalog" do
    user = user_fixture()
    workspace = workspace_fixture(user, %{source_locale: "sr-Latn"})
    project = project_fixture(user, %{workspace: workspace})

    assert {:ok, source} = Localization.ensure_source_language(project)
    assert source.locale_code == "sr-latn"
    assert source.name == "sr-latn"
  end

  test "ensure_source_language returns project_not_found for a missing project" do
    missing_project_id = 9_000_000_000_000_000_000

    assert {:error, :project_not_found} =
             Localization.ensure_source_language(%{id: missing_project_id})
  end

  test "ensure_source_language returns project_not_active for a deleted project" do
    user = user_fixture()
    project = project_fixture(user)

    project
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    assert {:error, :project_not_active} = Localization.ensure_source_language(project)
    refute Localization.get_source_language(project.id)
  end

  test "ensure_source_language preserves the Add error and rolls back an invalid source" do
    user = user_fixture()
    workspace = workspace_fixture(user, %{source_locale: "x"})
    project = project_fixture(user, %{workspace: workspace})

    assert {:error, %Ecto.Changeset{} = changeset} =
             Localization.ensure_source_language(project)

    assert "should be at least 2 character(s)" in errors_on(changeset).locale_code
    assert Localization.list_languages(project.id) == []
    refute Localization.get_source_language(project.id)
  end
end

defmodule StoryarnWeb.E2E.TemplatesTest do
  @moduledoc """
  E2E tests for project template flows.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.Repo

  @moduletag :e2e

  test "creates a mutable project from a template in a real browser", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    source_project = project_fixture(user, %{name: "E2E Template Source"})

    {:ok, template} =
      ProjectTemplates.create_template_from_project(scope, source_project, %{
        name: "E2E Starter",
        description: "Browser install fixture"
      })

    conn
    |> authenticate(user)
    |> visit("/templates/#{template.id}")
    |> assert_has("#template-install-form")
    |> assert_has("#template-install-version")
    |> click_button("Create from template")
    |> assert_path("/workspaces/*/projects/*")

    installed_project =
      Repo.get_by!(Project, owner_id: user.id, created_from_template_version_id: template.current_version_id)

    assert installed_project.id != source_project.id
    assert installed_project.name == "E2E Starter"
    assert installed_project.created_from_template_version_id == template.current_version_id
  end
end

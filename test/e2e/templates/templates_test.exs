defmodule StoryarnWeb.E2E.TemplatesTest do
  @moduledoc """
  E2E tests for project template flows.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.Repo
  alias Storyarn.Workers.InstallProjectTemplateWorker

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  test "creates a mutable project from a template in a real browser", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    source_project = project_fixture(user, %{name: "E2E Template Source"})

    {:ok, template} =
      ProjectTemplates.create_template_from_project(scope, source_project, %{
        name: "E2E Starter",
        description: "Browser install fixture"
      })

    session =
      conn
      |> authenticate(user)
      |> visit("/templates/#{template.id}")
      |> assert_has("body .phx-connected")
      |> assert_has("#template-install-form")
      |> assert_has("#template-install-version")
      |> click_button("Create from template")
      |> assert_has("#template-active-installations")

    installation =
      Repo.get_by!(ProjectTemplateInstall,
        user_id: user.id,
        project_template_version_id: template.current_version_id
      )

    assert_enqueued(
      worker: InstallProjectTemplateWorker,
      args: %{"installation_id" => installation.id}
    )

    assert_has(session, "#template-active-installation-#{installation.id}")

    assert :ok =
             perform_job(InstallProjectTemplateWorker, %{
               "installation_id" => installation.id
             })

    assert_path(session, "/workspaces/*/projects/*")

    installed_project =
      Repo.get_by!(Project, owner_id: user.id, created_from_template_version_id: template.current_version_id)

    assert installed_project.id != source_project.id
    assert installed_project.name == "E2E Starter"
    assert installed_project.created_from_template_version_id == template.current_version_id
  end

  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end
end

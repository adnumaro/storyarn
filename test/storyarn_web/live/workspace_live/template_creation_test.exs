defmodule StoryarnWeb.WorkspaceLive.TemplateCreationTest do
  use StoryarnWeb.ConnCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.Repo
  alias Storyarn.Workers.InstallProjectTemplateWorker

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/dashboard/WorkspaceDashboard")
  end

  describe "workspace project templates" do
    setup :register_and_log_in_user

    test "passes visible templates to the new project modal", %{conn: conn, user: user, scope: scope} do
      workspace = workspace_fixture(user, %{name: "Template Studio"})
      own_template = template_fixture(user, scope, %{name: "My Starter"})

      other_user = user_fixture()
      other_scope = user_scope_fixture(other_user)
      other_private = template_fixture(other_user, other_scope, %{name: "Hidden Starter"})
      public_template = other_user |> template_fixture(other_scope, %{name: "Storyarn Demo"}) |> make_public()

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      template_ids = Enum.map(vue.props["template-creation"]["templates"], & &1["id"])

      assert own_template.id in template_ids
      assert public_template.id in template_ids
      refute other_private.id in template_ids
    end

    test "queues project creation and exposes durable progress in the current workspace", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      workspace = workspace_fixture(user, %{name: "Install Template Studio"})
      template = template_fixture(user, scope, %{name: "Starter Kit"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      html =
        render_hook(view, "create_project_from_template", %{
          "template_id" => template.id,
          "name" => "Starter Copy"
        })

      installation = Repo.get_by!(ProjectTemplateInstall, workspace_id: workspace.id, status: "queued")
      assert html =~ "Template installation started"
      assert Repo.get_by(Project, workspace_id: workspace.id, name: "Starter Copy") == nil

      vue = get_dashboard_vue(view)
      assert Enum.any?(vue.props["template-creation"]["installations"], &(&1["id"] == installation.id))

      assert :ok =
               perform_job(InstallProjectTemplateWorker, %{
                 "installation_id" => installation.id
               })

      render(view)

      project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Starter Copy")
      assert project.created_from_template_version_id == template.current_version_id

      vue = get_dashboard_vue(view)
      assert Enum.any?(vue.props["projects"], &(&1["project"]["id"] == project.id))
      assert vue.props["template-creation"]["installations"] == []
    end

    test "does not show another member's installation failure as the current user's error", %{
      conn: conn,
      user: user
    } do
      workspace = workspace_fixture(user, %{name: "Shared Installation Studio"})
      other_user = user_fixture()
      _membership = workspace_membership_fixture(workspace, other_user, "member")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      send(
        view.pid,
        {:project_template_installation_updated,
         %ProjectTemplateInstall{id: 999_001, user_id: other_user.id, status: "failed"}}
      )

      refute render(view) =~ "Template installation failed"
    end
  end

  defp template_fixture(user, scope, attrs) do
    project = project_fixture(user, %{name: "#{attrs.name} Source"})

    {:ok, template} =
      ProjectTemplates.create_template_from_project(scope, project, %{
        name: attrs.name,
        description: Map.get(attrs, :description, "Template description")
      })

    template
  end

  defp make_public(template) do
    Repo.update_all(from(t in ProjectTemplate, where: t.id == ^template.id), set: [visibility: "public"])
    ProjectTemplates.get_template!(user_scope_fixture(template.owner), template.id)
  end
end

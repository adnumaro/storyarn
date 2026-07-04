defmodule StoryarnWeb.WorkspaceLive.TemplateCreationTest do
  use StoryarnWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.Repo

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
      template_ids = Enum.map(vue.props["project-templates"], & &1["id"])

      assert own_template.id in template_ids
      assert public_template.id in template_ids
      refute other_private.id in template_ids
    end

    test "creates project from template in the current workspace", %{conn: conn, user: user, scope: scope} do
      workspace = workspace_fixture(user, %{name: "Install Template Studio"})
      template = template_fixture(user, scope, %{name: "Starter Kit"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      render_hook(view, "create_project_from_template", %{
        "template_id" => template.id,
        "name" => "Starter Copy"
      })

      project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Starter Copy")
      {path, flash} = assert_redirect(view)

      assert project.created_from_template_version_id == template.current_version_id
      assert path == ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}"
      assert flash["info"] =~ "Project created"
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

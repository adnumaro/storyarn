defmodule StoryarnWeb.TemplateLiveTest do
  use StoryarnWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo

  describe "index" do
    setup :register_and_log_in_user

    test "lists own private templates and public templates only", %{conn: conn, user: user, scope: scope} do
      own_template = template_fixture(user, scope, %{name: "My Starter"})

      other_user = user_fixture()
      other_scope = user_scope_fixture(other_user)
      other_private = template_fixture(other_user, other_scope, %{name: "Hidden Starter"})
      public_template = other_user |> template_fixture(other_scope, %{name: "Public Demo"}) |> make_public()

      {:ok, view, _html} = live(conn, ~p"/templates")

      assert has_element?(view, "#templates-index")
      assert has_element?(view, "#template-card-#{own_template.id}")
      assert has_element?(view, "#template-card-#{public_template.id}")
      refute has_element?(view, "#template-card-#{other_private.id}")
    end
  end

  describe "show" do
    setup :register_and_log_in_user

    test "installs a template into a workspace", %{conn: conn, user: user, scope: scope} do
      workspace = workspace_fixture(user, %{name: "Install Studio"})
      template = template_fixture(user, scope, %{name: "Installable Template"})

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#template-install-form")

      render_submit(element(view, "#template-install-form"), %{
        "install" => %{
          "workspace_id" => to_string(workspace.id),
          "name" => "Installed From Template"
        }
      })

      {path, flash} = assert_redirect(view)
      assert path =~ "/workspaces/#{workspace.slug}/projects/"
      assert flash["info"] =~ "Project created"

      installed_project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Installed From Template")
      assert installed_project.created_from_template_version_id == template.current_version_id
    end

    test "publishes a new version for an owned private template", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Versioned Template"})

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#publish-template-version-button")
      html = render_click(element(view, "#publish-template-version-button"))
      assert html =~ "Template version published"

      template = Repo.get!(ProjectTemplate, template.id)
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert version.version_number == 2
      assert version_count(template.id) == 2
    end

    test "does not render publish action for public templates", %{conn: conn} do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      public_template = owner |> template_fixture(owner_scope, %{name: "Read Only Demo"}) |> make_public()

      {:ok, view, _html} = live(conn, ~p"/templates/#{public_template.id}")

      refute has_element?(view, "#publish-template-version-button")
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

  defp version_count(template_id) do
    Repo.aggregate(from(v in ProjectTemplateVersion, where: v.project_template_id == ^template_id), :count)
  end
end

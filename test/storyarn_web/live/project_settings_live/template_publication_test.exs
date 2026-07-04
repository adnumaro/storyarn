defmodule StoryarnWeb.ProjectSettingsLive.TemplatePublicationTest do
  use StoryarnWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures

  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo

  defp settings_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings"
  end

  defp get_general_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsGeneral")
  end

  describe "template publication in project settings" do
    setup :register_and_log_in_user

    test "passes existing private template publications for the project", %{conn: conn, user: user, scope: scope} do
      project = user |> project_fixture(%{name: "Template Source"}) |> Repo.preload(:workspace)
      other_project = user |> project_fixture(%{name: "Other Source"}) |> Repo.preload(:workspace)

      {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Project Starter"})

      {:ok, other_template} =
        ProjectTemplates.create_template_from_project(scope, other_project, %{name: "Other Starter"})

      {:ok, view, _html} = live(conn, settings_path(project))

      vue = get_general_vue(view)
      template_ids = Enum.map(vue.props["project-templates"], & &1["id"])

      assert template.id in template_ids
      refute other_template.id in template_ids
    end

    test "creates a private template from settings", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Publish Source"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "publish_template", %{
          "template" => %{
            "mode" => "new",
            "name" => "Settings Starter",
            "description" => "Created from settings"
          }
        })

      assert html =~ "Template published"

      template = Repo.get_by!(ProjectTemplate, source_project_id: project.id, name: "Settings Starter")
      assert template.visibility == "private"
      assert template.current_version_id
    end

    test "updates an existing template publication from settings", %{conn: conn, user: user, scope: scope} do
      project = user |> project_fixture(%{name: "Version Source"}) |> Repo.preload(:workspace)
      {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Versioned Starter"})

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "publish_template", %{
          "template" => %{
            "mode" => "update",
            "template_id" => template.id,
            "name" => "Versioned Starter Updated",
            "description" => "Updated from settings"
          }
        })

      assert html =~ "Template published"

      template = Repo.get!(ProjectTemplate, template.id)
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert template.name == "Versioned Starter Updated"
      assert template.description == "Updated from settings"
      assert version.version_number == 2
      assert version_count(template.id) == 2
    end
  end

  defp version_count(template_id) do
    Repo.aggregate(from(v in ProjectTemplateVersion, where: v.project_template_id == ^template_id), :count)
  end
end

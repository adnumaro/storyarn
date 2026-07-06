defmodule StoryarnWeb.ProjectSettingsLive.TemplatePublicationTest do
  use StoryarnWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures

  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
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

    test "queues a private template publication from settings", %{conn: conn, user: user} do
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

      assert html =~ "Template publication queued"

      publication = Repo.get_by!(ProjectTemplatePublication, source_project_id: project.id, name: "Settings Starter")
      assert publication.mode == "new"
      assert publication.status == "queued"
      assert publication.oban_job_id

      vue = get_general_vue(view)
      publication_ids = Enum.map(vue.props["project-template-publications"], & &1["id"])
      assert publication.id in publication_ids
    end

    test "queues an existing template publication update from settings", %{conn: conn, user: user, scope: scope} do
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

      assert html =~ "Template publication queued"

      publication = Repo.get_by!(ProjectTemplatePublication, project_template_id: template.id, status: "queued")
      unchanged_template = Repo.get!(ProjectTemplate, template.id)

      assert publication.mode == "update"
      assert publication.status == "queued"
      assert publication.name == "Versioned Starter Updated"
      assert publication.description == "Updated from settings"
      assert unchanged_template.name == "Versioned Starter"
      assert version_count(template.id) == 1
    end
  end

  defp version_count(template_id) do
    Repo.aggregate(from(v in ProjectTemplateVersion, where: v.project_template_id == ^template_id), :count)
  end
end

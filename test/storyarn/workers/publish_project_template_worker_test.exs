defmodule Storyarn.Workers.PublishProjectTemplateWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.ProjectTemplates
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Workers.PublishProjectTemplateWorker
  alias Storyarn.Workspaces.WorkspaceMembership

  describe "perform/1" do
    test "snoozes session lock contention without consuming the retry budget" do
      assert {:snooze, 30} =
               PublishProjectTemplateWorker.handle_perform_result(
                 {:error, :session_lock_timeout},
                 123
               )
    end

    test "publishes a queued new template" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user, %{name: "Worker Source"})

      {:ok, publication} =
        ProjectTemplates.request_template_publication(scope, project, %{
          name: "Worker Starter",
          description: "Created by worker",
          version_notes: "Worker v1 notes"
        })

      assert :ok = perform_job(PublishProjectTemplateWorker, %{"publication_id" => publication.id})

      publication = Repo.get!(ProjectTemplatePublication, publication.id)
      template = Repo.get!(ProjectTemplate, publication.project_template_id)
      version = Repo.get!(ProjectTemplateVersion, publication.project_template_version_id)

      assert publication.status == "published"
      assert template.name == "Worker Starter"
      assert template.description == "Created by worker"
      assert template.current_version_id == version.id
      assert version.version_number == 1
      assert version.version_notes == "Worker v1 notes"
      assert is_map(version.preview["project"])
      assert version.snapshot_storage_key =~ "project_template_publications/#{publication.id}/snapshot-"
    end

    test "updates metadata and publishes a new immutable version" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user, %{name: "Version Worker Source"})

      {:ok, template} = ProjectTemplates.create_template_from_project(scope, project, %{name: "Starter"})
      first_version_id = template.current_version_id

      {:ok, publication} =
        ProjectTemplates.request_template_version_publication(scope, template, project, %{
          name: "Starter Updated",
          description: "Updated by worker",
          version_notes: "Second version notes"
        })

      assert :ok = perform_job(PublishProjectTemplateWorker, %{"publication_id" => publication.id})

      template = Repo.get!(ProjectTemplate, template.id)
      second_version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert template.name == "Starter Updated"
      assert template.description == "Updated by worker"
      assert second_version.version_number == 2
      assert second_version.version_notes == "Second version notes"
      assert first_version_id != second_version.id
      assert Repo.get!(ProjectTemplateVersion, first_version_id).version_number == 1
    end

    test "marks publication failed if the requester loses project management permission" do
      user = user_fixture()
      scope = user_scope_fixture(user)
      project = project_fixture(user)

      {:ok, publication} = ProjectTemplates.request_template_publication(scope, project, %{name: "Lost Access"})

      Repo.update_all(
        from(m in ProjectMembership, where: m.project_id == ^project.id and m.user_id == ^user.id),
        set: [role: "viewer"]
      )

      Repo.update_all(
        from(m in WorkspaceMembership, where: m.workspace_id == ^project.workspace_id and m.user_id == ^user.id),
        set: [role: "viewer"]
      )

      assert :ok = perform_job(PublishProjectTemplateWorker, %{"publication_id" => publication.id})

      publication = Repo.get!(ProjectTemplatePublication, publication.id)

      assert publication.status == "failed"
      assert publication.error_code == "unauthorized"
      refute publication.project_template_id
    end
  end
end

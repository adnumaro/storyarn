defmodule StoryarnWeb.TemplateLiveTest do
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
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Workers.DeleteProjectTemplateArtifactsWorker
  alias Storyarn.Workers.InstallProjectTemplateWorker
  alias Storyarn.Workers.PublishProjectTemplateWorker

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

    test "archives and restores a private template from the listing", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Archivable Starter"})

      {:ok, view, _html} = live(conn, ~p"/templates")

      assert has_element?(view, "#archive-template-#{template.id}")
      render_click(element(view, "#archive-template-#{template.id}"))

      assert has_element?(view, "#unarchive-template-#{template.id}")
      refute has_element?(view, "#template-card-#{template.id} a[href='/templates/#{template.id}']")

      render_click(element(view, "#unarchive-template-#{template.id}"))

      assert has_element?(view, "#archive-template-#{template.id}")
      assert has_element?(view, "#template-card-#{template.id} a[href='/templates/#{template.id}']")
    end

    test "permanently deletes an archived private template from the listing", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Disposable Starter"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      storage_keys = [version.snapshot_storage_key, version.asset_manifest_storage_key]
      archive_template(template)

      {:ok, view, _html} = live(conn, ~p"/templates")

      assert has_element?(view, "#delete-template-#{template.id}")
      render_click(element(view, "#delete-template-#{template.id}"))

      assert has_element?(view, "#delete-template-confirmation-#{template.id}")
      assert has_element?(view, "#confirm-delete-template-#{template.id}")

      html = render_click(element(view, "#confirm-delete-template-#{template.id}"))

      refute has_element?(view, "#template-card-#{template.id}")
      assert html =~ "Template permanently deleted"
      assert Repo.get(ProjectTemplate, template.id) == nil

      assert_enqueued(
        worker: DeleteProjectTemplateArtifactsWorker,
        args: %{"storage_keys" => storage_keys}
      )
    end
  end

  describe "show" do
    setup :register_and_log_in_user

    test "queues a template installation and navigates when it completes", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      workspace = workspace_fixture(user, %{name: "Install Studio"})
      template = template_fixture(user, scope, %{name: "Installable Template"})

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#template-install-form")

      html =
        render_submit(element(view, "#template-install-form"), %{
          "install" => %{
            "workspace_id" => to_string(workspace.id),
            "version_id" => to_string(template.current_version_id),
            "name" => "Installed From Template"
          }
        })

      installation = Repo.get_by!(ProjectTemplateInstall, workspace_id: workspace.id, status: "queued")
      assert html =~ "Template installation started"
      assert has_element?(view, "#template-active-installation-#{installation.id}")

      assert :ok =
               perform_job(InstallProjectTemplateWorker, %{
                 "installation_id" => installation.id
               })

      {path, flash} = assert_redirect(view)
      assert path =~ "/workspaces/#{workspace.slug}/projects/"
      assert flash["info"] =~ "project is ready"

      installed_project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Installed From Template")
      assert installed_project.created_from_template_version_id == template.current_version_id
    end

    test "does not show failure feedback for an installation that was already dismissed", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Dismissed Failure Template"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      send(
        view.pid,
        {:project_template_installation_updated,
         %ProjectTemplateInstall{
           id: 999_002,
           status: "failed",
           feedback_dismissed_at: DateTime.utc_now(),
           project_template_version: version
         }}
      )

      refute render(view) =~ "Template installation failed"
    end

    test "installs a selected older template version", %{conn: conn, user: user, scope: scope} do
      workspace = workspace_fixture(user, %{name: "Version Install Studio"})
      template = template_fixture(user, scope, %{name: "Versioned Install Template"})
      first_version_id = template.current_version_id

      {:ok, template} = ProjectTemplates.publish_new_version(scope, template, template.source_project)

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#template-install-version")
      assert has_element?(view, "#template-version-#{first_version_id}")
      assert has_element?(view, "#template-version-#{template.current_version_id}")

      render_submit(element(view, "#template-install-form"), %{
        "install" => %{
          "workspace_id" => to_string(workspace.id),
          "version_id" => to_string(first_version_id),
          "name" => "Installed From Version One"
        }
      })

      installation = Repo.get_by!(ProjectTemplateInstall, workspace_id: workspace.id, status: "queued")

      assert :ok =
               perform_job(InstallProjectTemplateWorker, %{
                 "installation_id" => installation.id
               })

      {path, _flash} = assert_redirect(view)
      assert path =~ "/workspaces/#{workspace.slug}/projects/"

      installed_project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Installed From Version One")
      assert installed_project.created_from_template_version_id == first_version_id
    end

    test "queues a new version publication for an owned private template", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Versioned Template"})
      first_version_id = template.current_version_id

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#publish-template-version-button")

      html =
        render_submit(element(view, "#publish-template-version-form"), %{
          "publication" => %{"version_notes" => "LiveView version notes"}
        })

      assert html =~ "Template publication queued"

      publication = Repo.get_by!(ProjectTemplatePublication, project_template_id: template.id, status: "queued")
      template = Repo.get!(ProjectTemplate, template.id)

      assert publication.status == "queued"
      assert publication.version_notes == "LiveView version notes"
      assert template.current_version_id == first_version_id
      assert version_count(template.id) == 1
      assert has_element?(view, "#template-publication-#{publication.id}")

      assert :ok = perform_job(PublishProjectTemplateWorker, %{"publication_id" => publication.id})

      template = Repo.get!(ProjectTemplate, template.id)
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)

      assert version.version_number == 2
      assert version.version_notes == "LiveView version notes"
      assert version_count(template.id) == 2
    end

    test "shows a plan limit error instead of crashing when version limit is reached", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Version Limited Template"})
      template = Repo.preload(template, :source_project)

      insert_template_versions_to_limit(template, template.source_project, user)
      publication_count = template_publication_count(template.id)

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(view, "#publish-template-version-button")

      html =
        render_submit(element(view, "#publish-template-version-form"), %{
          "publication" => %{"version_notes" => "Blocked"}
        })

      assert html =~ "Template version limit reached for your plan"
      assert template_publication_count(template.id) == publication_count
    end

    test "does not render publish action for public templates", %{conn: conn} do
      owner = user_fixture()
      owner_scope = user_scope_fixture(owner)
      public_template = owner |> template_fixture(owner_scope, %{name: "Read Only Demo"}) |> make_public()

      {:ok, view, _html} = live(conn, ~p"/templates/#{public_template.id}")

      refute has_element?(view, "#publish-template-version-button")
      refute render(view) =~ owner.email
    end

    test "redirects instead of crashing when the template is no longer visible on mount", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Archived Before Mount"})
      archive_template(template)

      assert {:error, {:live_redirect, %{to: "/templates", flash: flash}}} = live(conn, ~p"/templates/#{template.id}")
      assert flash["error"] =~ "Template not found"
    end

    test "redirects instead of crashing when a PubSub refresh cannot refetch the template", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Archived After Mount"})

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      archive_template(template)
      send(view.pid, {:project_template_publication_updated, %{}})

      flash = assert_redirect(view, ~p"/templates")
      assert flash["error"] =~ "Template not found"
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

  defp archive_template(template) do
    Repo.update_all(from(t in ProjectTemplate, where: t.id == ^template.id), set: [status: "archived"])
  end

  defp version_count(template_id) do
    Repo.aggregate(from(v in ProjectTemplateVersion, where: v.project_template_id == ^template_id), :count)
  end

  defp template_publication_count(template_id) do
    Repo.aggregate(from(p in ProjectTemplatePublication, where: p.project_template_id == ^template_id), :count)
  end

  defp insert_template_versions_to_limit(template, project, user) do
    for version_number <- 2..20 do
      %ProjectTemplateVersion{
        project_template_id: template.id,
        source_project_id: project.id,
        published_by_id: user.id
      }
      |> ProjectTemplateVersion.create_changeset(%{
        version_number: version_number,
        snapshot_storage_key: "test/template-#{template.id}/snapshot-#{version_number}.json.gz",
        asset_manifest_storage_key: "test/template-#{template.id}/asset-manifest-#{version_number}.json.gz",
        checksum: String.duplicate("a", 64),
        entity_counts: %{},
        audit_report: %{"status" => "passed"},
        published_at: DateTime.utc_now(:second)
      })
      |> Repo.insert!()
    end
  end
end

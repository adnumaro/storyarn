defmodule StoryarnWeb.TemplateLiveTest do
  use StoryarnWeb.ConnCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectTemplates
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplate
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplateVersion
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

      assert [%{"id" => own_id, "canManage" => true}] = section_templates(view, "private")
      assert own_id == own_template.id
      assert [%{"id" => public_id, "canManage" => false}] = section_templates(view, "public")
      assert public_id == public_template.id
      refute other_private.id in listed_template_ids(view)
    end

    test "archives and restores a private template from the listing", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Archivable Starter"})

      {:ok, view, _html} = live(conn, ~p"/templates")

      assert section_ids(view, "private") == [template.id]
      render_hook(view, "archive_template", %{"id" => to_string(template.id)})

      assert section_ids(view, "private") == []
      assert section_ids(view, "archived") == [template.id]

      render_hook(view, "unarchive_template", %{"id" => to_string(template.id)})

      assert section_ids(view, "private") == [template.id]
      assert section_ids(view, "archived") == []
    end

    test "permanently deletes an archived private template from the listing", %{conn: conn, user: user, scope: scope} do
      template = template_fixture(user, scope, %{name: "Disposable Starter"})
      version = Repo.get!(ProjectTemplateVersion, template.current_version_id)
      storage_keys = [version.snapshot_storage_key, version.asset_manifest_storage_key]
      archive_template(template)

      {:ok, view, _html} = live(conn, ~p"/templates")

      assert section_ids(view, "archived") == [template.id]
      render_hook(view, "prepare_delete_template", %{"id" => to_string(template.id)})

      assert list_props(view)["pending-delete-id"] == template.id

      html = render_hook(view, "delete_template", %{"id" => to_string(template.id)})

      assert section_ids(view, "archived") == []
      assert list_props(view)["pending-delete-id"] == nil
      assert html =~ "Template permanently deleted"
      assert Repo.get(ProjectTemplate, template.id) == nil

      assert_enqueued(
        worker: DeleteProjectTemplateArtifactsWorker,
        args: %{"storage_keys" => storage_keys}
      )
    end

    test "searches through the URL and pages each section on its own", %{conn: conn, user: user, scope: scope} do
      matching = template_fixture(user, scope, %{name: "Harbor Starter"})
      _other = template_fixture(user, scope, %{name: "Forest Starter"})

      {:ok, view, _html} = live(conn, ~p"/templates")

      render_hook(view, "search", %{"search" => %{"q" => "  Harbor "}})

      assert_patch(view, ~p"/templates?q=Harbor")
      assert list_props(view)["query"] == "Harbor"
      assert section_ids(view, "private") == [matching.id]

      render_hook(view, "clear_search", %{})

      assert_patch(view, ~p"/templates")
      assert length(section_ids(view, "private")) == 2
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

      assert %{
               "workspaces" => [%{"id" => workspace_id, "name" => "Install Studio"}],
               "defaults" => %{"versionId" => version_id, "name" => "Installable Template"},
               "activeInstallations" => []
             } = show_props(view)["install"]

      assert workspace_id == to_string(workspace.id)
      assert version_id == to_string(template.current_version_id)

      html =
        render_hook(view, "install", %{
          "install" => %{
            "workspace_id" => workspace_id,
            "version_id" => version_id,
            "name" => "Installed From Template"
          }
        })

      installation = Repo.get_by!(ProjectTemplateInstall, workspace_id: workspace.id, status: "queued")
      assert html =~ "Template installation started"

      assert [%{"id" => active_id, "projectName" => "Installed From Template"}] =
               show_props(view)["install"]["activeInstallations"]

      assert active_id == installation.id

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

      assert installation_failure(view) == nil
    end

    test "rehydrates failure feedback on mount and stale events cannot restore it after dismissal", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Stale Failure Template"})
      workspace = workspace_fixture(user, %{name: "Stale Failure Workspace"})

      failed_installation =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Stale Failure Copy"
        )

      Repo.update_all(
        from(install in ProjectTemplateInstall, where: install.id == ^failed_installation.id),
        set: [
          error_code: "checksum_mismatch",
          error_message: "The template failed its integrity check."
        ]
      )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert installation_failure(view) == %{"id" => failed_installation.id, "errorCode" => "checksum_mismatch"}

      dismiss_failure(view, failed_installation.id)

      assert installation_failure(view) == nil
      assert Repo.get!(ProjectTemplateInstall, failed_installation.id).feedback_dismissed_at

      send(
        view.pid,
        {:project_template_installation_updated, failed_installation}
      )

      assert installation_failure(view) == nil
    end

    test "names a failure by its code and never sends the stored message", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Localized Failure Template"})
      workspace = workspace_fixture(user, %{name: "Localized Failure Workspace"})

      failed_installation =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Localized Failure Copy"
        )

      Repo.update_all(
        from(install in ProjectTemplateInstall, where: install.id == ^failed_installation.id),
        set: [
          error_code: "checksum_mismatch",
          error_message: "The template failed its integrity check."
        ]
      )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert installation_failure(view) == %{"id" => failed_installation.id, "errorCode" => "checksum_mismatch"}
      refute render(view) =~ "The template failed its integrity check."
    end

    test "queues concurrent failures and advances after dismissing the newest", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Queued Failure Template"})
      workspace = workspace_fixture(user, %{name: "Queued Failure Workspace"})

      first_failure =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "First Failed Copy"
        )

      second_failure =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Second Failed Copy"
        )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert failure_id(view) == second_failure.id

      dismiss_failure(view, second_failure.id)

      assert Repo.get!(ProjectTemplateInstall, second_failure.id).feedback_dismissed_at
      assert failure_id(view) == first_failure.id

      send(view.pid, {:project_template_installation_updated, second_failure})

      assert failure_id(view) == first_failure.id
    end

    test "does not expose an internal stored installation error", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Internal Failure Template"})
      workspace = workspace_fixture(user, %{name: "Internal Failure Workspace"})

      failed_installation =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Internal Failed Copy"
        )

      internal_error = "{:materialization_failed, #Ecto.Changeset<errors: [secret: \"token\"]>}"

      Repo.update_all(
        from(install in ProjectTemplateInstall, where: install.id == ^failed_installation.id),
        set: [error_code: "materialization_failed", error_message: internal_error]
      )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert installation_failure(view) == %{"id" => failed_installation.id, "errorCode" => "materialization_failed"}
      refute render(view) =~ "materialization_failed, #Ecto.Changeset"
      refute render(view) =~ "token"
    end

    test "does not let failures from inaccessible workspaces block the queue", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Authorized Failure Template"})
      workspace_owner = user_fixture()
      inaccessible_workspace = workspace_fixture(workspace_owner, %{name: "Former Workspace"})
      membership = workspace_membership_fixture(inaccessible_workspace, user, "member")

      inaccessible_failure =
        failed_installation_fixture(
          template,
          user,
          inaccessible_workspace,
          "Inaccessible Failed Copy"
        )

      Repo.delete!(membership)

      accessible_workspace = workspace_fixture(user, %{name: "Current Workspace"})

      accessible_failure =
        failed_installation_fixture(
          template,
          user,
          accessible_workspace,
          "Accessible Failed Copy"
        )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert failure_id(view) == accessible_failure.id
      refute failure_id(view) == inaccessible_failure.id
    end

    test "advances the queue when workspace access is revoked while feedback is open", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Revoked Failure Template"})
      workspace_owner = user_fixture()
      revoked_workspace = workspace_fixture(workspace_owner, %{name: "Soon Revoked Workspace"})
      membership = workspace_membership_fixture(revoked_workspace, user, "member")

      accessible_workspace = workspace_fixture(user, %{name: "Still Accessible Workspace"})

      accessible_failure =
        failed_installation_fixture(
          template,
          user,
          accessible_workspace,
          "Still Accessible Failed Copy"
        )

      revoked_failure =
        failed_installation_fixture(
          template,
          user,
          revoked_workspace,
          "Revoked Failed Copy"
        )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")
      assert failure_id(view) == revoked_failure.id

      Repo.delete!(membership)
      dismiss_failure(view, revoked_failure.id)

      refute Repo.get!(ProjectTemplateInstall, revoked_failure.id).feedback_dismissed_at
      assert failure_id(view) == accessible_failure.id
    end

    test "dismiss feedback only clears the matching installation failure", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Concurrent Failure Template"})
      workspace = workspace_fixture(user, %{name: "Concurrent Failure Workspace"})

      other_failure =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Other Failure Copy"
        )

      visible_failure =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Visible Failure Copy"
        )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      send(
        view.pid,
        {:project_template_installation_updated, visible_failure}
      )

      assert failure_id(view) == visible_failure.id

      assert {:ok, _dismissed} =
               ProjectTemplates.dismiss_installation_failure(
                 scope,
                 workspace,
                 other_failure.id
               )

      assert failure_id(view) == visible_failure.id
    end

    test "dismissing a failure does not clear a newer unrelated error", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Preserved Error Template"})
      workspace = workspace_fixture(user, %{name: "Preserved Error Workspace"})

      failed_installation =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Preserved Error Copy"
        )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      send(
        view.pid,
        {:project_template_installation_updated, failed_installation}
      )

      assert failure_id(view) == failed_installation.id

      html =
        render_hook(view, "install", %{
          "install" => %{
            "workspace_id" => "not-an-id",
            "version_id" => to_string(template.current_version_id),
            "name" => "Invalid installation"
          }
        })

      assert html =~ "Template could not be installed."

      assert {:ok, _dismissed} =
               ProjectTemplates.dismiss_installation_failure(
                 scope,
                 workspace,
                 failed_installation.id
               )

      assert render(view) =~ "Template could not be installed."
    end

    test "does not show a stale failure event when the database already records its dismissal", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      template = template_fixture(user, scope, %{name: "Persisted Dismissal Template"})
      workspace = workspace_fixture(user, %{name: "Persisted Dismissal Workspace"})

      stale_failure =
        failed_installation_fixture(
          template,
          user,
          workspace,
          "Persisted Dismissal Copy"
        )

      Repo.update_all(
        from(install in ProjectTemplateInstall, where: install.id == ^stale_failure.id),
        set: [feedback_dismissed_at: DateTime.utc_now(:second)]
      )

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      send(
        view.pid,
        {:project_template_installation_updated, stale_failure}
      )

      assert installation_failure(view) == nil
    end

    test "installs a selected older template version", %{conn: conn, user: user, scope: scope} do
      workspace = workspace_fixture(user, %{name: "Version Install Studio"})
      template = template_fixture(user, scope, %{name: "Versioned Install Template"})
      first_version_id = template.current_version_id

      {:ok, template} = ProjectTemplates.publish_new_version(scope, template, template.source_project)

      {:ok, view, _html} = live(conn, ~p"/templates/#{template.id}")

      assert [%{"id" => newest_id, "isCurrent" => true}, %{"id" => ^first_version_id, "isCurrent" => false}] =
               show_props(view)["versions"]

      assert newest_id == template.current_version_id

      render_hook(view, "install", %{
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

      assert show_props(view)["template"]["canPublish"]
      refute show_props(view)["has-active-publication"]

      html =
        render_hook(view, "publish_new_version", %{
          "publication" => %{"version_notes" => "LiveView version notes"}
        })

      assert html =~ "Template publication queued"

      publication = Repo.get_by!(ProjectTemplatePublication, project_template_id: template.id, status: "queued")
      template = Repo.get!(ProjectTemplate, template.id)

      assert publication.status == "queued"
      assert publication.version_notes == "LiveView version notes"
      assert template.current_version_id == first_version_id
      assert version_count(template.id) == 1
      assert show_props(view)["has-active-publication"]
      assert publication.id in Enum.map(show_props(view)["publications"], & &1["id"])

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

      assert show_props(view)["template"]["canPublish"]

      html =
        render_hook(view, "publish_new_version", %{
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

      refute show_props(view)["template"]["canPublish"]
      assert show_props(view)["publications"] == []
      assert show_props(view)["installs"] == []
      assert Enum.all?(show_props(view)["versions"], &is_nil(&1["publishedByEmail"]))
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

  defp failed_installation_fixture(template, user, workspace, project_name) do
    %ProjectTemplateInstall{
      project_template_version_id: template.current_version_id,
      user_id: user.id,
      workspace_id: workspace.id,
      status: "failed",
      stage: "failed",
      project_name: project_name,
      source: "template_show",
      error_code: "test_failure",
      error_message: "Test failure",
      completed_at: DateTime.utc_now(:second)
    }
    |> Repo.insert!()
    |> Repo.preload([:workspace, project_template_version: [:project_template]])
  end

  defp list_props(view), do: LiveVue.Test.get_vue(view, name: "live/template/list/TemplateList").props

  defp section_templates(view, key) do
    view
    |> list_props()
    |> Map.fetch!("sections")
    |> Enum.find(&(&1["key"] == key))
    |> Map.fetch!("templates")
  end

  defp section_ids(view, key), do: view |> section_templates(key) |> Enum.map(& &1["id"])

  defp listed_template_ids(view), do: Enum.flat_map(~w(private public archived), &section_ids(view, &1))

  defp show_props(view), do: LiveVue.Test.get_vue(view, name: "live/template/show/TemplateShow").props

  defp installation_failure(view), do: show_props(view)["installation-failure"]

  defp failure_id(view), do: view |> installation_failure() |> Map.fetch!("id")

  defp dismiss_failure(view, installation_id) do
    render_hook(view, "dismiss_template_installation_failure", %{"installation_id" => to_string(installation_id)})
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
    ProjectTemplates.get_template!(user_scope_fixture(Storyarn.Accounts.get_user!(template.owner.id)), template.id)
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

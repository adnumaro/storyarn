defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.VersioningFixtures
  import Storyarn.WorkspacesFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Localization
  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Repo
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker
  alias Storyarn.Workspaces.Workspace
  alias StoryarnWeb.ProjectSettingsLive.Snapshots, as: SnapshotsLive

  @outside_pg_bigint 9_223_372_036_854_775_808

  defp settings_path(project, section \\ nil) do
    base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings"
    if section, do: "#{base}/#{section}", else: base
  end

  defp get_general_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsGeneral")
  end

  defp get_usage_limits_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsUsageLimits")
  end

  defp get_snapshots_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsSnapshots")
  end

  defp get_version_control_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsVersionControl")
  end

  defp get_settings_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  defp connected_project_settings_socket(user, project, membership) do
    %Socket{
      endpoint: StoryarnWeb.Endpoint,
      router: StoryarnWeb.Router,
      root_pid: self(),
      transport_pid: self(),
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: user_scope_fixture(user),
        project: project,
        membership: membership,
        workspace: project.workspace
      }
    }
  end

  for {section, live_view} <- [
        localization: StoryarnWeb.ProjectSettingsLive.Localization,
        members: StoryarnWeb.ProjectSettingsLive.Members,
        usage_limits: StoryarnWeb.ProjectSettingsLive.UsageLimits,
        version_control: StoryarnWeb.ProjectSettingsLive.VersionControl
      ] do
    test "#{section} mount reloads ownership and subscribes even when access is already lost" do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      stale_membership = Projects.get_membership(project.id, owner.id)
      fresh_name = "Fresh mount #{unquote(section)}"

      project
      |> Ecto.Changeset.change(name: fresh_name)
      |> Repo.update!()

      socket = connected_project_settings_socket(owner, project, stale_membership)
      assert {:ok, mounted_socket} = unquote(live_view).mount(%{}, %{}, socket)
      assert mounted_socket.assigns.project.name == fresh_name
      assert mounted_socket.assigns.membership.id == stale_membership.id

      ownership_topic = "projects:#{project.id}:ownership"
      :ok = Phoenix.PubSub.unsubscribe(Storyarn.PubSub, ownership_topic)

      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      assert {:ok, _transferred_project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      assert {:ok, denied_socket} =
               unquote(live_view).mount(
                 %{},
                 %{},
                 connected_project_settings_socket(owner, project, stale_membership)
               )

      assert {:redirect, %{to: path}} = denied_socket.redirected

      assert path ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"

      probe = {:ownership_subscription_probe, project.id, unquote(section)}
      :ok = Phoenix.PubSub.broadcast(Storyarn.PubSub, ownership_topic, probe)
      assert_receive ^probe
    end
  end

  describe "open owner-only settings after an ownership transfer" do
    setup :register_and_log_in_user

    for section <- ["localization", "usage-limits", "version-control"] do
      test "#{section} redirects the former owner when ownership changes", %{
        conn: conn,
        user: owner
      } do
        project = owner |> project_fixture() |> Repo.preload(:workspace)
        receiver = user_fixture()
        _receiver_membership = membership_fixture(project, receiver, "editor")

        {:ok, view, _html} = live(conn, settings_path(project, unquote(section)))

        assert {:ok, _project} =
                 Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

        assert_redirect(
          view,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
        )
      end
    end
  end

  describe "General section" do
    setup :register_and_log_in_user

    test "renders general settings Vue component", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "My Project"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      vue = get_general_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsGeneral"
      assert vue.props["project-details"]["name"] == "My Project"
      assert vue.props["project-details"]["type"] == "game"
      assert vue.props["project-details"]["subtype"] == "rpg"
      assert vue.props["project-metrics-options"]["project_types"] == ["game", "film", "novel", "other"]
      assert vue.props["can-manage-project"] == true

      assert vue.props["source-language"] == %{
               "flagCode" => "gb",
               "label" => "English",
               "languageTag" => "en",
               "localeCode" => "en",
               "shortLabel" => "EN",
               "value" => "en"
             }

      assert %{
               "flagCode" => "us",
               "label" => "English (US)",
               "languageTag" => "en-US",
               "shortLabel" => "EN",
               "value" => "en-us"
             } in vue.props["source-language-options"]
    end

    test "keeps template publishing available but removes owner controls after a transfer", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      {:ok, view, _html} = live(conn, settings_path(project))
      assert get_general_vue(view).props["can-manage-project"] == true

      assert {:ok, _transferred_project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      refute_redirected(view)
      assert get_general_vue(view).props["can-manage-project"] == false
      assert Repo.reload!(project).owner_id == receiver.id
    end

    test "enables owner controls in an already open general tab for the new owner", %{
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture()
      _workspace_admin = workspace_membership_fixture(project.workspace, receiver, "admin")
      _receiver_membership = membership_fixture(project, receiver, "editor")

      {:ok, receiver_view, _html} =
        build_conn()
        |> log_in_user(receiver)
        |> live(settings_path(project))

      assert get_general_vue(receiver_view).props["can-manage-project"] == false

      assert {:ok, _transferred_project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      refute_redirected(receiver_view)
      assert get_general_vue(receiver_view).props["can-manage-project"] == true
      assert Repo.reload!(project).owner_id == receiver.id
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, settings_path(project))

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end

    test "updates project details via update_project event", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Old Name"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "update_project", %{"project" => %{"name" => "New Name"}})

      assert html =~ "updated successfully"

      vue = get_general_vue(view)
      assert vue.props["project-details"]["name"] == "New Name"
    end

    test "explains ownership drift and preserves project details", %{conn: conn, user: owner} do
      project = owner |> project_fixture(%{name: "Stable Name"}) |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project))

      conflicting_owner = user_fixture()
      _conflicting_membership = membership_fixture(project, conflicting_owner, "owner")

      html =
        render_click(view, "update_project", %{
          "project" => %{"name" => "Must Not Persist"}
        })

      assert html =~ "project ownership is inconsistent"
      assert Repo.reload!(project).name == "Stable Name"
    end

    test "survives replacement invalidations and reloads project fields after a snapshot restore", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture(%{name: "Before restore"}) |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project))

      restored_settings = %{
        "theme" => %{"primary" => "#123456", "accent" => "#654321"}
      }

      project
      |> Project.update_changeset(%{name: "After restore", settings: restored_settings})
      |> Repo.update!()

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:entities_deleted, :sheet, [123]}
      )

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:project_restored, 42}
      )

      _html = render(view)
      vue = get_general_vue(view)
      assert vue.props["project-details"]["name"] == "After restore"
      assert vue.props["theme-primary"] == "#123456"
      assert vue.props["theme-accent"] == "#654321"
    end

    test "ignores collaborator sidebar messages on the shared shell topic", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Stable project"}) |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project))

      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        "project:#{project.id}:shell",
        {:tree_changed, :sheets}
      )

      _html = render(view)
      assert get_general_vue(view).props["project-details"]["name"] == "Stable project"
    end

    test "updates project type metadata via update_project event", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Typed Project"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "update_project", %{
          "project" => %{
            "name" => "Typed Project",
            "description" => project.description || "",
            "project_type" => "film",
            "project_subtype" => "short_film",
            "project_type_other" => ""
          }
        })

      assert html =~ "updated successfully"

      project = Repo.get!(Project, project.id)
      assert project.project_type == "film"
      assert project.project_subtype == "short_film"

      vue = get_general_vue(view)
      assert vue.props["project-details"]["type"] == "film"
      assert vue.props["project-details"]["subtype"] == "short_film"
    end

    test "updates the project source language via change_source_language event", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      recipient = user_fixture()
      membership_fixture(project, recipient, "viewer")
      recipient_scope = user_scope_fixture(recipient)
      actor_scope = user_scope_fixture(user)
      :ok = Notifications.subscribe(recipient_scope)

      {:ok, view, _html} = live(conn, settings_path(project))

      html = render_click(view, "change_source_language", %{"locale_code" => "es-419"})

      assert html =~ "Source language updated."

      vue = get_general_vue(view)
      assert vue.props["source-language"]["localeCode"] == "es-419"

      source_language = Localization.get_source_language(project.id)
      assert source_language.locale_code == "es-419"

      assert_receive :notifications_changed
      assert [notification] = Notifications.list_notifications(recipient_scope)
      assert notification.actor_id == user.id
      assert notification.entity_type == "localization_language"
      assert notification.entity_id == source_language.id
      assert notification.kind == "content_created"
      assert Notifications.list_notifications(actor_scope) == []

      previous_source = Localization.get_language_by_locale(project.id, "en")
      refute previous_source.is_source
      assert previous_source.archived_at == nil
    end

    test "resets translations only after explicit confirmation when changing source language", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "change_source_language", %{
          "locale_code" => "es",
          "reset_translations" => true
        })

      assert html =~ "Source language updated."
      assert Localization.get_source_language(project.id).locale_code == "es"
      assert Localization.get_text(project.id, text.id) == nil
    end

    test "does not coerce arbitrary reset values when changing source language", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "change_source_language", %{
          "locale_code" => "es",
          "reset_translations" => "yes"
        })

      assert html =~ "Could not update the source language."
      assert Localization.get_source_language(project.id).locale_code == "en"
      assert Localization.get_text(project.id, text.id)
    end

    test "deletes project via delete_project event", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      render_click(view, "delete_project")

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces/#{project.workspace.slug}"
      assert flash["info"] =~ "deleted"
    end
  end

  describe "Members section" do
    setup :register_and_log_in_user

    test "passes members list to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      member = user_fixture(%{email: "member@example.com"})
      _membership = membership_fixture(project, member, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert vue.component == "live/project/settings/ProjectSettingsMembers"
      members = vue.props["members"]
      assert vue.props["current-user-id"] == Integer.to_string(user.id)
      assert Enum.any?(members, fn m -> m["email"] == user.email end)
      assert Enum.any?(members, fn m -> m["email"] == "member@example.com" end)

      assert Enum.find(members, &(&1["email"] == "member@example.com"))["user_id"] ==
               Integer.to_string(member.id)

      assert vue.props["can-transfer-ownership"] == true
    end

    test "sends an invitation directly to the project member", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      html =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "newmember@example.com", "role" => "editor"}
        })

      assert html =~ "Invitation queued for delivery"
      assert_push_event(view, "invitation_sent", %{})

      assert [invitation] = Projects.list_pending_invitations(project.id)
      assert invitation.email == "newmember@example.com"
      assert invitation.invited_by_id == user.id

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")

      assert [%{"id" => invitation_id, "email" => "newmember@example.com"}] =
               vue.props["pending-invitations"]

      assert invitation_id == invitation.id
    end

    test "shows the plan limit after the remaining project seat is reserved", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "first@example.com", "role" => "editor"}
      })

      html =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "second@example.com", "role" => "viewer"}
        })

      assert html =~ "Member limit reached for your plan"

      assert Enum.map(Projects.list_pending_invitations(project.id), & &1.email) == [
               "first@example.com"
             ]
    end

    test "revokes a pending project invitation and releases its seat", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "revoke-project@example.com", "role" => "editor"}
      })

      [invitation] = Projects.list_pending_invitations(project.id)

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})

      assert result =~ "Invitation revoked"
      assert Projects.list_pending_invitations(project.id) == []

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert vue.props["pending-invitations"] == []
    end

    test "does not revoke an invitation from another project", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = user |> project_fixture(%{workspace: workspace}) |> Repo.preload(:workspace)
      other_project = project_fixture(user, %{workspace: workspace})

      assert {:ok, other_invitation} =
               Projects.create_invitation(
                 user_scope_fixture(user),
                 other_project.id,
                 "other-project@example.com",
                 "editor"
               )

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(other_invitation.id)})

      assert result =~ "Invitation not found"
      assert [%{id: invitation_id}] = Projects.list_pending_invitations(other_project.id)
      assert invitation_id == other_invitation.id
    end

    test "a members socket cannot invite after the project is deleted", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "deleted-project@example.com", "role" => "editor"}
      })

      assert [invitation] = Projects.list_pending_invitations(project.id)

      assert {:ok, _deleted_project} =
               Projects.delete_project(user_scope_fixture(user), project.id)

      refute Repo.get(ProjectInvitation, invitation.id)

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "after-delete@example.com", "role" => "editor"}
      })

      flash = assert_redirect(view, ~p"/workspaces/#{project.workspace.slug}")
      assert flash["error"] == "Project not found."
      assert Projects.list_pending_invitations(project.id) == []
    end

    test "removes member via remove_member event", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      member = user_fixture(%{email: "removeme@example.com"})
      membership = membership_fixture(project, member, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)

      render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      refute Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)
    end

    test "explains ownership drift and preserves the member when removal fails closed", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      member = user_fixture()
      membership = membership_fixture(project, member, "editor")
      conflicting_owner = user_fixture()
      _conflicting_membership = membership_fixture(project, conflicting_owner, "owner")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      result = render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      assert result =~ "could not be removed because project ownership is inconsistent"
      assert Repo.reload!(membership).role == "editor"
    end

    test "rejects oversized and structured member-management ids", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      assert render_click(view, "remove_member", %{
               "id" => Integer.to_string(@outside_pg_bigint)
             }) =~ "Member not found."

      assert render_click(view, "remove_member", %{"id" => %{"unexpected" => true}}) =~
               "Member not found."

      assert render_click(view, "revoke_invitation", %{
               "id" => Integer.to_string(@outside_pg_bigint)
             }) =~ "Invitation not found."

      assert render_click(view, "revoke_invitation", %{"id" => []}) =~
               "Invitation not found."
    end

    test "transfers ownership and sends the former owner out of project settings", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture(%{email: "new-owner@example.com"})
      receiver_membership = membership_fixture(project, receiver, "viewer")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "transfer_owner", %{"user-id" => to_string(receiver.id)})

      assert_redirect(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      )

      assert Repo.reload!(project).owner_id == receiver.id
      assert Projects.get_membership(project.id, owner.id).role == "editor"
      assert Repo.reload!(receiver_membership).role == "owner"
      assert Repo.get!(Workspace, project.workspace_id).owner_id == owner.id
    end

    test "rejects an ownership target outside PostgreSQL bigint range", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      result =
        render_click(view, "transfer_owner", %{
          "user-id" => Integer.to_string(@outside_pg_bigint)
        })

      assert result =~ "Project ownership could not be transferred."

      assert render_click(view, "transfer_owner", %{
               "user-id" => %{"unexpected" => true}
             }) =~ "Project ownership could not be transferred."

      assert render_click(view, "transfer_owner", %{}) =~
               "Project ownership could not be transferred."

      refute_redirected(view)
      assert Repo.reload!(project).owner_id == owner.id
    end

    test "a stale members tab redirects after ownership is transferred elsewhere", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      assert {:ok, _project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      assert_redirect(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      )

      assert Projects.get_membership(project.id, owner.id).role == "editor"
    end

    test "a stale members tab cannot transfer ownership after losing authority without receiving PubSub", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture()
      receiver_membership = membership_fixture(project, receiver, "editor")
      third_member = user_fixture()
      _third_membership = membership_fixture(project, third_member, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      assert {:ok, :ownership_changed_without_broadcast} =
               Repo.transact(fn ->
                 project
                 |> Ecto.Changeset.change(owner_id: receiver.id)
                 |> Repo.update!()

                 project.id
                 |> Projects.get_membership(owner.id)
                 |> Ecto.Changeset.change(role: "editor")
                 |> Repo.update!()

                 receiver_membership
                 |> Ecto.Changeset.change(role: "owner")
                 |> Repo.update!()

                 {:ok, :ownership_changed_without_broadcast}
               end)

      render_click(view, "transfer_owner", %{"user-id" => to_string(third_member.id)})

      {path, flash} = assert_redirect(view)
      assert path == ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] == "You don't have permission to manage this project."

      assert Repo.reload!(project).owner_id == receiver.id
      assert Repo.reload!(receiver_membership).role == "owner"
      assert Projects.get_membership(project.id, third_member.id).role == "editor"
    end

    test "rejects a workspace-inherited target without a direct project membership", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      inherited_member = user_fixture()

      _workspace_membership =
        workspace_membership_fixture(project.workspace, inherited_member, "member")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      result =
        render_click(view, "transfer_owner", %{
          "user-id" => to_string(inherited_member.id)
        })

      assert result =~ "no longer a direct project member"
      assert Repo.reload!(project).owner_id == owner.id
    end
  end

  describe "Snapshots section" do
    setup :register_and_log_in_user

    test "stale owner assigns cannot start snapshot reads or refresh timers", %{user: owner} do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      stale_membership = Projects.get_membership(project.id, owner.id)
      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      assert {:ok, _project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: user_scope_fixture(owner),
          project: project,
          membership: stale_membership
        }
      }

      assert {:ok, redirected_socket} = SnapshotsLive.mount(%{}, %{}, socket)

      assert redirected_socket.redirected ==
               {:redirect, %{to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}", status: 302}}

      refute Map.has_key?(redirected_socket.assigns, :snapshots)
      refute Map.has_key?(redirected_socket.assigns, :snapshot_restores)
      refute Map.has_key?(redirected_socket.assigns, :snapshot_build_statuses)
      refute Map.has_key?(redirected_socket.assigns, :snapshot_build_status_timer)
      refute Map.has_key?(redirected_socket.assigns, :snapshot_access_active)
    end

    test "ownership drift fails every snapshot mutation with its existing client contract", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      snapshot = full_project_snapshot_fixture(project)
      snapshot_id = snapshot.id
      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      conflicting_owner = user_fixture()
      _conflicting_membership = membership_fixture(project, conflicting_owner, "owner")

      render_click(view, "create_snapshot", %{"idempotency_key" => "ownership-drift-create"})

      assert_push_event(view, "snapshot_request_failed", %{
        reason: "ownership_invariant_violation",
        requiredBytes: nil,
        availableBytes: nil,
        used: nil,
        limit: nil
      })

      render_click(view, "cancel_snapshot", %{"id" => snapshot_id})

      assert_push_event(view, "snapshot_cancel_failed", %{
        snapshotId: ^snapshot_id,
        reason: "ownership_invariant_violation",
        message:
          "The snapshot action could not be completed because project ownership is inconsistent. Contact support before retrying."
      })

      render_click(view, "delete_snapshot", %{"id" => snapshot_id})

      assert_push_event(view, "snapshot_delete_failed", %{
        snapshotId: ^snapshot_id,
        reason: "ownership_invariant_violation",
        message:
          "The snapshot action could not be completed because project ownership is inconsistent. Contact support before retrying."
      })

      html =
        render_click(view, "restore_snapshot", %{
          "id" => snapshot_id,
          "idempotency_key" => "ownership-drift-restore"
        })

      assert_push_event(view, "snapshot_restore_failed", %{
        snapshotId: ^snapshot_id,
        reason: "ownership_invariant_violation"
      })

      assert html =~ "project ownership is inconsistent"
      assert Versioning.list_project_snapshot_restores(project.id) == []
    end

    test "passively revokes an open snapshot tab and stops all later refreshes", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      pending = pending_project_snapshot_fixture(project, %{title: "Visible before transfer"})
      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      state_before = :sys.get_state(view.pid)
      assert state_before.socket.assigns.snapshot_access_active
      timer = state_before.socket.assigns.snapshot_build_status_timer
      assert is_reference(timer)

      assert {:ok, _project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      assert_redirect(
        view,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      )

      refute Process.alive?(view.pid)
      assert Process.read_timer(timer) == false
      assert Repo.reload!(pending).title == "Visible before transfer"
    end

    test "a snapshot update arriving before the ownership event revokes access without crashing", %{
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      pending = pending_project_snapshot_fixture(project, %{title: "Race-safe snapshot"})
      membership = Projects.get_membership(project.id, owner.id)
      receiver = user_fixture()
      _receiver_membership = membership_fixture(project, receiver, "editor")

      assert {:ok, mounted_socket} =
               SnapshotsLive.mount(
                 %{},
                 %{},
                 connected_project_settings_socket(owner, project, membership)
               )

      timer = mounted_socket.assigns.snapshot_build_status_timer
      assert is_reference(timer)

      assert {:ok, _project} =
               Projects.transfer_owner(user_scope_fixture(owner), project.id, receiver.id)

      assert {:noreply, revoked_socket} =
               SnapshotsLive.handle_info(
                 {:project_snapshot_updated, pending.id},
                 mounted_socket
               )

      refute revoked_socket.assigns.snapshot_access_active
      assert revoked_socket.assigns.snapshot_build_status_timer == nil
      assert revoked_socket.redirected
      assert Process.read_timer(timer) == false
    end

    test "passes canonical accounting measurements and workspace categories to Vue", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _asset = asset_fixture(project, user, %{size: 2_048})
      token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      prefix = "projects/#{project.id}/snapshots/archives/v2/ready/#{token}"

      snapshot =
        full_project_snapshot_fixture(project, %{
          title: "Measured checkpoint",
          project_size_bytes: 100,
          project_checksum: String.duplicate("a", 64),
          format_version: 2,
          object_prefix: prefix,
          archive_storage_key: prefix <> "/snapshot.zip",
          archive_size_bytes: 150,
          archive_checksum: String.duplicate("c", 64),
          manifest_storage_key: prefix <> "/manifest.json",
          manifest_size_bytes: 25,
          manifest_checksum: String.duplicate("b", 64),
          total_size_bytes: 175,
          accounted_size_bytes: 175,
          object_count: 2,
          asset_count: 2,
          blob_count: 1,
          asset_blob_size_bytes: 50,
          progress_bytes: 175,
          progress_total_bytes: 175
        })

      assert {:ok, _reservation} =
               Billing.reserve_storage(%{
                 workspace_id: project.workspace_id,
                 project_id: project.id,
                 project_snapshot_id: snapshot.id,
                 idempotency_key: "settings-export:#{snapshot.id}",
                 kind: "snapshot_export",
                 reserved_bytes: 60
               })

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))
      vue = get_snapshots_vue(view)

      assert vue.props |> Map.keys() |> Enum.sort() == [
               "restore-operation-active",
               "snapshot-limit",
               "snapshots",
               "storage-usage"
             ]

      assert vue.props["restore-operation-active"] == false
      assert vue.props["snapshot-limit"] == %{"used" => 1, "limit" => 10}

      assert [serialized] = vue.props["snapshots"]

      assert Map.take(serialized, [
               "mode",
               "lifecycleStatus",
               "integrityStatus",
               "accountedSizeBytes",
               "archiveSizeBytes",
               "sidecarSizeBytes",
               "assetCount",
               "blobCount",
               "activeReservationBytes",
               "exportReservationBytes",
               "accountingVersion",
               "deleteStatus",
               "canRestore",
               "restoreOperation"
             ]) == %{
               "mode" => "full",
               "lifecycleStatus" => "ready",
               "integrityStatus" => "verified",
               "accountedSizeBytes" => "175",
               "archiveSizeBytes" => "150",
               "sidecarSizeBytes" => "25",
               "assetCount" => 2,
               "blobCount" => 1,
               "activeReservationBytes" => "0",
               "exportReservationBytes" => "60",
               "accountingVersion" => 1,
               "deleteStatus" => "active_operation",
               "canRestore" => true,
               "restoreOperation" => nil
             }

      assert is_binary(serialized["accountingMeasuredAt"])

      assert serialized["downloadUrl"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot.id}/download"

      assert vue.props["storage-usage"] == %{
               "currentAssetsBytes" => "2048",
               "assetTrashBytes" => "0",
               "fullSnapshotsBytes" => "175",
               "activeReservationsBytes" => "60",
               "totalAccountedBytes" => "2283",
               "limitBytes" => "262144000",
               "remainingBytes" => "262141717",
               "limitKind" => "limited"
             }
    end

    test "serializes bigint accounting measurements as exact decimal strings", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      prefix = "projects/#{project.id}/snapshots/archives/v2/ready/#{token}"
      archive_bytes = 9_007_199_254_740_993
      total_bytes = archive_bytes + 25

      full_project_snapshot_fixture(project, %{
        title: "Large measured checkpoint",
        project_size_bytes: 100,
        project_checksum: String.duplicate("a", 64),
        format_version: 2,
        object_prefix: prefix,
        archive_storage_key: prefix <> "/snapshot.zip",
        archive_size_bytes: archive_bytes,
        archive_checksum: String.duplicate("c", 64),
        manifest_storage_key: prefix <> "/manifest.json",
        manifest_size_bytes: 25,
        manifest_checksum: String.duplicate("b", 64),
        total_size_bytes: total_bytes,
        accounted_size_bytes: total_bytes,
        asset_blob_size_bytes: 0,
        object_count: 2,
        asset_count: 1,
        blob_count: 1,
        progress_bytes: total_bytes,
        progress_total_bytes: total_bytes
      })

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))
      vue = get_snapshots_vue(view)

      assert [serialized] = vue.props["snapshots"]
      assert serialized["archiveSizeBytes"] == "9007199254740993"
      assert serialized["accountedSizeBytes"] == "9007199254741018"
      assert vue.props["storage-usage"]["totalAccountedBytes"] == "9007199254741018"
    end

    test "exposes the internal download route only for a verified v2 archive", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      prefix = "projects/#{project.id}/snapshots/archives/v2/ready/#{String.duplicate("A", 16)}"

      snapshot =
        full_project_snapshot_fixture(project, %{
          format_version: 2,
          object_prefix: prefix,
          archive_storage_key: prefix <> "/snapshot.zip",
          archive_size_bytes: 125,
          archive_checksum: String.duplicate("c", 64),
          manifest_storage_key: prefix <> "/manifest.json",
          manifest_size_bytes: 25,
          total_size_bytes: 150,
          accounted_size_bytes: 150,
          object_count: 2,
          asset_blob_size_bytes: 0,
          asset_count: 0,
          blob_count: 0,
          progress_bytes: 150,
          progress_total_bytes: 150
        })

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))
      assert [serialized] = get_snapshots_vue(view).props["snapshots"]

      assert serialized["archiveSizeBytes"] == "125"
      assert serialized["sidecarSizeBytes"] == "25"
      assert serialized["accountedSizeBytes"] == "150"
      assert serialized["deleteStatus"] == "ready"

      assert serialized["downloadUrl"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot.id}/download"

      refute serialized["downloadUrl"] =~ "X-Amz-"
    end

    test "omits download URLs for unverified snapshots", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      missing =
        project
        |> full_project_snapshot_fixture(%{
          title: "Missing snapshot",
          asset_blob_size_bytes: 0
        })
        |> ProjectSnapshot.reconciliation_integrity_changeset("missing")
        |> Repo.update!()

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      serialized_by_id =
        view
        |> get_snapshots_vue()
        |> then(& &1.props["snapshots"])
        |> Map.new(&{&1["id"], &1})

      assert serialized_by_id[missing.id]["downloadUrl"] == nil
      assert serialized_by_id[missing.id]["canRestore"] == false
    end

    test "requests and cancels a durable full snapshot from the settings surface", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      render_click(view, "create_snapshot", %{
        "mode" => "full",
        "idempotency_key" => Ecto.UUID.generate(),
        "title" => "Before refactor",
        "description" => "Exact boundary"
      })

      vue = get_snapshots_vue(view)
      assert [pending] = vue.props["snapshots"]
      assert pending["mode"] == "full"
      assert pending["lifecycleStatus"] == "pending"
      assert pending["progressPhase"] == "pending"
      assert pending["progressBytes"] == "0"
      assert pending["plannedSizeBytes"] == nil
      assert pending["progressTotalBytes"] == nil
      assert pending["canCancel"] == true
      assert pending["canRestore"] == false
      assert pending["deleteStatus"] == nil
      assert pending["downloadUrl"] == nil

      render_click(view, "cancel_snapshot", %{"id" => pending["id"]})

      vue = get_snapshots_vue(view)
      assert [cancelled] = vue.props["snapshots"]
      assert cancelled["lifecycleStatus"] == "cancelled"
      assert cancelled["canCancel"] == false
      assert is_binary(cancelled["cancelRequestedAt"])
    end

    test "rejects malformed snapshot identifiers without crashing the LiveView", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      render_click(view, "cancel_snapshot", %{"id" => %{"malformed" => true}})
      render_click(view, "delete_snapshot", %{"id" => ["malformed"]})

      render_click(view, "restore_snapshot", %{
        "id" => %{"malformed" => true},
        "idempotency_key" => Ecto.UUID.generate()
      })

      assert_push_event(view, "snapshot_restore_failed", %{
        snapshotId: nil,
        reason: "invalid_request"
      })

      assert get_snapshots_vue(view).props["snapshots"] == []
    end

    test "requests an idempotent durable restore and exposes only public operation state", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      snapshot = full_project_snapshot_fixture(project, %{title: "Restore boundary"})
      snapshot_id = snapshot.id
      idempotency_key = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      assert [ready] = get_snapshots_vue(view).props["snapshots"]
      assert ready["canRestore"] == true
      assert ready["restoreOperation"] == nil

      render_click(view, "restore_snapshot", %{
        "id" => snapshot_id,
        "idempotency_key" => idempotency_key
      })

      assert_push_event(view, "snapshot_restore_accepted", %{
        snapshotId: ^snapshot_id,
        restoreId: restore_id
      })

      restore = Repo.get!(ProjectSnapshotRestore, restore_id)
      assert restore.idempotency_key == idempotency_key
      assert restore.requested_by_id == user.id

      vue = get_snapshots_vue(view)
      assert vue.props["restore-operation-active"] == true
      assert [queued] = vue.props["snapshots"]
      assert queued["canRestore"] == false
      assert queued["canDelete"] == false
      assert queued["deleteStatus"] == "restore_operation"

      assert queued["restoreOperation"] == %{
               "attempt" => 0,
               "completedAt" => nil,
               "failedAt" => nil,
               "failureCode" => nil,
               "failureMessage" => nil,
               "id" => restore.id,
               "phase" => "queued",
               "requestedAt" => DateTime.to_iso8601(restore.requested_at),
               "stateUpdatedAt" => DateTime.to_iso8601(restore.state_updated_at),
               "status" => "queued"
             }

      render_click(view, "delete_snapshot", %{"id" => snapshot_id})

      assert_push_event(view, "snapshot_delete_failed", %{
        snapshotId: ^snapshot_id,
        reason: "restore_operation"
      })

      assert Repo.get(ProjectSnapshot, snapshot_id)

      render_click(view, "restore_snapshot", %{
        "id" => snapshot_id,
        "idempotency_key" => idempotency_key
      })

      assert_push_event(view, "snapshot_restore_accepted", %{
        snapshotId: ^snapshot_id,
        restoreId: ^restore_id
      })

      assert [replayed] = Versioning.list_project_snapshot_restores(project.id)
      assert replayed.id == restore.id

      job =
        restore.oban_job_id
        |> then(&Repo.get!(Oban.Job, &1))
        |> Ecto.Changeset.change(
          state: "executing",
          attempt: 1,
          attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
        )
        |> Repo.update!()

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, restore.generation,
                 job_id: job.id,
                 attempt: job.attempt
               )

      assert {:ok, failed} =
               Versioning.fail_project_snapshot_restore(
                 restore.id,
                 claimed.generation,
                 :project_snapshot_restore_preflight_failed
               )

      vue = get_snapshots_vue(view)
      assert vue.props["restore-operation-active"] == false
      assert [failed_snapshot] = vue.props["snapshots"]
      assert failed_snapshot["canRestore"] == true
      assert failed_snapshot["canDelete"] == true

      public_failure = failed_snapshot["restoreOperation"]
      assert public_failure["status"] == "failed"
      assert public_failure["phase"] == "failed"
      assert public_failure["failureCode"] == failed.failure_code
      assert public_failure["failureMessage"] == failed.failure_message
      refute Map.has_key?(public_failure, "failureDetails")
      refute Map.has_key?(public_failure, "result")
    end

    test "restore requests reauthorize the owner's current database membership", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      snapshot = full_project_snapshot_fixture(project)
      receiver = user_fixture()
      receiver_membership = membership_fixture(project, receiver, "editor")
      owner_membership = Projects.get_membership(project.id, user.id)

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))

      assert {:ok, :ownership_changed_without_broadcast} =
               Repo.transact(fn ->
                 project
                 |> Ecto.Changeset.change(owner_id: receiver.id)
                 |> Repo.update!()

                 owner_membership
                 |> Ecto.Changeset.change(role: "editor")
                 |> Repo.update!()

                 receiver_membership
                 |> Ecto.Changeset.change(role: "owner")
                 |> Repo.update!()

                 {:ok, :ownership_changed_without_broadcast}
               end)

      render_click(view, "restore_snapshot", %{
        "id" => snapshot.id,
        "idempotency_key" => Ecto.UUID.generate()
      })

      assert_push_event(view, "snapshot_restore_failed", %{
        snapshotId: snapshot_id,
        reason: "unauthorized"
      })

      assert snapshot_id == snapshot.id
      assert Versioning.list_project_snapshot_restores(project.id) == []
    end

    test "deletes a ready snapshot through the durable cleanup protocol", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      assert {:ok, requested} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      job =
        requested.build_job_id
        |> then(&Repo.get!(Oban.Job, &1))
        |> Ecto.Changeset.change(
          state: "executing",
          attempt: 1,
          attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
        )
        |> Repo.update!()

      assert :ok = BuildProjectSnapshotWorker.perform(job)

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))
      assert [ready] = get_snapshots_vue(view).props["snapshots"]
      assert ready["canDelete"] == true
      assert ready["deleteStatus"] == "ready"

      render_click(view, "delete_snapshot", %{"id" => ready["id"]})

      assert get_snapshots_vue(view).props["snapshots"] == []

      assert %SnapshotCleanupIntent{reason: "user_delete"} =
               Repo.get_by(SnapshotCleanupIntent,
                 project_snapshot_id_snapshot: ready["id"]
               )
    end

    test "tracks the retained download lease until the reaper releases it", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      token = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      prefix = "projects/#{project.id}/snapshots/archives/v2/ready/#{token}"

      snapshot =
        full_project_snapshot_fixture(project, %{
          format_version: 2,
          object_prefix: prefix,
          archive_storage_key: prefix <> "/snapshot.zip",
          archive_size_bytes: 125,
          archive_checksum: String.duplicate("c", 64),
          manifest_storage_key: prefix <> "/manifest.json",
          manifest_size_bytes: 25,
          total_size_bytes: 150,
          accounted_size_bytes: 150,
          object_count: 2,
          asset_blob_size_bytes: 0,
          asset_count: 0,
          blob_count: 0,
          progress_bytes: 150,
          progress_total_bytes: 150
        })

      {:ok, view, _html} = live(conn, settings_path(project, "snapshots"))
      assert [ready] = get_snapshots_vue(view).props["snapshots"]
      assert ready["canDelete"] == true
      assert ready["deleteStatus"] == "ready"

      assert :grant_issued =
               Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
                 {:keep_lease, :grant_issued}
               end)

      assert [leased] = get_snapshots_vue(view).props["snapshots"]
      assert leased["canDelete"] == false
      assert leased["deleteStatus"] == "download_lease"

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Versioning.delete_project_snapshot(
                 user_scope_fixture(user),
                 project,
                 snapshot.id
               )

      now = TimeHelpers.now()

      StorageReservation
      |> Repo.get_by!(project_snapshot_id_snapshot: snapshot.id, kind: "snapshot_export")
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})

      assert [released] = get_snapshots_vue(view).props["snapshots"]
      assert released["canDelete"] == true
      assert released["deleteStatus"] == "ready"
    end
  end

  describe "Entity auto-versioning settings" do
    setup :register_and_log_in_user

    test "exposes and persists only entity auto-version settings", %{conn: conn, user: user} do
      project =
        user
        |> project_fixture(%{
          auto_version_flows: true,
          auto_version_scenes: true,
          auto_version_sheets: true
        })
        |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "version-control"))
      vue = get_version_control_vue(view)

      assert vue.props["auto-version-flows"] == true
      assert vue.props["auto-version-scenes"] == true
      assert vue.props["auto-version-sheets"] == true

      render_click(view, "save_version_control", %{
        "version_control" => %{
          "auto_version_flows" => "false",
          "auto_version_scenes" => "false",
          "auto_version_sheets" => "false"
        }
      })

      updated = Repo.get!(Project, project.id)
      refute updated.auto_version_flows
      refute updated.auto_version_scenes
      refute updated.auto_version_sheets
    end

    test "explains ownership drift and preserves settings when saving fails closed", %{
      conn: conn,
      user: owner
    } do
      project =
        owner
        |> project_fixture(%{
          auto_version_flows: true,
          auto_version_scenes: true,
          auto_version_sheets: true
        })
        |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "version-control"))

      conflicting_owner = user_fixture()
      _conflicting_membership = membership_fixture(project, conflicting_owner, "owner")

      result =
        render_click(view, "save_version_control", %{
          "version_control" => %{
            "auto_version_flows" => "false",
            "auto_version_scenes" => "false",
            "auto_version_sheets" => "false"
          }
        })

      assert result =~ "could not be saved because project ownership is inconsistent"

      unchanged = Repo.get!(Project, project.id)
      assert unchanged.auto_version_flows
      assert unchanged.auto_version_scenes
      assert unchanged.auto_version_sheets
    end
  end

  describe "Localization provider settings" do
    setup :register_and_log_in_user

    test "ownership drift returns explicit replies without changing provider configuration", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "localization"))

      conflicting_owner = user_fixture()
      _conflicting_membership = membership_fixture(project, conflicting_owner, "owner")

      render_hook(view, "save_provider_config", %{
        "provider" => %{
          "api_key_encrypted" => "must-not-persist",
          "api_endpoint" => "https://api-free.deepl.com"
        }
      })

      save_message = "Provider settings could not be saved because project ownership is inconsistent."
      assert_reply(view, %{ok: false, errors: %{authorization: ^save_message}})
      assert Localization.get_provider_config(project.id) == nil

      render_hook(view, "test_provider_connection", %{})

      connection_message =
        "Provider connection could not be tested because project ownership is inconsistent."

      assert_reply(view, %{ok: false, error: ^connection_message})
      assert Localization.get_provider_config(project.id) == nil
    end

    test "distinguishes lost authority from inconsistent ownership", %{
      conn: conn,
      user: owner
    } do
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      receiver = user_fixture()
      receiver_membership = membership_fixture(project, receiver, "editor")
      owner_membership = Projects.get_membership(project.id, owner.id)
      {:ok, view, _html} = live(conn, settings_path(project, "localization"))

      assert {:ok, :ownership_changed_without_broadcast} =
               Repo.transact(fn ->
                 project
                 |> Ecto.Changeset.change(owner_id: receiver.id)
                 |> Repo.update!()

                 owner_membership
                 |> Ecto.Changeset.change(role: "editor")
                 |> Repo.update!()

                 receiver_membership
                 |> Ecto.Changeset.change(role: "owner")
                 |> Repo.update!()

                 {:ok, :ownership_changed_without_broadcast}
               end)

      render_hook(view, "save_provider_config", %{
        "provider" => %{
          "api_key_encrypted" => "must-not-persist",
          "api_endpoint" => "https://api-free.deepl.com"
        }
      })

      save_message = "You don't have permission to manage provider settings for this project."
      assert_reply(view, %{ok: false, errors: %{authorization: ^save_message}})

      render_hook(view, "test_provider_connection", %{})

      connection_message = "You don't have permission to test this project's provider connection."
      assert_reply(view, %{ok: false, error: ^connection_message})
      assert Localization.get_provider_config(project.id) == nil
    end
  end

  describe "Usage limits section" do
    setup :register_and_log_in_user

    test "passes project and workspace usage limits to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _sheet = sheet_fixture(project)
      flow = flow_fixture(project)
      _node = node_fixture(flow)
      _scene = scene_fixture(project)
      _asset = asset_fixture(project, user, %{size: 2_048})

      {:ok, view, _html} = live(conn, settings_path(project, "usage-limits"))

      layout = get_settings_layout_vue(view)

      assert layout.props["current-path"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/usage-limits"

      vue = get_usage_limits_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsUsageLimits"

      usage = vue.props["usage-limits"]
      assert usage["plan"] == %{"key" => "free", "name" => "Free"}
      assert usage["project"]["items"] == %{"used" => 6, "limit" => 700}

      assert usage["itemBreakdown"] == %{
               "sheets" => 1,
               "flows" => 1,
               "scenes" => 1,
               "flowNodes" => 3
             }

      assert usage["storage"] == %{
               "projectAccountedBytes" => "2048",
               "projectAssetBytes" => "2048",
               "projectSnapshotBytes" => "0",
               "projectReservationBytes" => "0",
               "assetCount" => 1,
               "workspace" => %{
                 "currentAssetsBytes" => "2048",
                 "assetTrashBytes" => "0",
                 "fullSnapshotsBytes" => "0",
                 "activeReservationsBytes" => "0",
                 "totalAccountedBytes" => "2048",
                 "limitBytes" => "262144000",
                 "remainingBytes" => "262141952",
                 "limitKind" => "limited"
               }
             }

      assert usage["workspace"]["storageBytes"] == %{
               "used" => "2048",
               "limit" => "262144000"
             }
    end

    test "shows a pending invitation as an occupied member seat", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      assert {:ok, _invitation} =
               Projects.create_invitation(
                 user_scope_fixture(user),
                 project.id,
                 "usage-pending@example.com",
                 "editor"
               )

      {:ok, view, _html} = live(conn, settings_path(project, "usage-limits"))
      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsUsageLimits")

      assert vue.props["usage-limits"]["workspace"]["members"] == %{
               "used" => 2,
               "limit" => 2
             }
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, settings_path(project, "usage-limits"))

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end
  end
end

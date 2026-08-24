defmodule Storyarn.Localization.StructuralNotificationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Platform.Notifications
  alias Storyarn.Repo

  setup do
    actor = user_fixture()
    recipient = user_fixture()
    project = project_fixture(actor)
    membership_fixture(project, recipient)

    %{
      actor: actor,
      actor_scope: user_scope_fixture(actor),
      recipient: recipient,
      recipient_scope: user_scope_fixture(recipient),
      project: project
    }
  end

  test "scoped addition notifies another member with the persisted language identity", %{
    actor: actor,
    actor_scope: actor_scope,
    recipient: recipient,
    recipient_scope: recipient_scope,
    project: project
  } do
    :ok = Notifications.subscribe(recipient_scope)
    :ok = Notifications.subscribe(actor_scope)

    assert {:ok, language} =
             Localization.add_language(actor_scope, project, %{
               locale_code: "fr-FR",
               name: "French (France)"
             })

    assert [notification] = Notifications.list_notifications(recipient_scope)
    assert notification.recipient_id == recipient.id
    assert notification.actor_id == actor.id
    assert notification.project_id == project.id
    assert notification.kind == "content_created"
    assert notification.entity_type == "localization_language"
    assert notification.entity_id == language.id
    assert notification.entity_name == language.name
    assert notification.entity_name == "French (France)"

    assert Notifications.list_notifications(actor_scope) == []
    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50
  end

  test "scoped source-language change notifies a member when it creates a locale", %{
    actor: actor,
    actor_scope: actor_scope,
    recipient: recipient,
    recipient_scope: recipient_scope,
    project: project
  } do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    :ok = Notifications.subscribe(recipient_scope)

    assert {:ok, new_source} =
             Localization.change_source_language(actor_scope, project, "fr-FR")

    assert_receive :notifications_changed

    assert [notification] = Notifications.list_notifications(recipient_scope)
    assert notification.recipient_id == recipient.id
    assert notification.actor_id == actor.id
    assert notification.project_id == project.id
    assert notification.kind == "content_created"
    assert notification.entity_type == "localization_language"
    assert notification.entity_id == new_source.id
    assert notification.entity_name == new_source.name

    assert Notifications.list_notifications(actor_scope) == []
    assert content_activity_marker_count(project) == 1
  end

  test "scoped source-language promotion of an existing target stays silent", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    :ok = Notifications.subscribe(recipient_scope)

    assert {:ok, promoted} =
             Localization.change_source_language(actor_scope, project, "es")

    assert promoted.id == target.id
    assert promoted.is_source
    assert Notifications.list_notifications(recipient_scope) == []
    refute_receive :notifications_changed, 100
    assert content_activity_marker_count(project) == 0
  end

  test "scoped source-language reactivation of an archived target stays silent", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    target = language_fixture(project, %{locale_code: "it", name: "Italian"})
    assert {:ok, archived} = Localization.remove_language(target)
    assert archived.archived_at
    :ok = Notifications.subscribe(recipient_scope)

    assert {:ok, reactivated} =
             Localization.change_source_language(actor_scope, project, "it")

    assert reactivated.id == target.id
    assert reactivated.is_source
    assert is_nil(reactivated.archived_at)
    assert Notifications.list_notifications(recipient_scope) == []
    refute_receive :notifications_changed, 100
    assert content_activity_marker_count(project) == 0
  end

  test "unauthorized source-language creation leaves no language, notification, or marker", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    outsider_scope = user_scope_fixture(user_fixture())
    :ok = Notifications.subscribe(recipient_scope)

    assert {:error, :not_found} =
             Localization.change_source_language(outsider_scope, project, "pt-BR")

    assert Localization.get_language_by_locale(project.id, "pt-BR") == nil
    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
    assert Notifications.list_notifications(outsider_scope) == []
    refute_receive :notifications_changed, 100
    assert content_activity_marker_count(project) == 0
  end

  test "scoped archival uses the locked current language name", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    stale_language = language_fixture(project, %{locale_code: "de", name: "Old German Name"})

    assert {:ok, updated_language} =
             Localization.update_language(stale_language, %{name: "Current German Name"})

    assert updated_language.name == "Current German Name"
    assert Notifications.list_notifications(recipient_scope) == []
    :ok = Notifications.subscribe(recipient_scope)
    :ok = Notifications.subscribe(actor_scope)

    assert {:ok, archived} = Localization.remove_language(actor_scope, stale_language)
    assert archived.archived_at

    assert [notification] = Notifications.list_notifications(recipient_scope)
    assert notification.kind == "content_deleted"
    assert notification.entity_type == "localization_language"
    assert notification.entity_id == stale_language.id
    assert notification.entity_name == "Current German Name"
    assert_receive :notifications_changed
    refute_receive :notifications_changed, 50
  end

  test "updates and the unscoped add/archive API stay silent", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    assert {:ok, language} =
             Localization.add_language(project, %{locale_code: "it", name: "Italian"})

    assert {:ok, updated} = Localization.update_language(language, %{name: "Italiano"})
    assert {:ok, archived} = Localization.remove_language(updated)
    assert archived.archived_at

    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
  end

  test "scoped addition reactivates a legacy archived locale without notifying", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    :ok = Notifications.subscribe(recipient_scope)

    assert {:ok, language} =
             Localization.add_language(project, %{locale_code: "nl", name: "Dutch"})

    assert {:ok, archived} = Localization.remove_language(language)
    assert archived.id == language.id
    assert archived.archived_at
    assert Notifications.list_notifications(recipient_scope) == []
    refute_receive :notifications_changed

    assert {:ok, reactivated} =
             Localization.add_language(actor_scope, project, %{
               locale_code: "nl",
               name: "Dutch (reactivated)"
             })

    assert reactivated.id == language.id
    assert is_nil(reactivated.archived_at)
    assert Notifications.list_notifications(recipient_scope) == []
    refute_receive :notifications_changed, 100
  end

  test "scoped reactivation rejects a user without project access", %{project: project} do
    assert {:ok, language} =
             Localization.add_language(project, %{locale_code: "sv", name: "Swedish"})

    assert {:ok, archived} = Localization.remove_language(language)
    assert archived.archived_at

    outsider_scope = user_scope_fixture(user_fixture())

    assert {:error, :not_found} =
             Localization.add_language(outsider_scope, project, %{
               locale_code: "sv",
               name: "Unauthorized reactivation"
             })

    assert is_nil(Localization.get_language(project.id, language.id))
  end

  test "rejecting source-language archival rolls back without a notification", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    source = source_language_fixture(project, %{name: "English Source"})

    assert {:error, :source_language} = Localization.remove_language(actor_scope, source)

    assert %{
             id: source_id,
             archived_at: nil
           } = Localization.get_language(project.id, source.id)

    assert source_id == source.id
    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
  end

  test "a scoped addition by an actor without access rolls back the language", %{
    actor_scope: actor_scope,
    recipient_scope: recipient_scope,
    project: project
  } do
    outsider_scope = user_scope_fixture(user_fixture())

    assert {:error, :not_found} =
             Localization.add_language(outsider_scope, project, %{
               locale_code: "pt-BR",
               name: "Portuguese (Brazil)"
             })

    assert Localization.get_language_by_locale(project.id, "pt-BR") == nil
    assert Notifications.list_notifications(recipient_scope) == []
    assert Notifications.list_notifications(actor_scope) == []
    assert Notifications.list_notifications(outsider_scope) == []
  end

  test "scoped writers reject a missing actor without raising", %{project: project} do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    missing_actor_scope = %{user: nil}

    assert {:error, :not_found} =
             Localization.add_language(missing_actor_scope, project, %{
               locale_code: "fr",
               name: "French"
             })

    assert {:error, :not_found} =
             Localization.add_language_with_count(missing_actor_scope, project, %{
               locale_code: "de",
               name: "German"
             })

    assert {:error, :not_found} = Localization.remove_language(missing_actor_scope, target)
    assert {:error, :not_found} = Localization.change_source_language(missing_actor_scope, project, "fr")

    assert {:error, :not_found} =
             Localization.change_source_language(missing_actor_scope, project, "fr", reset_translations: true)

    assert Localization.get_language(project.id, target.id).archived_at == nil
    assert Localization.get_language_by_locale(project.id, "fr") == nil
    assert Localization.get_language_by_locale(project.id, "de") == nil
  end

  defp content_activity_marker_count(project) do
    Repo.one(
      from(marker in "notification_content_activity_markers",
        where:
          field(marker, :project_id) == ^project.id and
            field(marker, :entity_type) == "localization_language",
        select: count(field(marker, :id))
      )
    )
  end
end

defmodule StoryarnWeb.SceneLive.VersionEventsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Versioning.RestorePolicy
  alias StoryarnWeb.SceneLive.VersionEvents
  alias StoryarnWeb.SceneLive.VersionHistory

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")

    original_policy = Application.get_env(:storyarn, RestorePolicy)

    on_exit(fn -> restore_config(RestorePolicy, original_policy) end)

    :ok
  end

  test "disabled capability and server gate stay aligned" do
    Application.put_env(:storyarn, RestorePolicy, scene_version_restore: false)

    refute Scenes.restore_enabled?()

    socket = build_socket(%{membership: %{role: "editor"}})

    assert {:noreply, result} =
             VersionEvents.with_authorized_restore(socket, fn authorized_socket ->
               send(self(), :restore_callback_called)
               {:noreply, authorized_socket}
             end)

    assert result.assigns.flash["error"] == "Could not restore version."
    refute_received :restore_callback_called
  end

  test "enabled server gate admits editors and still rejects viewers" do
    Application.put_env(:storyarn, RestorePolicy, scene_version_restore: true)

    assert Scenes.restore_enabled?()

    editor_socket = build_socket(%{membership: %{role: "editor"}})

    assert {:noreply, ^editor_socket} =
             VersionEvents.with_authorized_restore(editor_socket, fn authorized_socket ->
               send(self(), :editor_restore_callback_called)
               {:noreply, authorized_socket}
             end)

    assert_received :editor_restore_callback_called

    viewer_socket = build_socket(%{membership: %{role: "viewer"}})

    assert {:noreply, viewer_result} =
             VersionEvents.with_authorized_restore(viewer_socket, fn authorized_socket ->
               send(self(), :viewer_restore_callback_called)
               {:noreply, authorized_socket}
             end)

    assert viewer_result.assigns.flash["error"] ==
             "You don't have permission to perform this action."

    refute_received :viewer_restore_callback_called
  end

  test "restore request correlation preserves the existing bounded contract" do
    request_id = String.duplicate("x", 64)

    assert VersionHistory.restore_request_id(%{}) == {:ok, nil}
    assert VersionHistory.restore_request_id(%{"request_id" => request_id}) == {:ok, request_id}

    assert VersionHistory.put_restore_request_id(%{versionNumber: 7}, request_id) == %{
             versionNumber: 7,
             request_id: request_id
           }

    assert VersionHistory.put_restore_request_id(%{versionNumber: 7}, nil) == %{versionNumber: 7}

    for invalid <- [nil, 42, %{}, "", String.duplicate("x", 65)] do
      assert VersionHistory.restore_request_id(%{"request_id" => invalid}) == :error
    end
  end

  test "version serialization preserves the Vue history payload" do
    inserted_at = ~U[2026-08-23 10:15:00Z]

    version = %{
      id: 31,
      version_number: 7,
      title: "Milestone",
      description: "Playable draft",
      change_summary: "Scene renamed",
      change_details: %{"scene" => %{"name" => true}},
      is_auto: false,
      entity_type: "scene",
      inserted_at: inserted_at,
      created_by: %{display_name: "Scene Author", email: "author@example.com"}
    }

    assert VersionHistory.serialize_versions([version]) == [
             %{
               id: 31,
               versionNumber: 7,
               title: "Milestone",
               description: "Playable draft",
               changeSummary: "Scene renamed",
               changeDetails: %{"scene" => %{"name" => true}},
               isAuto: false,
               entityType: "scene",
               insertedAt: "Aug 23, 2026 at 10:15",
               createdBy: "Scene Author"
             }
           ]
  end

  test "conflict preview preserves the existing event name and payload shape" do
    socket = build_socket(%{})
    version = %{version_number: 7}

    report = %{
      has_conflicts: true,
      shortcut_collision: true,
      resolved_shortcut: "scene-2",
      conflicts: [%{type: :sheet, id: 9, contexts: ["pin"]}]
    }

    assert {:noreply, result} =
             VersionHistory.show_conflict_preview(socket, version, report, "preview-request")

    assert pushed_payload(result, "show_restore_modal") == %{
             versionNumber: 7,
             request_id: "preview-request",
             report: %{
               hasConflicts: true,
               shortcutCollision: true,
               resolvedShortcut: "scene-2",
               conflicts: [%{type: "sheet", id: 9, contexts: ["pin"]}]
             }
           }
  end

  describe "Scene restore event containment" do
    setup do
      Application.put_env(:storyarn, RestorePolicy, scene_version_restore: true)

      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Restore Scene"})

      {:ok, version} =
        Scenes.create_version(scene, user.id, title: "Restore target")

      %{user: user, project: project, scene: scene, version: version}
    end

    test "review shows the modal without creating an early safety version", context do
      socket = restore_socket(context, "editor")

      assert {:noreply, result} =
               VersionEvents.handle_review_restore(
                 restore_params(context.version, "review-request"),
                 socket,
                 scene_version_config()
               )

      payload = pushed_payload(result, "show_restore_modal")
      assert payload_value(payload, :versionNumber) == context.version.version_number
      assert payload_value(payload, :request_id) == "review-request"
      refute Map.has_key?(payload, :skipPreSnapshot)
      refute Map.has_key?(payload, "skipPreSnapshot")
      assert Scenes.count_versions(context.scene.id) == 1
    end

    test "review uses the canonical editor membership and defers safety creation", context do
      editor = user_fixture()
      membership_fixture(context.project, editor, "editor")

      # The cached role is deliberately stale: authorization must use the
      # persisted membership for this project.
      socket = restore_socket(%{context | user: editor}, "viewer")

      assert {:noreply, result} =
               VersionEvents.handle_review_restore(
                 restore_params(context.version, "actor-review-request"),
                 socket,
                 scene_version_config()
               )

      assert pushed_payload(result, "show_restore_modal")
      assert Scenes.count_versions(context.scene.id) == 1
    end

    test "all forged restore events are inert while containment is active", context do
      Application.put_env(:storyarn, RestorePolicy, scene_version_restore: false)
      socket = restore_socket(context, "editor")
      params = restore_params(context.version, "contained-request")
      config = scene_version_config()

      results =
        for handler <- [
              :handle_preview_restore,
              :handle_review_restore,
              :handle_confirm_restore
            ] do
          assert {:noreply, result} = apply(VersionEvents, handler, [params, socket, config])
          result
        end

      for result <- results do
        assert result.assigns.flash["error"] == "Could not restore version."
        refute pushed_payload(result, "show_unsaved_modal")
        refute pushed_payload(result, "show_restore_modal")
        refute pushed_payload(result, "version_restored")
      end

      assert Scenes.count_versions(context.scene.id) == 1
    end

    test "a viewer cannot forge any restore event", context do
      viewer = user_fixture()
      membership_fixture(context.project, viewer, "viewer")

      # A forged/stale editor assign must not override the canonical viewer
      # membership re-read by every restore event.
      socket = restore_socket(%{context | user: viewer}, "editor")
      params = restore_params(context.version, "viewer-request")
      config = scene_version_config()

      for handler <- [
            :handle_preview_restore,
            :handle_review_restore,
            :handle_confirm_restore
          ] do
        assert {:noreply, result} = apply(VersionEvents, handler, [params, socket, config])

        assert result.assigns.flash["error"] ==
                 "You don't have permission to perform this action."

        refute pushed_payload(result, "show_unsaved_modal")
        refute pushed_payload(result, "show_restore_modal")
        refute pushed_payload(result, "version_restored")
      end

      assert Scenes.count_versions(context.scene.id) == 1
    end

    test "echoes each exact request ID through preview, review, and confirmation", context do
      socket = restore_socket(context, "editor")
      config = scene_version_config()

      assert {:noreply, preview_result} =
               VersionEvents.handle_preview_restore(
                 restore_params(context.version, "preview-request"),
                 socket,
                 config
               )

      preview_payload =
        pushed_payload(preview_result, "show_unsaved_modal") ||
          pushed_payload(preview_result, "show_restore_modal")

      assert payload_value(preview_payload, :request_id) == "preview-request"

      assert {:noreply, review_result} =
               VersionEvents.handle_review_restore(
                 restore_params(context.version, "review-request"),
                 socket,
                 config
               )

      assert review_result
             |> pushed_payload("show_restore_modal")
             |> payload_value(:request_id) == "review-request"

      assert {:noreply, confirm_result} =
               VersionEvents.handle_confirm_restore(
                 restore_params(context.version, "confirm-request"),
                 socket,
                 config
               )

      assert confirm_result
             |> pushed_payload("version_restored")
             |> payload_value(:request_id) == "confirm-request"
    end

    test "accepts and echoes the 64-byte request ID boundary", context do
      socket = restore_socket(context, "editor")
      request_id = String.duplicate("x", 64)

      assert {:noreply, result} =
               VersionEvents.handle_review_restore(
                 restore_params(context.version, request_id),
                 socket,
                 scene_version_config()
               )

      assert result
             |> pushed_payload("show_restore_modal")
             |> payload_value(:request_id) == request_id
    end

    test "legacy requests omit correlation IDs from every response payload", context do
      socket = restore_socket(context, "editor")
      config = scene_version_config()
      params = %{"version_number" => to_string(context.version.version_number)}

      assert {:noreply, preview_result} =
               VersionEvents.handle_preview_restore(params, socket, config)

      assert {:noreply, review_result} =
               VersionEvents.handle_review_restore(params, socket, config)

      assert {:noreply, confirm_result} =
               VersionEvents.handle_confirm_restore(params, socket, config)

      preview_payload =
        pushed_payload(preview_result, "show_unsaved_modal") ||
          pushed_payload(preview_result, "show_restore_modal")

      payloads = [
        preview_payload,
        pushed_payload(review_result, "show_restore_modal"),
        pushed_payload(confirm_result, "version_restored")
      ]

      for payload <- payloads do
        refute Map.has_key?(payload, :request_id)
        refute Map.has_key?(payload, "request_id")
      end

      assert Scenes.count_versions(context.scene.id) == 3
    end

    test "rejects malformed request IDs before authorization or restore", context do
      socket = restore_socket(context, "viewer")
      config = scene_version_config()

      for request_id <- [nil, 42, %{}, "", String.duplicate("x", 65)],
          handler <- [
            :handle_preview_restore,
            :handle_review_restore,
            :handle_confirm_restore
          ] do
        params = restore_params(context.version, request_id)
        assert {:noreply, ^socket} = apply(VersionEvents, handler, [params, socket, config])
      end

      refute socket.assigns.flash["error"]
      refute pushed_payload(socket, "show_unsaved_modal")
      refute pushed_payload(socket, "show_restore_modal")
      refute pushed_payload(socket, "version_restored")
      assert Scenes.count_versions(context.scene.id) == 1
    end
  end

  defp build_socket(assigns) do
    %Socket{assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)}
  end

  defp pushed_payload(socket, event_name) do
    socket
    |> get_in([Access.key(:private), :live_temp, :push_events])
    |> List.wrap()
    |> Enum.find_value(fn
      [^event_name, payload] -> payload
      {^event_name, payload} -> payload
      _other -> nil
    end)
  end

  defp restore_socket(context, role) do
    build_socket(%{
      current_scope: Scope.for_user(context.user),
      scene: context.scene,
      membership: %{role: role},
      project: context.project
    })
  end

  defp scene_version_config do
    %{
      restore_path: fn _socket -> "/restored" end
    }
  end

  defp restore_params(version, request_id) do
    %{
      "version_number" => to_string(version.version_number),
      "request_id" => request_id
    }
  end

  defp payload_value(payload, key) when is_atom(key) do
    case Map.fetch(payload, key) do
      {:ok, value} -> value
      :error -> Map.get(payload, Atom.to_string(key))
    end
  end

  defp restore_config(module, nil), do: Application.delete_env(:storyarn, module)
  defp restore_config(module, config), do: Application.put_env(:storyarn, module, config)
end

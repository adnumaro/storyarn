defmodule StoryarnWeb.Helpers.VersionEventHelpersTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias StoryarnWeb.Helpers.VersionEventHelpers

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")

    restore_policy =
      Application.get_env(:storyarn, RestorePolicy, [])

    on_exit(fn ->
      Application.put_env(
        :storyarn,
        RestorePolicy,
        restore_policy
      )
    end)

    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Restore Flow"})

    {:ok, version} =
      Versioning.create_version("flow", flow, project.id, user.id, title: "Restore target")

    %{user: user, project: project, flow: flow, version: version}
  end

  describe "handle_review_restore/3" do
    test "shows the restore modal without creating an early race-prone safety version", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      assert {:noreply, result} =
               VersionEventHelpers.handle_review_restore(
                 restore_params(version, "review-request"),
                 socket,
                 flow_version_config()
               )

      assert event = pushed_event(result, "show_restore_modal")
      payload = pushed_payload(event)
      assert payload_value(payload, :versionNumber) == version.version_number
      assert payload_value(payload, :request_id) == "review-request"
      refute Map.has_key?(payload, :skipPreSnapshot)
      refute Map.has_key?(payload, "skipPreSnapshot")

      assert Versioning.count_versions("flow", flow.id) == 1
    end

    test "defers actor validation and backup creation until final confirmation", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      invalid_user = %{user | id: -1}

      socket =
        build_socket(%{
          current_scope: Scope.for_user(invalid_user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      assert {:noreply, result} =
               VersionEventHelpers.handle_review_restore(
                 restore_params(version, "actor-review-request"),
                 socket,
                 flow_version_config()
               )

      assert pushed_event(result, "show_restore_modal")
      assert Versioning.count_versions("flow", flow.id) == 1
    end

    test "all forged restore events are inert while containment is active", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      policy =
        Application.get_env(:storyarn, RestorePolicy, [])

      Application.put_env(
        :storyarn,
        RestorePolicy,
        Keyword.put(policy, :flow_version_restore, false)
      )

      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      params = restore_params(version, "contained-request")
      config = flow_version_config()

      assert {:noreply, preview_socket} =
               VersionEventHelpers.handle_preview_restore(params, socket, config)

      assert {:noreply, review_socket} =
               VersionEventHelpers.handle_review_restore(params, socket, config)

      assert {:noreply, confirm_socket} =
               VersionEventHelpers.handle_confirm_restore(params, socket, config)

      for result <- [
            preview_socket,
            review_socket,
            confirm_socket
          ] do
        assert result.assigns.flash["error"] == "Could not restore version."
        refute pushed_event(result, "show_unsaved_modal")
        refute pushed_event(result, "show_restore_modal")
        refute pushed_event(result, "version_restored")
      end

      assert Versioning.count_versions("flow", flow.id) == 1
    end

    test "a viewer cannot forge a restore preview while the feature is enabled", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "viewer"},
          project: project
        })

      assert {:noreply, result} =
               VersionEventHelpers.handle_preview_restore(
                 restore_params(version, "viewer-request"),
                 socket,
                 flow_version_config()
               )

      assert result.assigns.flash["error"] ==
               "You don't have permission to perform this action."

      refute pushed_event(result, "show_unsaved_modal")
      refute pushed_event(result, "show_restore_modal")
    end

    test "echoes the exact request ID through preview, review, and confirmation", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      assert {:noreply, preview_result} =
               VersionEventHelpers.handle_preview_restore(
                 restore_params(version, "preview-request"),
                 socket,
                 flow_version_config()
               )

      assert preview_event =
               pushed_event(preview_result, "show_unsaved_modal") ||
                 pushed_event(preview_result, "show_restore_modal")

      assert payload_value(pushed_payload(preview_event), :request_id) == "preview-request"

      assert {:noreply, review_result} =
               VersionEventHelpers.handle_review_restore(
                 restore_params(version, "review-request"),
                 socket,
                 flow_version_config()
               )

      assert review_event = pushed_event(review_result, "show_restore_modal")
      assert payload_value(pushed_payload(review_event), :request_id) == "review-request"

      assert {:noreply, confirm_result} =
               VersionEventHelpers.handle_confirm_restore(
                 restore_params(version, "confirm-request"),
                 socket,
                 flow_version_config()
               )

      assert confirm_event = pushed_event(confirm_result, "version_restored")
      assert payload_value(pushed_payload(confirm_event), :request_id) == "confirm-request"
    end

    test "accepts and echoes the 64-byte request ID boundary", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      request_id = String.duplicate("x", 64)

      assert {:noreply, result} =
               VersionEventHelpers.handle_review_restore(
                 restore_params(version, request_id),
                 socket,
                 flow_version_config()
               )

      assert event = pushed_event(result, "show_restore_modal")
      assert payload_value(pushed_payload(event), :request_id) == request_id
    end

    test "omits request IDs from all response payloads for legacy clients", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "editor"},
          project: project
        })

      params = %{"version_number" => to_string(version.version_number)}

      assert {:noreply, preview_result} =
               VersionEventHelpers.handle_preview_restore(params, socket, flow_version_config())

      assert {:noreply, review_result} =
               VersionEventHelpers.handle_review_restore(params, socket, flow_version_config())

      assert {:noreply, confirm_result} =
               VersionEventHelpers.handle_confirm_restore(params, socket, flow_version_config())

      assert preview_event =
               pushed_event(preview_result, "show_unsaved_modal") ||
                 pushed_event(preview_result, "show_restore_modal")

      assert review_event = pushed_event(review_result, "show_restore_modal")
      assert confirm_event = pushed_event(confirm_result, "version_restored")

      for event <- [preview_event, review_event, confirm_event] do
        payload = pushed_payload(event)
        refute Map.has_key?(payload, :request_id)
        refute Map.has_key?(payload, "request_id")
      end

      assert Versioning.count_versions("flow", flow.id) == 3
    end

    test "rejects present malformed request IDs before authorization or restore", %{
      user: user,
      project: project,
      flow: flow,
      version: version
    } do
      socket =
        build_socket(%{
          current_scope: Scope.for_user(user),
          flow: flow,
          membership: %{role: "viewer"},
          project: project
        })

      config = flow_version_config()

      for request_id <- [nil, 42, %{}, "", String.duplicate("x", 65)],
          handler <- [
            :handle_preview_restore,
            :handle_review_restore,
            :handle_confirm_restore
          ] do
        params = restore_params(version, request_id)

        assert {:noreply, ^socket} =
                 apply(VersionEventHelpers, handler, [params, socket, config])
      end

      refute socket.assigns.flash["error"]
      refute pushed_event(socket, "show_unsaved_modal")
      refute pushed_event(socket, "show_restore_modal")
      refute pushed_event(socket, "version_restored")
      assert Versioning.count_versions("flow", flow.id) == 1
    end
  end

  defp build_socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  defp flow_version_config do
    %{
      entity_key: :flow,
      entity_type: "flow",
      restore_path: fn _socket -> "/restored" end
    }
  end

  defp restore_params(version, request_id) do
    %{
      "version_number" => to_string(version.version_number),
      "request_id" => request_id
    }
  end

  defp pushed_event(socket, event_name) do
    socket
    |> get_in([Access.key(:private), :live_temp, :push_events])
    |> List.wrap()
    |> Enum.find(fn
      [name, _payload] -> name == event_name
      {name, _payload} -> name == event_name
    end)
  end

  defp pushed_payload([_name, payload]), do: payload
  defp pushed_payload({_name, payload}), do: payload

  defp payload_value(payload, key) when is_atom(key) do
    case Map.fetch(payload, key) do
      {:ok, value} -> value
      :error -> Map.get(payload, Atom.to_string(key))
    end
  end
end

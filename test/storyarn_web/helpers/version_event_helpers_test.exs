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

  describe "handle_save_and_restore/3" do
    test "shows the restore modal after creating the pre-restore backup", %{
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
               VersionEventHelpers.handle_save_and_restore(
                 %{"version_number" => to_string(version.version_number)},
                 socket,
                 flow_version_config()
               )

      assert event = pushed_event(result, "show_restore_modal")
      payload = pushed_payload(event)
      assert payload_value(payload, :versionNumber) == version.version_number
      assert payload_value(payload, :skipPreSnapshot) == true

      backup = Versioning.get_version("flow", flow.id, 2)
      assert backup.title == "Before restore to v1"
      assert Versioning.count_versions("flow", flow.id) == 2
    end

    test "aborts when the pre-restore backup cannot be created", %{
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
               VersionEventHelpers.handle_save_and_restore(
                 %{"version_number" => to_string(version.version_number)},
                 socket,
                 flow_version_config()
               )

      assert result.assigns.flash["error"] == "Could not save current state."
      refute pushed_event(result, "show_restore_modal")
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

      params = %{"version_number" => to_string(version.version_number)}
      config = flow_version_config()

      assert {:noreply, preview_socket} =
               VersionEventHelpers.handle_preview_restore(params, socket, config)

      assert {:noreply, save_socket} =
               VersionEventHelpers.handle_save_and_restore(params, socket, config)

      assert {:noreply, discard_socket} =
               VersionEventHelpers.handle_discard_and_restore(params, socket, config)

      assert {:noreply, confirm_socket} =
               VersionEventHelpers.handle_confirm_restore(
                 Map.put(params, "skip_pre_snapshot", true),
                 socket,
                 config
               )

      for result <- [
            preview_socket,
            save_socket,
            discard_socket,
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
                 %{"version_number" => to_string(version.version_number)},
                 socket,
                 flow_version_config()
               )

      assert result.assigns.flash["error"] ==
               "You don't have permission to perform this action."

      refute pushed_event(result, "show_unsaved_modal")
      refute pushed_event(result, "show_restore_modal")
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
      entity_type: "flow"
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
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end
end

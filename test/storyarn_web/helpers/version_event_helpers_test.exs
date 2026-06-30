defmodule StoryarnWeb.Helpers.VersionEventHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias StoryarnWeb.Helpers.VersionEventHelpers

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")

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

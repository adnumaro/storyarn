defmodule StoryarnWeb.Helpers.VersionEventHelpersTest do
  use ExUnit.Case, async: false

  alias Phoenix.LiveView.Socket
  alias Storyarn.Versioning.RestorePolicy
  alias StoryarnWeb.Helpers.VersionEventHelpers

  setup do
    Gettext.put_locale(Storyarn.Gettext, "en")
    restore_policy = Application.get_env(:storyarn, RestorePolicy, [])

    on_exit(fn ->
      Application.put_env(:storyarn, RestorePolicy, restore_policy)
    end)

    :ok
  end

  describe "with_authorized_restore/3" do
    test "runs the callback for an editor when Sheet restore is enabled" do
      Application.put_env(:storyarn, RestorePolicy, sheet_version_restore: true)
      test_pid = self()
      socket = build_socket("editor")

      assert {:noreply, ^socket} =
               VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
                 send(test_pid, :restore_authorized)
                 {:noreply, authorized_socket}
               end)

      assert_received :restore_authorized
    end

    test "fails closed before invoking the callback when Sheet restore is disabled" do
      Application.put_env(:storyarn, RestorePolicy, sheet_version_restore: false)
      test_pid = self()
      socket = build_socket("editor")

      assert {:noreply, result} =
               VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
                 send(test_pid, :restore_authorized)
                 {:noreply, authorized_socket}
               end)

      refute_received :restore_authorized
      assert result.assigns.flash["error"] == "Could not restore version."
    end

    test "does not invoke the callback for a viewer when Sheet restore is enabled" do
      Application.put_env(:storyarn, RestorePolicy, sheet_version_restore: true)
      test_pid = self()
      socket = build_socket("viewer")

      assert {:noreply, result} =
               VersionEventHelpers.with_authorized_restore(socket, "sheet", fn authorized_socket ->
                 send(test_pid, :restore_authorized)
                 {:noreply, authorized_socket}
               end)

      refute_received :restore_authorized

      assert result.assigns.flash["error"] ==
               "You don't have permission to perform this action."
    end
  end

  defp build_socket(role) do
    %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        membership: %{role: role}
      }
    }
  end
end

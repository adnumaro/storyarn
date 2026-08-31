defmodule StoryarnWeb.ProjectSettingsLive.SettingsComponentsRepairTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.ProjectLive.Components.SettingsComponents

  test "pluralizes repaired and failed node counts independently in English and Spanish" do
    assert Gettext.with_locale(Storyarn.Gettext, "en", fn ->
             SettingsComponents.partial_repair_message(1, 2)
           end) ==
             "Repair partially completed: 1 node repaired; 2 nodes failed."

    assert Gettext.with_locale(Storyarn.Gettext, "en", fn ->
             SettingsComponents.partial_repair_message(2, 1)
           end) ==
             "Repair partially completed: 2 nodes repaired; 1 node failed."

    assert Gettext.with_locale(Storyarn.Gettext, "es", fn ->
             SettingsComponents.partial_repair_message(1, 2)
           end) ==
             "Reparación parcial: 1 nodo reparado; 2 nodos fallidos."

    assert Gettext.with_locale(Storyarn.Gettext, "es", fn ->
             SettingsComponents.partial_repair_message(2, 1)
           end) ==
             "Reparación parcial: 2 nodos reparados; 1 nodo fallido."

    assert Gettext.with_locale(Storyarn.Gettext, "en", fn ->
             SettingsComponents.failed_repair_message(2)
           end) ==
             "No nodes could be repaired; 2 nodes failed. Try again."

    assert Gettext.with_locale(Storyarn.Gettext, "es", fn ->
             SettingsComponents.failed_repair_message(2)
           end) ==
             "No se pudo reparar ningún nodo; fallaron 2 nodos. Inténtalo de nuevo."
  end

  test "reports repaired and failed counts for a partial variable-reference repair" do
    user = user_fixture()
    project = project_fixture(user)

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: user_scope_fixture(user),
        project: project
      }
    }

    repair_fun = fn scope, project_id ->
      assert scope.user.id == user.id
      assert project_id == project.id

      {:error,
       {:partial_variable_reference_repair,
        %{
          repaired_count: 39,
          failures: [{123, :database_unavailable}]
        }}}
    end

    assert {:noreply, repaired_socket} =
             SettingsComponents.do_repair_variable_references(socket, repair_fun)

    assert repaired_socket.assigns.flash["error"] ==
             "Repair partially completed: 39 nodes repaired; 1 node failed."
  end

  test "reports the failed count when no candidate could be repaired" do
    user = user_fixture()
    project = project_fixture(user)

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: user_scope_fixture(user),
        project: project
      }
    }

    repair_fun = fn scope, project_id ->
      assert scope.user.id == user.id
      assert project_id == project.id

      {:error,
       {:partial_variable_reference_repair,
        %{
          repaired_count: 0,
          failures: [{123, :concurrent_change}, {456, :node_not_found}]
        }}}
    end

    assert {:noreply, repaired_socket} =
             SettingsComponents.do_repair_variable_references(socket, repair_fun)

    assert repaired_socket.assigns.flash["error"] ==
             "No nodes could be repaired; 2 nodes failed. Try again."
  end

  test "explains ownership drift without reporting a generic repair failure" do
    user = user_fixture()
    project = project_fixture(user)

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: user_scope_fixture(user),
        project: project
      }
    }

    assert {:noreply, repaired_socket} =
             SettingsComponents.do_repair_variable_references(
               socket,
               fn _scope, _project_id -> {:error, :ownership_invariant_violation} end
             )

    assert repaired_socket.assigns.flash["error"] ==
             "Variable references could not be repaired because project ownership is inconsistent."
  end
end

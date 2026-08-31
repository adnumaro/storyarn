defmodule StoryarnWeb.Helpers.AuthorizeTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias StoryarnWeb.Helpers.Authorize

  defp socket_with_membership(role) do
    %Socket{
      assigns: %{__changed__: %{}, flash: %{}, membership: %{role: role}}
    }
  end

  defp socket_without_membership do
    %Socket{
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end

  defp socket_with_nil_membership do
    %Socket{
      assigns: %{__changed__: %{}, flash: %{}, membership: nil}
    }
  end

  describe "authorize/2 with :edit_content" do
    test "allows owner" do
      assert :ok = Authorize.authorize(socket_with_membership("owner"), :edit_content)
    end

    test "allows editor" do
      assert :ok = Authorize.authorize(socket_with_membership("editor"), :edit_content)
    end

    test "denies viewer" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("viewer"), :edit_content)
    end

    test "denies when no membership" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_without_membership(), :edit_content)
    end

    test "denies when membership is nil" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_nil_membership(), :edit_content)
    end

    test "reauthorizes sticky child LiveViews that carry only project_id" do
      owner = user_fixture()
      project = project_fixture(owner)
      editor = user_fixture()
      membership = membership_fixture(project, editor, "editor")

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: Scope.for_user(editor),
          project_id: project.id,
          membership: %{role: "editor"}
        }
      }

      assert :ok = Authorize.authorize(socket, :edit_content)
      Repo.update!(Ecto.Changeset.change(membership, role: "viewer"))

      assert {:error, :unauthorized} = Authorize.authorize(socket, :edit_content)
    end

    test "a scoped socket without a resource identity fails closed" do
      user = user_fixture()

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: Scope.for_user(user),
          membership: %{role: "owner"}
        }
      }

      assert {:error, :unauthorized} = Authorize.authorize(socket, :edit_content)
    end
  end

  describe "authorize/2 with :manage_project" do
    test "allows owner" do
      assert :ok = Authorize.authorize(socket_with_membership("owner"), :manage_project)
    end

    test "denies editor" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("editor"), :manage_project)
    end

    test "denies viewer" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("viewer"), :manage_project)
    end

    test "denies when no membership" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_without_membership(), :manage_project)
    end
  end

  describe "authorize/2 with :manage_members" do
    test "allows owner" do
      assert :ok = Authorize.authorize(socket_with_membership("owner"), :manage_members)
    end

    test "denies editor" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("editor"), :manage_members)
    end

    test "denies viewer" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("viewer"), :manage_members)
    end

    test "denies when no membership" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_without_membership(), :manage_members)
    end
  end

  describe "authorize/2 with :manage_workspace" do
    test "allows owner" do
      assert :ok = Authorize.authorize(socket_with_membership("owner"), :manage_workspace)
    end

    test "denies admin because workspace management is owner-only" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("admin"), :manage_workspace)
    end

    test "denies member" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("member"), :manage_workspace)
    end

    test "denies viewer" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("viewer"), :manage_workspace)
    end

    test "denies when no membership" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_without_membership(), :manage_workspace)
    end
  end

  describe "authorize/2 with :manage_workspace_members" do
    test "allows owner" do
      assert :ok =
               Authorize.authorize(socket_with_membership("owner"), :manage_workspace_members)
    end

    test "allows admin" do
      assert :ok =
               Authorize.authorize(socket_with_membership("admin"), :manage_workspace_members)
    end

    test "denies member" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("member"), :manage_workspace_members)
    end

    test "denies viewer" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("viewer"), :manage_workspace_members)
    end

    test "denies when no membership" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_without_membership(), :manage_workspace_members)
    end
  end

  describe "authorize/2 with unknown action" do
    test "denies unknown actions" do
      assert {:error, :unauthorized} =
               Authorize.authorize(socket_with_membership("owner"), :unknown_action)
    end
  end

  describe "with_authorization/3" do
    test "executes function when authorized" do
      socket = socket_with_membership("owner")

      result =
        Authorize.with_authorization(socket, :edit_content, fn socket ->
          {:noreply, socket}
        end)

      assert {:noreply, %Socket{}} = result
    end

    test "preserves a reply result when authorized" do
      socket = socket_with_membership("owner")

      assert {:reply, %{ok: true}, ^socket} =
               Authorize.with_authorization(socket, :edit_content, fn callback_socket ->
                 {:reply, %{ok: true}, callback_socket}
               end)
    end

    test "returns unauthorized flash when not authorized" do
      socket = socket_with_membership("viewer")

      result =
        Authorize.with_authorization(socket, :edit_content, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"]
    end

    test "translates the shared unauthorized flash in the active locale" do
      message =
        Gettext.with_locale(Storyarn.Gettext, "es", fn ->
          socket = socket_with_membership("viewer")

          {:noreply, result_socket} =
            Authorize.with_authorization(socket, :edit_content, fn _socket ->
              raise "should not be called"
            end)

          result_socket.assigns.flash["error"]
        end)

      assert message == "No tienes permiso para realizar esta acción."
    end
  end

  describe "with_authorization/4" do
    test "exposes a canonical ownership failure to the explicit failure callback" do
      owner = user_fixture()
      project = project_fixture(owner)
      second_owner = user_fixture()
      _second_owner_membership = membership_fixture(project, second_owner, "owner")

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: Scope.for_user(owner),
          project: project,
          membership: %{role: "owner"}
        }
      }

      assert {:error, :unauthorized} = Authorize.authorize(socket, :manage_project)

      assert {:noreply, ^socket} =
               Authorize.with_authorization(
                 socket,
                 :manage_project,
                 fn _socket -> raise "should not be called" end,
                 fn callback_socket, reason ->
                   assert reason == :ownership_invariant_violation
                   {:noreply, callback_socket}
                 end
               )
    end

    test "preserves a reply result from the explicit failure callback" do
      socket = socket_with_membership("viewer")

      assert {:reply, %{ok: false, reason: :unauthorized}, ^socket} =
               Authorize.with_authorization(
                 socket,
                 :edit_content,
                 fn _socket -> raise "should not be called" end,
                 fn callback_socket, reason ->
                   {:reply, %{ok: false, reason: reason}, callback_socket}
                 end
               )
    end
  end

  describe "with_edit_authorization/2" do
    test "executes function for a canonically authorized membership" do
      socket = socket_with_membership("editor")

      result =
        Authorize.with_edit_authorization(socket, fn socket ->
          {:noreply, socket}
        end)

      assert {:noreply, %Socket{}} = result
    end

    test "returns unauthorized flash for a read-only membership" do
      socket = socket_with_membership("viewer")

      result =
        Authorize.with_edit_authorization(socket, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"]
    end

    test "does not trust a stale can_edit assign without membership" do
      socket = %Socket{
        assigns: %{__changed__: %{}, flash: %{}, can_edit: true}
      }

      result =
        Authorize.with_edit_authorization(socket, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"]
    end
  end
end

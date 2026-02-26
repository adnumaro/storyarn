defmodule StoryarnWeb.Helpers.AuthorizeTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Helpers.Authorize

  defp socket_with_membership(role) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, membership: %{role: role}}
    }
  end

  defp socket_without_membership do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end

  defp socket_with_nil_membership do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, membership: nil}
    }
  end

  defp socket_with_can_edit(can_edit) do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, can_edit: can_edit}
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

    test "allows admin" do
      assert :ok = Authorize.authorize(socket_with_membership("admin"), :manage_workspace)
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

      assert {:noreply, %Phoenix.LiveView.Socket{}} = result
    end

    test "returns unauthorized flash when not authorized" do
      socket = socket_with_membership("viewer")

      result =
        Authorize.with_authorization(socket, :edit_content, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Phoenix.LiveView.Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"] != nil
    end
  end

  describe "with_edit_authorization/2" do
    test "executes function when can_edit is true" do
      socket = socket_with_can_edit(true)

      result =
        Authorize.with_edit_authorization(socket, fn socket ->
          {:noreply, socket}
        end)

      assert {:noreply, %Phoenix.LiveView.Socket{}} = result
    end

    test "returns unauthorized flash when can_edit is false" do
      socket = socket_with_can_edit(false)

      result =
        Authorize.with_edit_authorization(socket, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Phoenix.LiveView.Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"] != nil
    end

    test "returns unauthorized flash when can_edit is nil" do
      socket = socket_with_can_edit(nil)

      result =
        Authorize.with_edit_authorization(socket, fn _socket ->
          raise "should not be called"
        end)

      assert {:noreply, %Phoenix.LiveView.Socket{} = result_socket} = result
      assert result_socket.assigns.flash["error"] != nil
    end
  end
end

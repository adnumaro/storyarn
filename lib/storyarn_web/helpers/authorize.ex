defmodule StoryarnWeb.Helpers.Authorize do
  @moduledoc """
  Authorization helpers for LiveView handle_event callbacks.

  This module provides functions to check permissions in handle_event callbacks,
  ensuring that even if UI elements are hidden, direct WebSocket events are still
  properly authorized.

  ## Usage

      use StoryarnWeb.Helpers.Authorize

      def handle_event("delete", _params, socket) do
        with :ok <- authorize(socket, :edit_content) do
          # proceed with deletion
        else
          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
        end
      end

  ## Available Actions

  ### Project Actions
  - `:edit_content` - Edit entities, templates, variables, flows
  - `:manage_project` - Update project settings, delete project
  - `:manage_members` - Invite/remove members, change roles

  ### Workspace Actions
  - `:manage_workspace` - Update workspace settings, delete workspace
  - `:manage_workspace_members` - Invite/remove members in workspace
  """

  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.Socket
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @type callback_result :: {:noreply, Socket.t()} | {:reply, map(), Socket.t()}

  defmacro __using__(_opts) do
    quote do
      import StoryarnWeb.Helpers.Authorize,
        only: [authorize: 2, with_authorization: 3, with_authorization: 4, with_edit_authorization: 2]
    end
  end

  @doc """
  Executes a function if authorized, otherwise returns unauthorized flash.

  This helper reduces boilerplate for handle_event callbacks that need authorization.
  The function receives the socket and must return a valid LiveView event
  result: either `{:noreply, socket}` or `{:reply, reply, socket}`.

  ## Examples

      def handle_event("delete", %{"id" => id}, socket) do
        with_authorization(socket, :edit_content, fn socket ->
          BlockHelpers.delete_block(socket, id)
        end)
      end

  Is equivalent to:

      def handle_event("delete", %{"id" => id}, socket) do
        case authorize(socket, :edit_content) do
          :ok -> BlockHelpers.delete_block(socket, id)
          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("You don't have permission..."))}
        end
      end
  """
  @spec with_authorization(
          Socket.t(),
          atom(),
          (Socket.t() -> callback_result())
        ) :: callback_result()
  def with_authorization(socket, action, success_fn) do
    case authorize(socket, action) do
      :ok ->
        success_fn.(socket)

      {:error, :unauthorized} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, unauthorized_message())}
    end
  end

  @doc """
  Executes an authorized function while allowing a caller to present a
  specific, context-owned failure without weakening the authorization check.

  Existing callers should keep using `with_authorization/3`. This variant is
  reserved for mutations where collapsing an integrity failure into a generic
  permission error would hide an actionable problem from the user.
  """
  @spec with_authorization(
          Socket.t(),
          atom(),
          (Socket.t() -> callback_result()),
          (Socket.t(), atom() -> callback_result())
        ) :: callback_result()
  def with_authorization(socket, action, success_fn, failure_fn) do
    case authorization_result(socket, action) do
      :ok -> success_fn.(socket)
      {:error, reason} -> failure_fn.(socket, reason)
    end
  end

  @doc """
  Executes a function after canonical project edit authorization.

  This is a compatibility spelling for LiveViews that historically checked a
  cached `can_edit` assign. It deliberately delegates to `authorize/2`: a
  mounted socket may outlive a membership change.

  ## Examples

      def handle_event("save", params, socket) do
        with_edit_authorization(socket, fn socket ->
          {:noreply, do_save(socket, params)}
        end)
      end
  """
  @spec with_edit_authorization(
          Socket.t(),
          (Socket.t() -> {:noreply, Socket.t()})
        ) :: {:noreply, Socket.t()}
  def with_edit_authorization(socket, success_fn) do
    with_authorization(socket, :edit_content, success_fn)
  end

  defp unauthorized_message do
    gettext("You don't have permission to perform this action.")
  end

  @doc """
  Checks if the current socket has permission to perform an action.

  Returns `:ok` if authorized, `{:error, :unauthorized}` otherwise.

  Mounted production sockets are reauthorized through the owning context using
  `current_scope` plus the assigned resource identity. The cached-membership
  fallback exists only for isolated tests that omit `current_scope` entirely.

  ## Examples

      # In a handle_event callback
      def handle_event("delete", _params, socket) do
        with :ok <- authorize(socket, :edit_content) do
          # Do the deletion
          {:noreply, socket}
        else
          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
        end
      end
  """
  @spec authorize(Socket.t(), atom()) :: :ok | {:error, :unauthorized}
  def authorize(socket, action) do
    case authorization_result(socket, action) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unauthorized}
    end
  end

  # A mounted socket's membership can become stale after a role change. When
  # the resource identity and scope are available, every mutation re-reads the
  # canonical membership through its owning context. The role-only fallback is
  # reserved for isolated helper/handler tests that intentionally build a
  # minimal socket without a resource.
  defp authorization_result(%{assigns: assigns}, :edit_content), do: authorize_project(assigns, :edit_content)

  # AI execution: a distinct action because a viewer may read content but must
  # never spend a workspace's AI allowance.
  defp authorization_result(%{assigns: assigns}, :use_ai), do: authorize_project(assigns, :use_ai)

  # Project management (settings, deletion)
  defp authorization_result(%{assigns: assigns}, :manage_project), do: authorize_project(assigns, :manage_project)

  # Project member management (invitations, removals)
  defp authorization_result(%{assigns: assigns}, :manage_members), do: authorize_project(assigns, :manage_members)

  # Workspace management (settings, deletion)
  defp authorization_result(%{assigns: assigns}, :manage_workspace), do: authorize_workspace(assigns, :manage_workspace)

  # Workspace member management
  defp authorization_result(%{assigns: assigns}, :manage_workspace_members),
    do: authorize_workspace(assigns, :manage_members)

  # The context independently scopes notification mutations to this user.
  defp authorization_result(%{assigns: %{current_scope: %{user: %{id: _}}}}, :manage_notifications), do: :ok

  # Catch-all: deny unknown actions
  defp authorization_result(_socket, _action), do: {:error, :unauthorized}

  defp authorize_project(%{current_scope: %{user: %{id: _}} = scope, project: %{id: project_id}}, action)
       when is_integer(project_id) do
    case Projects.authorize(scope, project_id, action) do
      {:ok, _project, _membership} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Sticky child LiveViews such as FlowSidebarLive and
  # LocalizationToolbarLive receive the project identity as a scalar session
  # value rather than a Project struct. They must still re-read membership on
  # every mutation.
  defp authorize_project(%{current_scope: %{user: %{id: _}} = scope, project_id: project_id}, action)
       when is_integer(project_id) do
    case Projects.authorize(scope, project_id, action) do
      {:ok, _project, _membership} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A production socket with a scope but no trustworthy resource identity must
  # fail closed. Never downgrade it to the cached-role compatibility path.
  defp authorize_project(%{current_scope: %{user: %{id: _}}}, _action), do: {:error, :unauthorized}

  defp authorize_project(assigns, action) do
    authorize_cached_role(assigns, action, &Projects.can?/2)
  end

  defp authorize_workspace(%{current_scope: %{user: %{id: _}} = scope, workspace: %{id: workspace_id}}, action)
       when is_integer(workspace_id) do
    case Workspaces.authorize(scope, workspace_id, action) do
      {:ok, _workspace, _membership} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_workspace(%{current_scope: %{user: %{id: _}} = scope, workspace_id: workspace_id}, action)
       when is_integer(workspace_id) do
    case Workspaces.authorize(scope, workspace_id, action) do
      {:ok, _workspace, _membership} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_workspace(%{current_scope: %{user: %{id: _}}}, _action), do: {:error, :unauthorized}

  defp authorize_workspace(assigns, action) do
    authorize_cached_role(assigns, action, &Workspaces.can?/2)
  end

  defp authorize_cached_role(assigns, action, permission?) do
    case Map.get(assigns, :membership) do
      %{role: role} when is_binary(role) ->
        if permission?.(role, action), do: :ok, else: {:error, :unauthorized}

      _missing_membership ->
        {:error, :unauthorized}
    end
  end
end

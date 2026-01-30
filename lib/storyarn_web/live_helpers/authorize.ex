defmodule StoryarnWeb.LiveHelpers.Authorize do
  @moduledoc """
  Authorization helpers for LiveView handle_event callbacks.

  This module provides functions to check permissions in handle_event callbacks,
  ensuring that even if UI elements are hidden, direct WebSocket events are still
  properly authorized.

  ## Usage

      use StoryarnWeb.LiveHelpers.Authorize

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

  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Workspaces.WorkspaceMembership

  defmacro __using__(_opts) do
    quote do
      import StoryarnWeb.LiveHelpers.Authorize, only: [authorize: 2]
    end
  end

  @doc """
  Checks if the current socket has permission to perform an action.

  Returns `:ok` if authorized, `{:error, :unauthorized}` otherwise.

  The function looks at socket assigns to determine authorization:
  - For project actions: checks `@can_edit` or `@membership` with ProjectMembership.can?
  - For workspace actions: checks `@membership` role

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
  @spec authorize(Phoenix.LiveView.Socket.t(), atom()) :: :ok | {:error, :unauthorized}
  def authorize(socket, action)

  # Project content editing actions
  def authorize(%{assigns: assigns}, :edit_content) do
    cond do
      # Fast path: check cached @can_edit assign (set at mount)
      Map.get(assigns, :can_edit) == true ->
        :ok

      # Fallback: check membership role directly
      membership = Map.get(assigns, :membership) ->
        if ProjectMembership.can?(membership.role, :edit_content) do
          :ok
        else
          {:error, :unauthorized}
        end

      # No authorization context available
      true ->
        {:error, :unauthorized}
    end
  end

  # Project management (settings, deletion)
  def authorize(%{assigns: assigns}, :manage_project) do
    case Map.get(assigns, :membership) do
      %{role: role} when is_binary(role) ->
        if ProjectMembership.can?(role, :manage_project) do
          :ok
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  # Project member management (invitations, removals)
  def authorize(%{assigns: assigns}, :manage_members) do
    case Map.get(assigns, :membership) do
      %{role: role} when is_binary(role) ->
        if ProjectMembership.can?(role, :manage_members) do
          :ok
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  # Workspace management (settings, deletion)
  def authorize(%{assigns: assigns}, :manage_workspace) do
    case Map.get(assigns, :membership) do
      %{role: role} when role in ["owner", "admin"] ->
        :ok

      _ ->
        {:error, :unauthorized}
    end
  end

  # Workspace member management
  def authorize(%{assigns: assigns}, :manage_workspace_members) do
    case Map.get(assigns, :membership) do
      %{role: role} when is_binary(role) ->
        if WorkspaceMembership.can?(role, :manage_members) do
          :ok
        else
          {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  # Catch-all: deny unknown actions
  def authorize(_socket, _action), do: {:error, :unauthorized}
end

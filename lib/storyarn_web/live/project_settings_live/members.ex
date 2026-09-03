defmodule StoryarnWeb.ProjectSettingsLive.Members do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects

  @max_pg_bigint 9_223_372_036_854_775_807

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/project/settings/ProjectSettingsMembers"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-members"
        members={serialize_members(@members)}
        pending-invitations={serialize_invitations(@pending_invitations)}
        current-user-id={Integer.to_string(@current_scope.user.id)}
        can-transfer-ownership={@project.owner_id == @current_scope.user.id}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_members(members) do
    Enum.map(members, fn m ->
      %{
        id: m.id,
        user_id: Integer.to_string(m.user_id),
        role: m.role,
        email: m.user.email,
        display_name: m.user.display_name
      }
    end)
  end

  defp serialize_invitations(invitations) do
    Enum.map(invitations, fn invitation ->
      %{
        id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        expires_at: DateTime.to_iso8601(invitation.expires_at)
      }
    end)
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    stale_project = socket.assigns.project

    if connected?(socket) do
      :ok = Projects.subscribe_project_ownership_changes(stale_project.id)
    end

    with {:ok, socket} <- refresh_project_access(socket),
         true <- current_project_owner?(socket) do
      socket = socket |> assign_member_data() |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))

      {:ok, socket}
    else
      _lost_access -> mount_access_denied(socket, stale_project)
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    socket =
      socket
      |> assign(:page_title, dgettext("projects", "Project Settings"))
      |> assign(:current_path, current_path)

    {:noreply, socket}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_remove_member(socket, id)
    end)
  end

  def handle_event("transfer_owner", %{"user-id" => user_id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_transfer_owner(socket, user_id)
    end)
  end

  def handle_event("transfer_owner", _payload, socket) do
    ownership_transfer_error(
      socket,
      dgettext("projects", "Project ownership could not be transferred.")
    )
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_revoke_invitation(socket, id)
    end)
  end

  @impl true
  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id} = receipt},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    case refresh_project_access(socket) do
      {:ok, refreshed_socket} ->
        if current_project_owner?(refreshed_socket) do
          {:noreply, assign_member_data(refreshed_socket)}
        else
          redirect_after_ownership_transfer(refreshed_socket, receipt)
        end

      {:error, :not_found} ->
        project_unavailable(socket)
    end
  end

  defp redirect_after_ownership_transfer(socket, %{previous_owner_id: previous_owner_id})
       when previous_owner_id == socket.assigns.current_scope.user.id do
    project_management_lost(socket)
  end

  defp redirect_after_ownership_transfer(socket, _receipt) do
    project_management_lost(
      socket,
      dgettext("projects", "You don't have permission to manage this project.")
    )
  end

  defp project_management_lost(socket) do
    project = socket.assigns.project

    {:noreply,
     push_navigate(socket,
       to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
     )}
  end

  defp with_fresh_manage_members_authorization(socket, success_fn) do
    case refresh_project_access(socket) do
      {:ok, refreshed_socket} ->
        if current_project_owner?(refreshed_socket) and
             Projects.can?(refreshed_socket.assigns.membership.role, :manage_members) do
          success_fn.(refreshed_socket)
        else
          project_management_lost(
            refreshed_socket,
            dgettext("projects", "You don't have permission to manage this project.")
          )
        end

      {:error, :not_found} ->
        project_unavailable(socket)
    end
  end

  defp do_transfer_owner(socket, user_id) do
    with {:ok, target_user_id} <- parse_positive_pg_bigint(user_id),
         {:ok, _receipt} <-
           Projects.transfer_owner(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             target_user_id
           ) do
      project = socket.assigns.project

      {:noreply,
       socket
       |> put_flash(:info, dgettext("projects", "Project ownership transferred."))
       |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    else
      {:error, :target_not_member} ->
        ownership_transfer_error(socket, dgettext("projects", "That person is no longer a direct project member."))

      {:error, :ownership_invariant_violation} ->
        ownership_transfer_error(
          socket,
          dgettext(
            "projects",
            "Ownership could not be transferred because the project ownership data is inconsistent."
          )
        )

      {:error, :unauthorized} ->
        ownership_transfer_error(
          socket,
          dgettext("projects", "Only the current project owner can transfer ownership.")
        )

      {:error, :not_found} ->
        project = socket.assigns.project

        {:noreply,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}")}

      _reason ->
        ownership_transfer_error(socket, dgettext("projects", "Project ownership could not be transferred."))
    end
  end

  defp ownership_transfer_error(socket, message) do
    case refresh_project_access(socket) do
      {:ok, refreshed_socket} ->
        if current_project_owner?(refreshed_socket) and
             Projects.can?(refreshed_socket.assigns.membership.role, :manage_members) do
          {:noreply, put_flash(refreshed_socket, :error, message)}
        else
          project_management_lost(refreshed_socket, message)
        end

      {:error, :not_found} ->
        project_unavailable(socket)
    end
  end

  defp refresh_project_access(socket) do
    project_id = socket.assigns.project.id

    case Projects.reload_project(socket.assigns.current_scope, project_id) do
      {:ok, project, membership} ->
        {:ok,
         socket
         |> assign(:project, project)
         |> assign(:membership, membership)
         |> assign(:current_workspace, project.workspace)}

      {:error, :not_found} = error ->
        error
    end
  end

  defp current_project_owner?(socket) do
    socket.assigns.project.owner_id == socket.assigns.current_scope.user.id and
      Projects.can?(socket.assigns.membership.role, :manage_project)
  end

  defp assign_member_data(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:members, Projects.list_project_members(project_id))
    |> assign(:pending_invitations, Projects.list_pending_invitations(project_id))
  end

  defp mount_access_denied(socket, project) do
    {:ok,
     socket
     |> put_flash(
       :error,
       dgettext("projects", "You don't have permission to manage this project.")
     )
     |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
  end

  defp project_management_lost(socket, message) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
  end

  defp project_unavailable(socket) do
    workspace_slug = socket.assigns.project.workspace.slug

    {:noreply,
     socket
     |> put_flash(:error, dgettext("projects", "Project not found."))
     |> push_navigate(to: ~p"/workspaces/#{workspace_slug}")}
  end

  defp parse_positive_pg_bigint(value) when is_integer(value) and value > 0 and value <= @max_pg_bigint, do: {:ok, value}

  defp parse_positive_pg_bigint(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= @max_pg_bigint -> {:ok, id}
      _invalid -> :error
    end
  end

  defp parse_positive_pg_bigint(_value), do: :error
end

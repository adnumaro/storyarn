defmodule StoryarnWeb.ProjectSettingsLive.Members do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects

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
      workspace={@workspace}
      project={@project}
    >
      <:title>{dgettext("projects", "Members")}</:title>
      <:subtitle>{dgettext("projects", "Manage project members and invitations")}</:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsMembers"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-members"
        members={serialize_members(@members)}
        pending-invitations={serialize_invitations(@pending_invitations)}
        current-user-id={@current_scope.user.id}
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
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      members = Projects.list_project_members(project.id)
      pending_invitations = Projects.list_pending_invitations(project.id)

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:members, members)
        |> assign(:pending_invitations, pending_invitations)
        |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("projects", "You don't have permission to manage this project.")
       )
       |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
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

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_revoke_invitation(socket, id)
    end)
  end

  defp with_fresh_manage_members_authorization(socket, success_fn) do
    project_id = socket.assigns.project.id

    with {:ok, project, membership} <-
           Projects.get_project(socket.assigns.current_scope, project_id),
         true <- Projects.can?(membership.role, :manage_members) do
      socket
      |> assign(:project, project)
      |> assign(:membership, membership)
      |> success_fn.()
    else
      _reason ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )}
    end
  end
end

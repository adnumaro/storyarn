defmodule StoryarnWeb.SettingsLive.WorkspaceMembers do
  @moduledoc """
  LiveView for workspace team management settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Shared.Validations
  alias Storyarn.Workspaces

  @workspace_invite_roles ~w(admin member viewer)

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if Workspaces.can?(membership.role, :access_workspace_settings) do
      members = Workspaces.list_workspace_members(workspace.id)
      pending_invitations = Workspaces.list_pending_invitations(workspace.id)
      invite_changeset = invite_changeset(%{})

      {:ok,
       socket
       |> assign(:page_title, dgettext("workspaces", "Workspace Members"))
       |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/members")
       |> assign(:members, members)
       |> assign(:pending_invitations, pending_invitations)
       |> assign(:invite_form, to_form(invite_changeset, as: "invite"))}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("workspaces", "You don't have permission to manage this workspace.")
       )
       |> push_navigate(to: ~p"/users/settings")}
    end
  end

  defp invite_changeset(params) do
    types = %{email: :string, role: :string}
    defaults = %{email: "", role: "member"}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.update_change(:email, &String.trim/1)
    |> Ecto.Changeset.validate_required([:email, :role])
    |> Validations.validate_email_format()
    |> Ecto.Changeset.validate_inclusion(:role, @workspace_invite_roles)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsMembers"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-members"
        members={serialize_members(@members)}
        pending-invitations={serialize_invitations(@pending_invitations)}
        current-user-id={@current_scope.user.id}
        can-invite={Workspaces.can?(@membership.role, :manage_members)}
        can-manage={@membership.role == "owner"}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
  end

  @impl true
  def handle_event("change_role", %{"role" => role, "member-id" => member_id}, socket) do
    if socket.assigns.membership.role == "owner" do
      do_change_role(socket, member_id, role)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can change member roles.")
       )}
    end
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    if socket.assigns.membership.role == "owner" do
      do_remove_member(socket, id)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can remove members.")
       )}
    end
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_revoke_invitation(socket, id)
    end)
  end

  # Private helpers

  defp with_fresh_manage_members_authorization(socket, success_fn) do
    workspace_id = socket.assigns.workspace.id

    case Workspaces.authorize(socket.assigns.current_scope, workspace_id, :manage_members) do
      {:ok, workspace, membership} ->
        socket
        |> assign(:workspace, workspace)
        |> assign(:membership, membership)
        |> success_fn.()

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "You don't have permission to manage this workspace.")
         )}
    end
  end

  defp serialize_members(members) do
    Enum.map(members, fn member ->
      %{
        id: member.id,
        email: member.user.email,
        display_name: member.user.display_name,
        role: member.role
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

  defp do_send_invitation(socket, invite_params) do
    changeset = invite_changeset(invite_params)

    if changeset.valid? do
      workspace = socket.assigns.workspace
      user = socket.assigns.current_scope.user
      email = Ecto.Changeset.get_field(changeset, :email)
      role = Ecto.Changeset.get_field(changeset, :role)

      workspace
      |> Workspaces.create_invitation(user, email, role)
      |> handle_workspace_invitation_result(socket)
    else
      {:noreply,
       socket
       |> assign(:invite_form, to_form(%{changeset | action: :validate}, as: "invite"))
       |> put_flash(
         :error,
         dgettext("workspaces", "Enter a valid email address and role.")
       )}
    end
  end

  defp handle_workspace_invitation_result({:ok, _invitation}, socket) do
    pending_invitations = Workspaces.list_pending_invitations(socket.assigns.workspace.id)

    {:noreply,
     socket
     |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
     |> assign(:pending_invitations, pending_invitations)
     |> push_event("invitation_sent", %{})
     |> put_flash(:info, dgettext("workspaces", "Invitation queued for delivery."))}
  end

  defp handle_workspace_invitation_result({:error, :already_member}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("workspaces", "This person is already a member of this workspace.")
     )}
  end

  defp handle_workspace_invitation_result({:error, :already_invited}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("workspaces", "An invitation has already been sent to this email.")
     )}
  end

  defp handle_workspace_invitation_result({:error, :rate_limited}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("workspaces", "Too many invitations have been sent. Try again later.")
     )}
  end

  defp handle_workspace_invitation_result({:error, :limit_reached, %{resource: :members_per_workspace}}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member limit reached for your plan."))}
  end

  defp handle_workspace_invitation_result({:error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Could not send invitation."))}
  end

  defp do_revoke_invitation(socket, id) do
    workspace_id = socket.assigns.workspace.id

    with {invitation_id, ""} <- Integer.parse(to_string(id)),
         %{workspace_id: ^workspace_id} = invitation <- Workspaces.get_pending_invitation(invitation_id),
         {:ok, _invitation} <- Workspaces.revoke_invitation(invitation) do
      pending_invitations = Workspaces.list_pending_invitations(workspace_id)

      {:noreply,
       socket
       |> assign(:pending_invitations, pending_invitations)
       |> put_flash(:info, dgettext("workspaces", "Invitation revoked."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Invitation not found."))}
    end
  end

  defp do_change_role(socket, member_id, role) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == member_id))

    if member && member.role != "owner" do
      perform_role_update(socket, member, role)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}
    end
  end

  defp perform_role_update(socket, member, role) do
    case Workspaces.update_member_role(member, role) do
      {:ok, _} ->
        members = Workspaces.list_workspace_members(socket.assigns.workspace.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, dgettext("workspaces", "Role updated successfully."))

        {:noreply, socket}

      {:error, :cannot_change_owner_role} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Cannot change the owner's role."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Failed to update role."))}
    end
  end

  defp do_remove_member(socket, id) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == id))

    if member && member.role != "owner" do
      perform_member_removal(socket, member)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}
    end
  end

  defp perform_member_removal(socket, member) do
    case Workspaces.remove_member(member) do
      {:ok, _} ->
        members = Workspaces.list_workspace_members(socket.assigns.workspace.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, dgettext("workspaces", "Member removed."))

        {:noreply, socket}

      {:error, :cannot_remove_owner} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Cannot remove the workspace owner."))}
    end
  end
end

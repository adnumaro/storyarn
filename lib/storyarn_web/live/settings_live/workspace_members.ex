defmodule StoryarnWeb.SettingsLive.WorkspaceMembers do
  @moduledoc """
  LiveView for workspace team management settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Workspaces

  @workspace_invite_roles ~w(admin member viewer)
  @max_pg_bigint 9_223_372_036_854_775_807

  @impl true
  def mount(_params, _session, socket) do
    stale_workspace = socket.assigns.workspace

    if connected?(socket) do
      :ok = Workspaces.subscribe_workspace_ownership_changes(stale_workspace.id)
    end

    case Workspaces.authorize(
           socket.assigns.current_scope,
           stale_workspace.id,
           :access_workspace_settings
         ) do
      {:ok, workspace, membership} ->
        members = Workspaces.list_workspace_members(workspace.id)
        pending_invitations = Workspaces.list_pending_invitations(workspace.id)
        invite_changeset = invite_changeset(%{})

        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:page_title, dgettext("workspaces", "Workspace Members"))
         |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/members")
         |> assign(:members, members)
         |> assign(:pending_invitations, pending_invitations)
         |> assign(:invite_form, to_form(invite_changeset, as: "invite"))}

      {:error, _reason} ->
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
    |> Workspaces.validate_invitation_email_format()
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
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsMembers"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-members"
        members={serialize_members(@members)}
        pending-invitations={serialize_invitations(@pending_invitations)}
        current-user-id={Integer.to_string(@current_scope.user.id)}
        can-invite={Workspaces.can?(@membership.role, :manage_members)}
        can-manage={@workspace.owner_id == @current_scope.user.id}
        can-transfer-ownership={@workspace.owner_id == @current_scope.user.id}
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
    with_fresh_owner_authorization(
      socket,
      dgettext("workspaces", "Only the workspace owner can change member roles."),
      &do_change_role(&1, member_id, role)
    )
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    with_fresh_owner_authorization(
      socket,
      dgettext("workspaces", "Only the workspace owner can remove members."),
      &do_remove_member(&1, id)
    )
  end

  @impl true
  def handle_event("transfer_owner", %{"user-id" => user_id}, socket) do
    with_fresh_owner_authorization(
      socket,
      dgettext("workspaces", "Only the current workspace owner can transfer ownership."),
      &do_transfer_owner(&1, user_id)
    )
  end

  def handle_event("transfer_owner", _payload, socket) do
    ownership_transfer_error(
      socket,
      dgettext("workspaces", "Workspace ownership could not be transferred.")
    )
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    with_fresh_manage_members_authorization(socket, fn socket ->
      do_revoke_invitation(socket, id)
    end)
  end

  @impl true
  def handle_info(
        {:workspace_ownership_transferred, %{workspace_id: workspace_id}},
        %{assigns: %{workspace: %{id: workspace_id}}} = socket
      ) do
    case refresh_workspace_settings_access(socket) do
      {:ok, refreshed_socket} ->
        {:noreply, refresh_workspace_navigation(refreshed_socket)}

      {:error, _reason} ->
        workspace_settings_unavailable(socket)
    end
  end

  # Private helpers

  defp with_fresh_manage_members_authorization(socket, success_fn) do
    case refresh_workspace_settings_access(socket) do
      {:ok, refreshed_socket} ->
        if Workspaces.can?(refreshed_socket.assigns.membership.role, :manage_members) do
          success_fn.(refreshed_socket)
        else
          workspace_settings_unavailable(refreshed_socket)
        end

      {:error, _reason} ->
        workspace_settings_unavailable(socket)
    end
  end

  defp with_fresh_owner_authorization(socket, error_message, success_fn) do
    case refresh_workspace_settings_access(socket) do
      {:ok, refreshed_socket} ->
        if refreshed_socket.assigns.workspace.owner_id == refreshed_socket.assigns.current_scope.user.id do
          success_fn.(refreshed_socket)
        else
          {:noreply, put_flash(refreshed_socket, :error, error_message)}
        end

      {:error, _reason} ->
        workspace_settings_unavailable(socket)
    end
  end

  defp refresh_workspace_settings_access(socket) do
    workspace_id = socket.assigns.workspace.id

    case Workspaces.authorize(
           socket.assigns.current_scope,
           workspace_id,
           :access_workspace_settings
         ) do
      {:ok, workspace, membership} ->
        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:members, Workspaces.list_workspace_members(workspace.id))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refresh_workspace_navigation(socket) do
    workspace_data = Workspaces.list_workspaces(socket.assigns.current_scope)

    managed_slugs =
      workspace_data
      |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_settings))
      |> MapSet.new(& &1.workspace.slug)

    general_slugs =
      workspace_data
      |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_general_settings))
      |> MapSet.new(& &1.workspace.slug)

    socket
    |> assign(:workspaces, Enum.map(workspace_data, & &1.workspace))
    |> assign(:managed_workspace_slugs, managed_slugs)
    |> assign(:general_workspace_slugs, general_slugs)
  end

  defp workspace_settings_unavailable(socket) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       dgettext("workspaces", "You don't have permission to manage this workspace.")
     )
     |> push_navigate(to: ~p"/users/settings")}
  end

  defp workspace_ownership_invariant_error(socket) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       dgettext(
         "workspaces",
         "Storyarn could not verify the current workspace owner, so no changes were made. Contact support if the problem continues."
       )
     )
     |> push_navigate(to: ~p"/users/settings")}
  end

  defp serialize_members(members) do
    Enum.map(members, fn member ->
      %{
        id: member.id,
        user_id: Integer.to_string(member.user_id),
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
      email = Ecto.Changeset.get_field(changeset, :email)
      role = Ecto.Changeset.get_field(changeset, :role)

      socket.assigns.current_scope
      |> Workspaces.create_invitation(workspace.id, email, role)
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

  defp handle_workspace_invitation_result({:error, :unauthorized}, socket) do
    workspace_settings_unavailable(socket)
  end

  defp handle_workspace_invitation_result({:error, :ownership_invariant_violation}, socket) do
    workspace_ownership_invariant_error(socket)
  end

  defp handle_workspace_invitation_result({:error, :not_found}, socket) do
    workspace_settings_unavailable(socket)
  end

  defp handle_workspace_invitation_result({:error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Could not send invitation."))}
  end

  defp do_revoke_invitation(socket, id) do
    workspace_id = socket.assigns.workspace.id

    case parse_positive_pg_bigint(id) do
      {:ok, invitation_id} ->
        handle_workspace_invitation_revoke_result(
          Workspaces.revoke_invitation(
            socket.assigns.current_scope,
            workspace_id,
            invitation_id
          ),
          socket
        )

      :error ->
        workspace_invitation_not_found(socket)
    end
  end

  defp handle_workspace_invitation_revoke_result({:ok, _invitation}, socket) do
    pending_invitations = Workspaces.list_pending_invitations(socket.assigns.workspace.id)

    {:noreply,
     socket
     |> assign(:pending_invitations, pending_invitations)
     |> put_flash(:info, dgettext("workspaces", "Invitation revoked."))}
  end

  defp handle_workspace_invitation_revoke_result({:error, :unauthorized}, socket) do
    workspace_settings_unavailable(socket)
  end

  defp handle_workspace_invitation_revoke_result({:error, :ownership_invariant_violation}, socket) do
    workspace_ownership_invariant_error(socket)
  end

  defp handle_workspace_invitation_revoke_result({:error, :not_found}, socket) do
    case refresh_workspace_settings_access(socket) do
      {:ok, refreshed_socket} -> workspace_invitation_not_found(refreshed_socket)
      {:error, _reason} -> workspace_settings_unavailable(socket)
    end
  end

  defp handle_workspace_invitation_revoke_result({:error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Could not revoke invitation."))}
  end

  defp workspace_invitation_not_found(socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Invitation not found."))}
  end

  defp do_change_role(socket, member_id, role) do
    case parse_positive_pg_bigint(member_id) do
      {:ok, membership_id} -> perform_role_update(socket, membership_id, role)
      _ -> {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}
    end
  end

  defp perform_role_update(socket, membership_id, role) do
    case Workspaces.update_member_role(
           socket.assigns.current_scope,
           socket.assigns.workspace.id,
           membership_id,
           role
         ) do
      {:ok, _} ->
        members = Workspaces.list_workspace_members(socket.assigns.workspace.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, dgettext("workspaces", "Role updated successfully."))

        {:noreply, socket}

      {:error, :cannot_change_owner_role} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Cannot change the owner's role."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}

      {:error, :unauthorized} ->
        workspace_owner_action_error(
          socket,
          dgettext("workspaces", "Only the workspace owner can change member roles.")
        )

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Failed to update role."))}
    end
  end

  defp do_remove_member(socket, id) do
    case parse_positive_pg_bigint(id) do
      {:ok, membership_id} -> perform_member_removal(socket, membership_id)
      _ -> {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}
    end
  end

  defp perform_member_removal(socket, membership_id) do
    case Workspaces.remove_member(
           socket.assigns.current_scope,
           socket.assigns.workspace.id,
           membership_id
         ) do
      {:ok, _} ->
        members = Workspaces.list_workspace_members(socket.assigns.workspace.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, dgettext("workspaces", "Member removed."))

        {:noreply, socket}

      {:error, :cannot_remove_owner} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Cannot remove the workspace owner."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Member not found."))}

      {:error, :unauthorized} ->
        workspace_owner_action_error(
          socket,
          dgettext("workspaces", "Only the workspace owner can remove members.")
        )

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Failed to remove member."))}
    end
  end

  defp do_transfer_owner(socket, user_id) do
    with {:ok, target_user_id} <- parse_positive_pg_bigint(user_id),
         {:ok, _receipt} <-
           Workspaces.transfer_owner(
             socket.assigns.current_scope,
             socket.assigns.workspace.id,
             target_user_id
           ) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("workspaces", "Workspace ownership transferred."))
       |> push_navigate(to: ~p"/users/settings/workspaces/#{socket.assigns.workspace.slug}/members")}
    else
      {:error, :limit_reached, _details} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "workspaces",
             "The new owner has reached their workspace limit. They need to free capacity before receiving this workspace."
           )
         )}

      {:error, :target_not_member} ->
        ownership_transfer_error(socket, dgettext("workspaces", "That person is no longer a workspace member."))

      {:error, :ownership_invariant_violation} ->
        ownership_transfer_error(
          socket,
          dgettext(
            "workspaces",
            "Ownership could not be transferred because the workspace ownership data is inconsistent."
          )
        )

      {:error, :unauthorized} ->
        ownership_transfer_error(
          socket,
          dgettext("workspaces", "Only the current workspace owner can transfer ownership.")
        )

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
         |> push_navigate(to: ~p"/users/settings")}

      _reason ->
        ownership_transfer_error(socket, dgettext("workspaces", "Workspace ownership could not be transferred."))
    end
  end

  defp ownership_transfer_error(socket, message) do
    workspace_owner_action_error(socket, message)
  end

  defp workspace_owner_action_error(socket, message) do
    case refresh_workspace_settings_access(socket) do
      {:ok, refreshed_socket} ->
        {:noreply, put_flash(refreshed_socket, :error, message)}

      {:error, _reason} ->
        workspace_settings_unavailable(socket)
    end
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

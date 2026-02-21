defmodule StoryarnWeb.SettingsLive.WorkspaceMembers do
  @moduledoc """
  LiveView for workspace team management settings.
  """
  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.MemberComponents

  alias Storyarn.Workspaces

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, slug) do
      {:ok, workspace, membership} ->
        if membership.role in ["owner", "admin"] do
          members = Workspaces.list_workspace_members(workspace.id)
          pending_invitations = Workspaces.list_pending_invitations(workspace.id)
          invite_changeset = invite_changeset(%{})

          {:ok,
           socket
           |> assign(:page_title, dgettext("workspaces", "Workspace Members"))
           |> assign(:current_path, ~p"/users/settings/workspaces/#{slug}/members")
           |> assign(:workspace, workspace)
           |> assign(:membership, membership)
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

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("workspaces", "Workspace not found."))
         |> push_navigate(to: ~p"/users/settings")}
    end
  end

  defp invite_changeset(params) do
    types = %{email: :string, role: :string}
    defaults = %{email: "", role: "member"}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :role])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_path={@current_path}
    >
      <:title>{dgettext("workspaces", "Members")}</:title>
      <:subtitle>
        {dgettext("workspaces", "Manage team members for %{name}", name: @workspace.name)}
      </:subtitle>

      <div class="space-y-8">
        <%!-- Team Members Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("workspaces", "Team Members")}</h3>
          <div class="space-y-3">
            <.member_row
              :for={member <- @members}
              member={member}
              current_user_id={@current_scope.user.id}
              can_manage={@membership.role == "owner"}
              on_remove="remove_member"
              on_role_change="change_role"
              role_options={[
                {dgettext("workspaces", "Admin"), "admin"},
                {dgettext("workspaces", "Member"), "member"},
                {dgettext("workspaces", "Viewer"), "viewer"}
              ]}
            />
          </div>
        </section>

        <div class="divider" />

        <%!-- Invite Form --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("workspaces", "Invite a new member")}</h3>
          <.form for={@invite_form} id="invite-form" phx-submit="send_invitation">
            <div class="flex gap-3 items-end">
              <div class="flex-1">
                <.input
                  field={@invite_form[:email]}
                  type="email"
                  label={dgettext("workspaces", "Email address")}
                  placeholder="colleague@example.com"
                  required
                />
              </div>
              <div class="w-32">
                <.input
                  field={@invite_form[:role]}
                  type="select"
                  label={dgettext("workspaces", "Role")}
                  options={[
                    {dgettext("workspaces", "Admin"), "admin"},
                    {dgettext("workspaces", "Member"), "member"},
                    {dgettext("workspaces", "Viewer"), "viewer"}
                  ]}
                />
              </div>
              <.button variant="primary" class="mb-2">
                {dgettext("workspaces", "Send Invite")}
              </.button>
            </div>
          </.form>
        </section>

        <%!-- Pending Invitations Section --%>
        <section :if={@pending_invitations != []}>
          <div class="divider" />
          <h3 class="text-lg font-semibold mb-4">{dgettext("workspaces", "Pending Invitations")}</h3>
          <div class="space-y-2">
            <.invitation_row
              :for={invitation <- @pending_invitations}
              invitation={invitation}
              on_revoke="revoke_invitation"
            />
          </div>
        </section>
      </div>
    </Layouts.settings>
    """
  end

  @impl true
  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    case authorize(socket, :manage_workspace_members) do
      :ok ->
        do_send_invitation(socket, invite_params)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "You don't have permission to perform this action.")
         )}
    end
  end

  @impl true
  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    case authorize(socket, :manage_workspace_members) do
      :ok ->
        do_revoke_invitation(socket, id)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "You don't have permission to perform this action.")
         )}
    end
  end

  @impl true
  def handle_event("change_role", %{"role" => role, "member-id" => member_id}, socket) do
    if socket.assigns.membership.role != "owner" do
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can change member roles.")
       )}
    else
      do_change_role(socket, member_id, role)
    end
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    if socket.assigns.membership.role != "owner" do
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can remove members.")
       )}
    else
      do_remove_member(socket, id)
    end
  end

  # Private helpers

  defp do_send_invitation(socket, invite_params) do
    case Workspaces.create_invitation(
           socket.assigns.workspace,
           socket.assigns.current_scope.user,
           invite_params["email"],
           invite_params["role"]
         ) do
      {:ok, _invitation} ->
        pending_invitations = Workspaces.list_pending_invitations(socket.assigns.workspace.id)

        socket =
          socket
          |> assign(:pending_invitations, pending_invitations)
          |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
          |> put_flash(:info, dgettext("workspaces", "Invitation sent successfully."))

        {:noreply, socket}

      {:error, :already_member} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "This email is already a member of the workspace.")
         )}

      {:error, :already_invited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "An invitation has already been sent to this email.")
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "Too many invitations. Please try again later.")
         )}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("workspaces", "Failed to send invitation. Please try again.")
         )}
    end
  end

  defp do_revoke_invitation(socket, id) do
    invitation = Enum.find(socket.assigns.pending_invitations, &(to_string(&1.id) == id))

    if invitation do
      {:ok, _} = Workspaces.revoke_invitation(invitation)
      pending_invitations = Workspaces.list_pending_invitations(socket.assigns.workspace.id)

      socket =
        socket
        |> assign(:pending_invitations, pending_invitations)
        |> put_flash(:info, dgettext("workspaces", "Invitation revoked."))

      {:noreply, socket}
    else
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
        {:noreply,
         put_flash(socket, :error, dgettext("workspaces", "Cannot change the owner's role."))}

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
        {:noreply,
         put_flash(socket, :error, dgettext("workspaces", "Cannot remove the workspace owner."))}
    end
  end
end

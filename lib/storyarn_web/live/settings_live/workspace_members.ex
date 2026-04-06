defmodule StoryarnWeb.SettingsLive.WorkspaceMembers do
  @moduledoc """
  LiveView for workspace team management settings.
  """
  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  alias Storyarn.Accounts
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    case Workspaces.get_workspace_by_slug(scope, slug) do
      {:ok, workspace, membership} ->
        if membership.role in ["owner", "admin"] do
          members = Workspaces.list_workspace_members(workspace.id)
          invite_changeset = invite_changeset(%{})

          {:ok,
           socket
           |> assign(:page_title, dgettext("workspaces", "Workspace Members"))
           |> assign(:current_path, ~p"/users/settings/workspaces/#{slug}/members")
           |> assign(:workspace, workspace)
           |> assign(:membership, membership)
           |> assign(:members, members)
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
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="modules/settings/WorkspaceMembers"
        v-socket={@socket}
        id="workspace-settings-members"
        members={serialize_members(@members)}
        current-user-id={@current_scope.user.id}
        can-manage={@membership.role == "owner"}
      />
    </Layouts.settings>
    """
  end

  @impl true
  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    Authorize.with_authorization(socket, :manage_workspace_members, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
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

  @workspace_invite_roles ~w(admin member viewer)

  defp do_send_invitation(socket, invite_params) do
    role = invite_params["role"]

    if role in @workspace_invite_roles do
      workspace = socket.assigns.workspace
      user = socket.assigns.current_scope.user

      request_info = %{
        invitee_email: String.downcase(invite_params["email"]),
        requester_email: user.email,
        type: "workspace",
        entity_name: workspace.name,
        entity_id: workspace.id,
        role: role,
        locale: Gettext.get_locale(Storyarn.Gettext)
      }

      Accounts.notify_admin_invitation_request(request_info)

      socket =
        socket
        |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
        |> put_flash(
          :info,
          dgettext("workspaces", "Invitation request sent. An admin will review it shortly.")
        )

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Invalid role."))}
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

defmodule StoryarnWeb.ProjectLive.Settings do
  use StoryarnWeb, :live_view

  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mb-8">
        <.back navigate={~p"/projects/#{@project.id}"}>{gettext("Back to project")}</.back>
      </div>

      <div class="text-center mb-8">
        <.header>
          {gettext("Project Settings")}
          <:subtitle>
            {gettext("Manage your project details and team members")}
          </:subtitle>
        </.header>
      </div>

      <div class="space-y-8 max-w-2xl mx-auto">
        <%!-- Project Details Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{gettext("Project Details")}</h3>
          <.form
            for={@project_form}
            id="project-form"
            phx-submit="update_project"
            phx-change="validate_project"
          >
            <.input
              field={@project_form[:name]}
              type="text"
              label={gettext("Project Name")}
              required
            />
            <.input
              field={@project_form[:description]}
              type="textarea"
              label={gettext("Description")}
              rows={3}
            />
            <.button variant="primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save Changes")}
            </.button>
          </.form>
        </section>

        <div class="divider" />

        <%!-- Team Members Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{gettext("Team Members")}</h3>
          <div class="space-y-3 mb-6">
            <.member_row
              :for={member <- @members}
              member={member}
              current_user_id={@current_scope.user.id}
            />
          </div>

          <%!-- Invite Form --%>
          <div class="card bg-base-200 p-4">
            <h4 class="font-medium mb-3">{gettext("Invite a new member")}</h4>
            <.form for={@invite_form} id="invite-form" phx-submit="send_invitation">
              <div class="flex gap-3 items-end">
                <div class="flex-1">
                  <.input
                    field={@invite_form[:email]}
                    type="email"
                    label={gettext("Email address")}
                    placeholder="colleague@example.com"
                    required
                  />
                </div>
                <div class="w-32">
                  <.input
                    field={@invite_form[:role]}
                    type="select"
                    label={gettext("Role")}
                    options={[
                      {gettext("Editor"), "editor"},
                      {gettext("Viewer"), "viewer"}
                    ]}
                  />
                </div>
                <.button variant="primary" class="mb-2">
                  {gettext("Send Invite")}
                </.button>
              </div>
            </.form>
          </div>
        </section>

        <%!-- Pending Invitations Section --%>
        <section :if={@pending_invitations != []}>
          <h3 class="text-lg font-semibold mb-4">{gettext("Pending Invitations")}</h3>
          <div class="space-y-2">
            <.invitation_row :for={invitation <- @pending_invitations} invitation={invitation} />
          </div>
        </section>

        <div class="divider" />

        <%!-- Danger Zone --%>
        <section>
          <h3 class="text-lg font-semibold mb-4 text-error">{gettext("Danger Zone")}</h3>
          <div class="card bg-error/10 border border-error/30 p-4">
            <p class="text-sm mb-4">
              {gettext("Once you delete a project, there is no going back. Please be certain.")}
            </p>
            <.button
              variant="error"
              phx-click="delete_project"
              data-confirm={
                gettext("Are you sure you want to delete this project? This action cannot be undone.")
              }
            >
              {gettext("Delete Project")}
            </.button>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :member, :map, required: true
  attr :current_user_id, :integer, required: true

  defp member_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-3 rounded-lg border border-base-300">
      <div class="flex items-center gap-3">
        <div class="avatar placeholder">
          <div class="bg-neutral text-neutral-content rounded-full size-10">
            <span class="text-sm">{get_initials(@member.user)}</span>
          </div>
        </div>
        <div>
          <p class="font-medium">{@member.user.display_name || @member.user.email}</p>
          <p :if={@member.user.display_name} class="text-sm text-base-content/70">
            {@member.user.email}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <.role_badge role={@member.role} />
        <%= if @member.role != "owner" and @member.user.id != @current_user_id do %>
          <.link
            phx-click="remove_member"
            phx-value-id={@member.id}
            class="btn btn-ghost btn-sm text-error"
            data-confirm={gettext("Are you sure you want to remove this member?")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  attr :invitation, :map, required: true

  defp invitation_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-3 rounded-lg border border-base-300 bg-base-200/50">
      <div>
        <p class="font-medium">{@invitation.email}</p>
        <p class="text-xs text-base-content/50">
          {gettext("Invited by")} {@invitation.invited_by.display_name || @invitation.invited_by.email}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <.role_badge role={@invitation.role} />
        <span class="badge badge-ghost badge-sm">{gettext("Pending")}</span>
        <.link
          phx-click="revoke_invitation"
          phx-value-id={@invitation.id}
          class="btn btn-ghost btn-sm text-error"
          data-confirm={gettext("Are you sure you want to revoke this invitation?")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end

  defp get_initials(user) do
    name = user.display_name || user.email

    name
    |> String.split(~r/[@\s]/)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.authorize(socket.assigns.current_scope, id, :manage_project) do
      {:ok, project, _membership} ->
        members = Projects.list_project_members(id)
        pending_invitations = Projects.list_pending_invitations(id)

        project_changeset = Projects.change_project(project)
        invite_changeset = invite_changeset(%{})

        socket =
          socket
          |> assign(:project, project)
          |> assign(:members, members)
          |> assign(:pending_invitations, pending_invitations)
          |> assign(:project_form, to_form(project_changeset))
          |> assign(:invite_form, to_form(invite_changeset, as: "invite"))

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/projects")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have permission to manage this project."))
         |> redirect(to: ~p"/projects")}
    end
  end

  defp invite_changeset(params) do
    types = %{email: :string, role: :string}
    defaults = %{email: "", role: "editor"}

    {defaults, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :role])
  end

  @impl true
  def handle_event("validate_project", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(changeset))}
  end

  def handle_event("update_project", %{"project" => project_params}, socket) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        project_changeset = Projects.change_project(project)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:project_form, to_form(project_changeset))
          |> put_flash(:info, gettext("Project updated successfully."))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :project_form, to_form(changeset))}
    end
  end

  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    case Projects.create_invitation(
           socket.assigns.project,
           socket.assigns.current_scope.user,
           invite_params["email"],
           invite_params["role"]
         ) do
      {:ok, _invitation} ->
        pending_invitations = Projects.list_pending_invitations(socket.assigns.project.id)

        socket =
          socket
          |> assign(:pending_invitations, pending_invitations)
          |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
          |> put_flash(:info, gettext("Invitation sent successfully."))

        {:noreply, socket}

      {:error, :already_member} ->
        {:noreply,
         put_flash(socket, :error, gettext("This email is already a member of the project."))}

      {:error, :already_invited} ->
        {:noreply,
         put_flash(socket, :error, gettext("An invitation has already been sent to this email."))}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many invitations. Please try again later."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("Failed to send invitation. Please try again."))}
    end
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    invitation = Enum.find(socket.assigns.pending_invitations, &(to_string(&1.id) == id))

    if invitation do
      {:ok, _} = Projects.revoke_invitation(invitation)
      pending_invitations = Projects.list_pending_invitations(socket.assigns.project.id)

      socket =
        socket
        |> assign(:pending_invitations, pending_invitations)
        |> put_flash(:info, gettext("Invitation revoked."))

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, gettext("Invitation not found."))}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    member = Enum.find(socket.assigns.members, &(to_string(&1.id) == id))

    if member && member.role != "owner" do
      case Projects.remove_member(member) do
        {:ok, _} ->
          members = Projects.list_project_members(socket.assigns.project.id)

          socket =
            socket
            |> assign(:members, members)
            |> put_flash(:info, gettext("Member removed."))

          {:noreply, socket}

        {:error, :cannot_remove_owner} ->
          {:noreply, put_flash(socket, :error, gettext("Cannot remove the project owner."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Member not found."))}
    end
  end

  def handle_event("delete_project", _params, socket) do
    case Projects.delete_project(socket.assigns.project) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, gettext("Project deleted."))
          |> push_navigate(to: ~p"/projects")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete project."))}
    end
  end
end

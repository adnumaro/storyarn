defmodule StoryarnWeb.ProjectSettingsLive.Members do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
      back_label={dgettext("projects", "Back to project")}
      sidebar_sections={project_settings_sections(@workspace, @project)}
    >
      <:title>{dgettext("projects", "Members")}</:title>
      <:subtitle>{dgettext("projects", "Manage project members and invitations")}</:subtitle>

      <.vue
        v-component="modules/project-settings/Members"
        v-socket={@socket}
        id="project-settings-members"
        members={serialize_members(@members)}
        current-user-id={@current_scope.user.id}
      />
    </Layouts.settings>
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

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      members = Projects.list_project_members(project.id)

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:members, members)
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
    Authorize.with_authorization(socket, :manage_members, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :manage_members, fn socket ->
      do_remove_member(socket, id)
    end)
  end
end

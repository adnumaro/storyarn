defmodule StoryarnWeb.ProjectLive.Settings do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.MemberComponents
  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      sheets_tree={@sheets_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}
    >
      <div class="text-center mb-8">
        <.header>
          {dgettext("projects", "Project Settings")}
          <:subtitle>
            {dgettext("projects", "Manage your project details and team members")}
          </:subtitle>
        </.header>
      </div>

      <div class="space-y-8 max-w-2xl mx-auto">
        <%!-- Project Details Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Project Details")}</h3>
          <.form
            for={@project_form}
            id="project-form"
            phx-submit="update_project"
            phx-change="validate_project"
          >
            <.input
              field={@project_form[:name]}
              type="text"
              label={dgettext("projects", "Project Name")}
              required
            />
            <.input
              field={@project_form[:description]}
              type="textarea"
              label={dgettext("projects", "Description")}
              rows={3}
            />
            <.button variant="primary" phx-disable-with={dgettext("projects", "Saving...")}>
              {dgettext("projects", "Save Changes")}
            </.button>
          </.form>
        </section>

        <div class="divider" />

        <%!-- Team Members Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Team Members")}</h3>
          <div class="space-y-3 mb-6">
            <.member_row
              :for={member <- @members}
              member={member}
              current_user_id={@current_scope.user.id}
              can_manage={true}
              on_remove="remove_member"
            />
          </div>

          <%!-- Invite Form --%>
          <div class="card bg-base-200 p-4">
            <h4 class="font-medium mb-3">{dgettext("projects", "Invite a new member")}</h4>
            <.form for={@invite_form} id="invite-form" phx-submit="send_invitation">
              <div class="flex gap-3 items-end">
                <div class="flex-1">
                  <.input
                    field={@invite_form[:email]}
                    type="email"
                    label={dgettext("projects", "Email address")}
                    placeholder="colleague@example.com"
                    required
                  />
                </div>
                <div class="w-32">
                  <.input
                    field={@invite_form[:role]}
                    type="select"
                    label={dgettext("projects", "Role")}
                    options={[
                      {dgettext("projects", "Editor"), "editor"},
                      {dgettext("projects", "Viewer"), "viewer"}
                    ]}
                  />
                </div>
                <.button variant="primary" class="mb-2">
                  {dgettext("projects", "Send Invite")}
                </.button>
              </div>
            </.form>
          </div>
        </section>

        <%!-- Pending Invitations Section --%>
        <section :if={@pending_invitations != []}>
          <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Pending Invitations")}</h3>
          <div class="space-y-2">
            <.invitation_row
              :for={invitation <- @pending_invitations}
              invitation={invitation}
              on_revoke="revoke_invitation"
            />
          </div>
        </section>

        <div class="divider" />

        <%!-- Localization Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Localization")}</h3>

          <%!-- DeepL Configuration --%>
          <div class="card bg-base-200 p-4">
            <h4 class="font-medium mb-3">{dgettext("projects", "Translation Provider (DeepL)")}</h4>

            <.form
              for={@provider_form}
              id="provider-config-form"
              phx-submit="save_provider_config"
            >
              <.input
                field={@provider_form[:api_key_encrypted]}
                type="password"
                label={dgettext("projects", "API Key")}
                placeholder={if @has_api_key, do: "••••••••", else: ""}
              />
              <.input
                field={@provider_form[:api_endpoint]}
                type="select"
                label={dgettext("projects", "API Tier")}
                options={[
                  {dgettext("projects", "Free (api-free.deepl.com)"), "https://api-free.deepl.com"},
                  {dgettext("projects", "Pro (api.deepl.com)"), "https://api.deepl.com"}
                ]}
              />
              <div class="flex items-center gap-3 mt-3">
                <.button variant="primary" phx-disable-with={dgettext("projects", "Saving...")}>
                  {dgettext("projects", "Save")}
                </.button>
                <.button
                  :if={@has_api_key}
                  type="button"
                  phx-click="test_provider_connection"
                  phx-disable-with={dgettext("projects", "Testing...")}
                >
                  {dgettext("projects", "Test Connection")}
                </.button>
              </div>
            </.form>

            <div :if={@provider_usage} class="mt-3 text-sm opacity-70">
              {dgettext("projects", "Usage: %{used} / %{limit} characters",
                used: format_number(@provider_usage.character_count),
                limit: format_number(@provider_usage.character_limit)
              )}
            </div>
          </div>
        </section>

        <div class="divider" />

        <%!-- Maintenance Section --%>
        <section>
          <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Maintenance")}</h3>
          <div class="card bg-base-200 p-4">
            <p class="text-sm mb-3">
              {dgettext("projects",
                "If you renamed sheet shortcuts or variable names, flow nodes may reference old names. Use this to repair them."
              )}
            </p>
            <.button phx-click={show_modal("repair-refs-confirm")}>
              {dgettext("projects", "Repair variable references")}
            </.button>
          </div>
        </section>

        <div class="divider" />

        <%!-- Danger Zone --%>
        <section>
          <h3 class="text-lg font-semibold mb-4 text-error">{dgettext("projects", "Danger Zone")}</h3>
          <div class="card bg-error/10 border border-error/30 p-4">
            <p class="text-sm mb-4">
              {dgettext("projects", "Once you delete a project, there is no going back. Please be certain.")}
            </p>
            <.button variant="error" phx-click={show_modal("delete-project-confirm")}>
              {dgettext("projects", "Delete Project")}
            </.button>
          </div>
        </section>
      </div>

      <.confirm_modal
        id="repair-refs-confirm"
        title={dgettext("projects", "Repair variable references?")}
        message={dgettext("projects", "This will update node data across the entire project.")}
        confirm_text={dgettext("projects", "Continue")}
        on_confirm={JS.push("repair_variable_references")}
      />

      <.confirm_modal
        id="delete-project-confirm"
        title={dgettext("projects", "Delete project?")}
        message={dgettext("projects", "This action cannot be undone.")}
        confirm_text={dgettext("projects", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("delete_project")}
      />
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        if Projects.ProjectMembership.can?(membership.role, :manage_project) do
          project = Repo.preload(project, :workspace)
          members = Projects.list_project_members(project.id)
          pending_invitations = Projects.list_pending_invitations(project.id)
          sheets_tree = Sheets.list_sheets_tree(project.id)

          project_changeset = Projects.change_project(project)
          provider_config = get_provider_config(project.id)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(:sheets_tree, sheets_tree)
            |> assign(:members, members)
            |> assign(:pending_invitations, pending_invitations)
            |> assign(:project_form, to_form(project_changeset))
            |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
            |> assign(:provider_form, to_form(provider_changeset(provider_config), as: "provider"))
            |> assign(:has_api_key, provider_config != nil && provider_config.api_key_encrypted != nil)
            |> assign(:provider_usage, nil)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, dgettext("projects", "You don't have permission to manage this project."))
           |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
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
    case authorize(socket, :manage_project) do
      :ok ->
        case Projects.update_project(socket.assigns.project, project_params) do
          {:ok, project} ->
            project_changeset = Projects.change_project(project)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:project_form, to_form(project_changeset))
              |> put_flash(:info, dgettext("projects", "Project updated successfully."))

            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :project_form, to_form(changeset))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    case authorize(socket, :manage_members) do
      :ok -> do_send_invitation(socket, invite_params)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    case authorize(socket, :manage_members) do
      :ok -> do_revoke_invitation(socket, id)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    case authorize(socket, :manage_members) do
      :ok -> do_remove_member(socket, id)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("repair_variable_references", _params, socket) do
    case authorize(socket, :manage_project) do
      :ok -> do_repair_variable_references(socket)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_project", _params, socket) do
    case authorize(socket, :manage_project) do
      :ok ->
        workspace = socket.assigns.workspace

        case Projects.delete_project(socket.assigns.project) do
          {:ok, _} ->
            socket =
              socket
              |> put_flash(:info, dgettext("projects", "Project deleted."))
              |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete project."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("save_provider_config", %{"provider" => params}, socket) do
    case authorize(socket, :manage_project) do
      :ok -> do_save_provider_config(socket, params)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("test_provider_connection", _params, socket) do
    case authorize(socket, :manage_project) do
      :ok -> do_test_provider_connection(socket)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("projects", "You don't have permission to perform this action."))}
    end
  end
end

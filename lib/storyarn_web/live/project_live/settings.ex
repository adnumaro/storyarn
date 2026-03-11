defmodule StoryarnWeb.ProjectLive.Settings do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.MemberComponents
  import StoryarnWeb.Components.ColorPicker
  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects

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
      <:title>{section_title(@live_action)}</:title>
      <:subtitle>{section_subtitle(@live_action)}</:subtitle>

      <.section_content
        live_action={@live_action}
        project_form={@project_form}
        members={@members}
        current_scope={@current_scope}
        invite_form={@invite_form}
        theme_primary={@theme_primary}
        theme_accent={@theme_accent}
        has_custom_theme={@has_custom_theme}
        provider_form={@provider_form}
        has_api_key={@has_api_key}
        provider_usage={@provider_usage}
      />

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
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Section content
  # ===========================================================================

  defp section_content(%{live_action: :general} = assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Project Details --%>
      <section>
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

      <%!-- Theme --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Project Theme")}</h3>
        <div class="card bg-base-200 p-4">
          <div class="flex gap-8 items-start">
            <div>
              <label class="text-sm font-medium mb-2 block">
                {dgettext("projects", "Primary")}
              </label>
              <div class="flex items-center gap-3">
                <.color_picker
                  id="theme-primary"
                  color={@theme_primary}
                  event="update_theme_primary"
                />
                <code class="text-xs opacity-60">{@theme_primary}</code>
              </div>
            </div>
            <div>
              <label class="text-sm font-medium mb-2 block">
                {dgettext("projects", "Accent")}
              </label>
              <div class="flex items-center gap-3">
                <.color_picker
                  id="theme-accent"
                  color={@theme_accent}
                  event="update_theme_accent"
                />
                <code class="text-xs opacity-60">{@theme_accent}</code>
              </div>
            </div>
          </div>
          <div class="flex gap-3 mt-4">
            <.button variant="primary" phx-click="save_theme">
              {dgettext("projects", "Apply Theme")}
            </.button>
            <.button :if={@has_custom_theme} phx-click="reset_theme">
              {dgettext("projects", "Reset to Default")}
            </.button>
          </div>
        </div>
      </section>

      <div class="divider" />

      <%!-- Maintenance --%>
      <section>
        <h3 class="text-lg font-semibold mb-4">{dgettext("projects", "Maintenance")}</h3>
        <div class="card bg-base-200 p-4">
          <p class="text-sm mb-3">
            {dgettext(
              "projects",
              "If you renamed sheet shortcuts or variable names, flow nodes may reference old names. Use this to repair them."
            )}
          </p>
          <.button variant="primary" phx-click={show_modal("repair-refs-confirm")}>
            {dgettext("projects", "Repair variable references")}
          </.button>
        </div>
      </section>

      <div class="divider" />

      <%!-- Danger Zone --%>
      <section>
        <h3 class="text-lg font-semibold mb-4 text-error">
          {dgettext("projects", "Danger Zone")}
        </h3>
        <div class="card bg-error/10 border border-error/30 p-4">
          <p class="text-sm mb-4">
            {dgettext(
              "projects",
              "Once you delete a project, there is no going back. Please be certain."
            )}
          </p>
          <.button variant="error" phx-click={show_modal("delete-project-confirm")}>
            {dgettext("projects", "Delete Project")}
          </.button>
        </div>
      </section>
    </div>
    """
  end

  defp section_content(%{live_action: :localization} = assigns) do
    ~H"""
    <div>
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
    </div>
    """
  end

  defp section_content(%{live_action: :members} = assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="space-y-3">
        <.member_row
          :for={member <- @members}
          member={member}
          current_user_id={@current_scope.user.id}
          can_manage={true}
          on_remove="remove_member"
        />
      </div>

      <div class="card bg-base-200 p-4">
        <h4 class="font-medium mb-3">{dgettext("projects", "Request member invitation")}</h4>
        <p class="text-sm opacity-70 mb-3">
          {dgettext("projects", "Invitation requests are reviewed by an admin before being sent.")}
        </p>
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
          </div>
          <.button variant="primary">
            {dgettext("projects", "Request Invitation")}
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

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
        if Projects.can?(membership.role, :manage_project) do
          members = Projects.list_project_members(project.id)

          project_changeset = Projects.change_project(project)
          provider_config = get_provider_config(project.id)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(:members, members)
            |> assign(:project_form, to_form(project_changeset))
            |> assign(:invite_form, to_form(invite_changeset(%{}), as: "invite"))
            |> assign(
              :provider_form,
              to_form(provider_changeset(provider_config), as: "provider")
            )
            |> assign(
              :has_api_key,
              provider_config != nil && provider_config.api_key_encrypted != nil
            )
            |> assign(:provider_usage, nil)
            |> assign_theme(project)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             dgettext("projects", "You don't have permission to manage this project.")
           )
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
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    {:noreply,
     socket
     |> assign(:page_title, dgettext("projects", "Project Settings"))
     |> assign(:current_path, current_path)}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("validate_project", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(changeset))}
  end

  def handle_event("update_project", %{"project" => project_params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
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
    end)
  end

  def handle_event("send_invitation", %{"invite" => invite_params}, socket) do
    with_authorization(socket, :manage_members, fn socket ->
      do_send_invitation(socket, invite_params)
    end)
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    with_authorization(socket, :manage_members, fn socket ->
      do_remove_member(socket, id)
    end)
  end

  def handle_event("repair_variable_references", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_repair_variable_references(socket)
    end)
  end

  def handle_event("delete_project", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      workspace = socket.assigns.workspace

      case Projects.delete_project(socket.assigns.project) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("projects", "Project deleted."))
           |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete project."))}
      end
    end)
  end

  def handle_event("save_provider_config", %{"provider" => params}, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_save_provider_config(socket, params)
    end)
  end

  def handle_event("test_provider_connection", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      do_test_provider_connection(socket)
    end)
  end

  def handle_event("update_theme_primary", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_primary, color)}
  end

  def handle_event("update_theme_accent", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_accent, color)}
  end

  def handle_event("save_theme", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      project = socket.assigns.project
      settings = project.settings || %{}

      new_settings =
        Map.put(settings, "theme", %{
          "primary" => socket.assigns.theme_primary,
          "accent" => socket.assigns.theme_accent
        })

      case Projects.update_project(project, %{settings: new_settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(:has_custom_theme, true)
           |> put_flash(:info, dgettext("projects", "Theme saved."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save theme."))}
      end
    end)
  end

  def handle_event("reset_theme", _params, socket) do
    with_authorization(socket, :manage_project, fn socket ->
      project = socket.assigns.project
      settings = Map.delete(project.settings || %{}, "theme")

      case Projects.update_project(project, %{settings: settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign_theme(project)
           |> put_flash(:info, dgettext("projects", "Theme reset to default."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to reset theme."))}
      end
    end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp section_title(:general), do: dgettext("projects", "General")
  defp section_title(:localization), do: dgettext("projects", "Localization")
  defp section_title(:members), do: dgettext("projects", "Members")

  defp section_subtitle(:general),
    do: dgettext("projects", "Project details, theme, and maintenance")

  defp section_subtitle(:localization),
    do: dgettext("projects", "Translation provider configuration")

  defp section_subtitle(:members),
    do: dgettext("projects", "Manage project members and invitations")

  defp project_settings_sections(workspace, project) do
    base = ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/settings"

    [
      %{
        label: dgettext("projects", "General"),
        items: [
          %{label: dgettext("projects", "General"), path: base, icon: "settings"}
        ]
      },
      %{
        label: dgettext("projects", "Integrations"),
        items: [
          %{
            label: dgettext("projects", "Localization"),
            path: "#{base}/localization",
            icon: "languages"
          }
        ]
      },
      %{
        label: dgettext("projects", "Administration"),
        items: [
          %{label: dgettext("projects", "Members"), path: "#{base}/members", icon: "users"},
          %{
            label: dgettext("projects", "Import & Export"),
            path: "#{base}/export-import",
            icon: "package"
          }
        ]
      }
    ]
  end

  defp assign_theme(socket, project) do
    case Storyarn.Projects.Project.theme_colors(project) do
      %{primary: p, accent: a} ->
        socket
        |> assign(:theme_primary, p)
        |> assign(:theme_accent, a)
        |> assign(:has_custom_theme, true)

      nil ->
        socket
        |> assign(:theme_primary, "#00D4CC")
        |> assign(:theme_accent, "#E8922F")
        |> assign(:has_custom_theme, false)
    end
  end
end

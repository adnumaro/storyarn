defmodule StoryarnWeb.ProjectSettingsLive.General do
  @moduledoc """
  Project › General: details, source language, theme colors, maintenance and
  the danger zone. The owner edits; workspace members who may publish
  templates can open the page and see it locked.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.SaveStatusTimer
  alias StoryarnWeb.LanguagePickerOption

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
        v-component="live/project/settings/ProjectSettingsGeneral"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-general"
        project-details={serialize_project_details(@project)}
        project-metrics-options={Projects.project_classification_options()}
        source-language={serialize_source_language(@source_language)}
        source-language-options={source_language_options()}
        theme-primary={@theme_primary}
        theme-accent={@theme_accent}
        has-custom-theme={@has_custom_theme}
        can-manage-project={can_manage_project?(@current_scope, @project, @membership)}
        save-status={Atom.to_string(@save_status)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_project_details(project) do
    %{
      name: project.name,
      description: project.description || "",
      type: project.project_type || "",
      subtype: project.project_subtype || "",
      typeOther: project.project_type_other || ""
    }
  end

  defp serialize_source_language(nil), do: nil

  defp serialize_source_language(lang) do
    lang.locale_code
    |> LanguagePickerOption.from_code(label: lang.name || Localization.language_name(lang.locale_code))
    |> Map.put(:localeCode, lang.locale_code)
  end

  defp source_language_options do
    Enum.map(Localization.language_options_for_select(), fn {_label, code} ->
      LanguagePickerOption.from_code(code, label: Localization.language_name(code))
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

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.Live.Shared.ProjectChromeHelpers.shell_topic(stale_project.id)
      )
    end

    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, stale_project.id),
         true <- can_open_general_settings?(socket.assigns.current_scope, project, membership) do
      {:ok, source_language} = Localization.ensure_source_language(project)
      project_changeset = Projects.change_project(project)

      socket =
        socket
        |> assign(:project, project)
        |> assign(:workspace, project.workspace)
        |> assign(:membership, membership)
        |> assign(:current_workspace, project.workspace)
        |> assign(:source_language, source_language)
        |> assign(:project_form, to_form(project_changeset))
        |> assign(:save_status, :idle)
        |> assign_theme(project)

      {:ok, socket}
    else
      _lost_access ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> redirect(to: ~p"/workspaces/#{stale_project.workspace.slug}/projects/#{stale_project.slug}")}
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
  def handle_event("validate_project", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_form, to_form(changeset))}
  end

  def handle_event("update_project", %{"project" => project_params}, socket) do
    with_project_owner_authorization(socket, fn socket ->
      case Projects.update_project(
             socket.assigns.current_scope,
             socket.assigns.project.id,
             project_params
           ) do
        {:ok, project} ->
          project_changeset = Projects.change_project(project)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:project_form, to_form(project_changeset))
            |> SaveStatusTimer.mark_saved()

          {:noreply, socket}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :project_form, to_form(changeset))}

        {:error, :ownership_invariant_violation} ->
          project_ownership_invariant_error(socket)

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Only the current project owner can update this project.")
           )}
      end
    end)
  end

  def handle_event("change_source_language", %{"locale_code" => locale_code} = params, socket) do
    with_project_owner_authorization(socket, fn socket ->
      opts = if reset_translations?(params), do: [reset_translations: true], else: []

      case Localization.change_source_language(
             socket.assigns.current_scope,
             socket.assigns.project,
             locale_code,
             opts
           ) do
        {:ok, source_language} ->
          {:noreply,
           socket
           |> assign(:source_language, source_language)
           |> put_flash(:info, dgettext("projects", "Source language updated."))}

        {:error, :ownership_invariant_violation} ->
          project_ownership_invariant_error(socket)

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Could not update the source language.")
           )}
      end
    end)
  end

  def handle_event("repair_variable_references", _params, socket) do
    with_project_owner_authorization(socket, fn socket ->
      do_repair_variable_references(socket)
    end)
  end

  def handle_event("delete_project", _params, socket) do
    with_project_owner_authorization(socket, fn socket ->
      workspace = socket.assigns.workspace

      case Projects.delete_project(socket.assigns.current_scope, socket.assigns.project.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("projects", "Project deleted."))
           |> push_navigate(to: ~p"/workspaces/#{workspace.slug}")}

        {:error, :ownership_invariant_violation} ->
          project_ownership_invariant_error(socket)

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete project."))}
      end
    end)
  end

  def handle_event("update_theme_primary", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_primary, color)}
  end

  def handle_event("update_theme_accent", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_accent, color)}
  end

  def handle_event("save_theme", _params, socket) do
    with_project_owner_authorization(socket, fn socket ->
      do_save_theme(socket)
    end)
  end

  def handle_event("reset_theme", _params, socket) do
    with_project_owner_authorization(socket, fn socket ->
      project = socket.assigns.project
      settings = Map.delete(project.settings || %{}, "theme")

      case Projects.update_project(socket.assigns.current_scope, project.id, %{settings: settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign_theme(project)
           |> put_flash(:info, dgettext("projects", "Theme reset to default."))}

        {:error, :ownership_invariant_violation} ->
          project_ownership_invariant_error(socket)

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to reset theme."))}
      end
    end)
  end

  @impl true
  def handle_info({:reset_save_status, token}, socket) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply, assign(socket, :save_status, :idle)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:project_restored, _restore_id}, socket) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, socket.assigns.project.id),
         true <- can_open_general_settings?(socket.assigns.current_scope, project, membership) do
      {:noreply,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(:project_form, to_form(Projects.change_project(project)))
       |> assign(:source_language, Localization.get_source_language(project.id))
       |> assign_theme(project)}
    else
      _reason ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> push_navigate(to: ~p"/workspaces/#{socket.assigns.workspace.slug}")}
    end
  end

  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- can_open_general_settings?(socket.assigns.current_scope, project, membership) do
      {:noreply,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(:project_form, to_form(Projects.change_project(project)))
       |> assign(:source_language, Localization.get_source_language(project.id))
       |> assign_theme(project)}
    else
      _lost_access ->
        project = socket.assigns.project

        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # ===========================================================================
  # Private
  # ===========================================================================

  defp can_open_general_settings?(scope, project, membership) do
    can_manage_project?(scope, project, membership) or
      Projects.can_publish_project_template?(scope, project)
  end

  defp can_manage_project?(scope, project, membership) do
    project.owner_id == scope.user.id and Projects.can?(membership.role, :manage_project)
  end

  defp with_project_owner_authorization(socket, success_fn) do
    Authorize.with_authorization(
      socket,
      :manage_project,
      success_fn,
      fn
        socket, :ownership_invariant_violation ->
          project_ownership_invariant_error(socket)

        socket, _reason ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("You don't have permission to perform this action.")
           )}
      end
    )
  end

  defp project_ownership_invariant_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext(
         "projects",
         "This action could not be completed because project ownership is inconsistent. Contact support before retrying."
       )
     )}
  end

  defp reset_translations?(%{"reset_translations" => value}) when value in [true, "true"], do: true
  defp reset_translations?(_params), do: false

  defp do_save_theme(socket) do
    alias StoryarnWeb.Helpers.ColorUtils

    primary = socket.assigns.theme_primary
    accent = socket.assigns.theme_accent

    if ColorUtils.valid_hex?(primary) and ColorUtils.valid_hex?(accent) do
      project = socket.assigns.project
      settings = project.settings || %{}

      new_settings =
        Map.put(settings, "theme", %{
          "primary" => primary,
          "accent" => accent
        })

      case Projects.update_project(socket.assigns.current_scope, project.id, %{settings: new_settings}) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(:has_custom_theme, true)
           |> put_flash(:info, dgettext("projects", "Theme saved."))}

        {:error, :ownership_invariant_violation} ->
          project_ownership_invariant_error(socket)

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save theme."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Invalid color format. Use #RRGGBB."))}
    end
  end

  defp assign_theme(socket, project) do
    case Projects.project_theme_colors(project) do
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

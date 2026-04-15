defmodule StoryarnWeb.ProjectSettingsLive.General do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Localization
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
      <:title>{dgettext("projects", "General")}</:title>
      <:subtitle>{dgettext("projects", "Project details, theme, and maintenance")}</:subtitle>

      <.vue
        v-component="modules/project-settings/General"
        v-socket={@socket}
        id="project-settings-general"
        project-name={@project.name}
        project-description={@project.description || ""}
        source-language={serialize_source_language(@source_language)}
        source-language-name={Localization.language_name(@source_language.locale_code)}
        theme-primary={@theme_primary}
        theme-accent={@theme_accent}
        has-custom-theme={@has_custom_theme}
      />
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_source_language(nil), do: nil

  defp serialize_source_language(lang) do
    %{localeCode: lang.locale_code}
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) do
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
    Authorize.with_authorization(socket, :manage_project, fn socket ->
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

  def handle_event("change_source_language", %{"locale_code" => locale_code}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case Localization.change_source_language(socket.assigns.project, locale_code) do
        {:ok, source_language} ->
          {:noreply,
           socket
           |> assign(:source_language, source_language)
           |> put_flash(:info, dgettext("projects", "Source language updated."))}

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
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_repair_variable_references(socket)
    end)
  end

  def handle_event("delete_project", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      workspace = socket.assigns.workspace

      case Projects.delete_project(socket.assigns.project, socket.assigns.current_scope.user.id) do
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

  def handle_event("update_theme_primary", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_primary, color)}
  end

  def handle_event("update_theme_accent", %{"color" => color}, socket) do
    {:noreply, assign(socket, :theme_accent, color)}
  end

  def handle_event("save_theme", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_save_theme(socket)
    end)
  end

  def handle_event("reset_theme", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
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

  defp do_save_theme(socket) do
    alias Storyarn.Shared.ColorUtils

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
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Invalid color format. Use #RRGGBB."))}
    end
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

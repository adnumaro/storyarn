defmodule StoryarnWeb.ProjectSettingsLive.General do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Localization
  alias Storyarn.ProductMetrics.Taxonomy
  alias Storyarn.Projects
  alias Storyarn.ProjectTemplates
  alias StoryarnWeb.Helpers.Authorize

  require Logger

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
      workspace={@workspace}
      project={@project}
    >
      <:title>{dgettext("projects", "General")}</:title>
      <:subtitle>{dgettext("projects", "Project details, theme, and maintenance")}</:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsGeneral"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-general"
        project-details={serialize_project_details(@project)}
        project-metrics-options={Taxonomy.project_options()}
        source-language={serialize_source_language(@source_language)}
        source-language-name={Localization.language_name(@source_language.locale_code)}
        theme-primary={@theme_primary}
        theme-accent={@theme_accent}
        has-custom-theme={@has_custom_theme}
        project-templates={serialize_project_templates(@project_templates)}
        project-template-publications={serialize_template_publications(@template_publications)}
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
    %{localeCode: lang.locale_code}
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      if connected?(socket), do: ProjectTemplates.subscribe_template_publications(project)

      {:ok, source_language} = Localization.ensure_source_language(project)
      project_changeset = Projects.change_project(project)

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:source_language, source_language)
        |> assign(:project_form, to_form(project_changeset))
        |> assign_project_templates()
        |> assign_template_publications()
        |> assign_theme(project)

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

  def handle_event("publish_template", %{"template" => template_params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      {:noreply, enqueue_template_publication(socket, template_params)}
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

  @impl true
  def handle_info({:project_template_publication_updated, _publication}, socket) do
    {:noreply,
     socket
     |> assign_project_templates()
     |> assign_template_publications()}
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp publish_template_from_settings(socket, %{"mode" => "new"} = params) do
    ProjectTemplates.request_template_publication(
      socket.assigns.current_scope,
      socket.assigns.project,
      template_attrs(params)
    )
  end

  defp publish_template_from_settings(socket, %{"mode" => "update"} = params) do
    with {:ok, template_id} <- parse_template_id(params["template_id"]),
         {:ok, template} <- fetch_template(socket.assigns.current_scope, template_id) do
      ProjectTemplates.request_template_version_publication(
        socket.assigns.current_scope,
        template,
        socket.assigns.project,
        template_attrs(params)
      )
    end
  end

  defp publish_template_from_settings(_socket, _params), do: {:error, :invalid_mode}

  defp enqueue_template_publication(socket, template_params) do
    case publish_template_from_settings(socket, template_params) do
      {:ok, _publication} ->
        socket
        |> assign_project_templates()
        |> assign_template_publications()
        |> put_flash(:info, dgettext("projects", "Template publication queued."))

      {:error, reason} ->
        Logger.warning(fn ->
          "Template publication enqueue failed project_id=#{socket.assigns.project.id} " <>
            "reason=#{inspect(template_publication_failure_summary(reason))}"
        end)

        put_flash(socket, :error, template_publication_error_message(reason))
    end
  end

  defp template_publication_failure_summary(%{"errors" => errors, "materialization" => materialization} = report) do
    %{
      status: Map.get(report, "status"),
      error_count: length(errors || []),
      first_errors: Enum.take(errors || [], 5),
      materialization: materialization
    }
  end

  defp template_publication_failure_summary(%Ecto.Changeset{} = changeset) do
    %{
      changeset_valid?: changeset.valid?,
      errors: changeset.errors
    }
  end

  defp template_publication_failure_summary(reason), do: reason

  defp template_publication_error_message(:publication_already_active) do
    dgettext("projects", "A template publication is already running.")
  end

  defp template_publication_error_message(_reason) do
    dgettext("projects", "Template could not be queued.")
  end

  defp template_attrs(params) do
    %{
      "name" => params["name"],
      "description" => params["description"]
    }
  end

  defp parse_template_id(value) when is_integer(value), do: {:ok, value}

  defp parse_template_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_template_id}
    end
  end

  defp parse_template_id(_value), do: {:error, :invalid_template_id}

  defp fetch_template(scope, template_id) do
    ProjectTemplates.get_template(scope, template_id)
  end

  defp assign_project_templates(socket) do
    assign(
      socket,
      :project_templates,
      project_templates_for_project(socket.assigns.current_scope, socket.assigns.project)
    )
  end

  defp assign_template_publications(socket) do
    assign(
      socket,
      :template_publications,
      ProjectTemplates.list_template_publications(socket.assigns.current_scope,
        source_project_id: socket.assigns.project.id,
        limit: 10
      )
    )
  end

  defp project_templates_for_project(scope, project) do
    scope
    |> ProjectTemplates.list_templates(source_project_id: project.id)
    |> Enum.filter(&(&1.visibility == "private" and &1.source_project_id == project.id))
  end

  defp serialize_project_templates(templates) do
    Enum.map(templates, fn template ->
      %{
        id: template.id,
        name: template.name,
        description: template.description || "",
        current_version_number: version_number(template.current_version)
      }
    end)
  end

  defp version_number(%{version_number: version_number}), do: version_number
  defp version_number(_version), do: nil

  defp serialize_template_publications(publications) do
    Enum.map(publications, fn publication ->
      %{
        id: publication.id,
        mode: publication.mode,
        status: publication.status,
        template_id: publication.project_template_id,
        template_version_id: publication.project_template_version_id,
        name: publication.name,
        description: publication.description || "",
        error_message: publication.error_message,
        inserted_at: iso_datetime(publication.inserted_at),
        completed_at: iso_datetime(publication.completed_at)
      }
    end)
  end

  defp iso_datetime(nil), do: nil
  defp iso_datetime(datetime), do: DateTime.to_iso8601(datetime)

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

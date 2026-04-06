defmodule StoryarnWeb.ProjectSettingsLive.VersionControl do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Billing
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
      <:title>{dgettext("projects", "Version Control")}</:title>
      <:subtitle>
        {dgettext("projects", "Configure automatic snapshots and auto-versioning")}
      </:subtitle>

      <.vue
        v-component="modules/project-settings/VersionControl"
        v-socket={@socket}
        id="project-settings-version-control"
        auto-snapshots-enabled={version_control_value(@version_control_form, :auto_snapshots_enabled)}
        auto-version-flows={version_control_value(@version_control_form, :auto_version_flows)}
        auto-version-scenes={version_control_value(@version_control_form, :auto_version_scenes)}
        auto-version-sheets={version_control_value(@version_control_form, :auto_version_sheets)}
        version-usage={serialize_version_usage(@version_usage)}
      />
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp version_control_value(nil, _field), do: false

  defp version_control_value(form, field) do
    case form[field] do
      %{value: val} -> val == true || val == "true"
      _ -> false
    end
  end

  defp serialize_version_usage(nil), do: nil

  defp serialize_version_usage(usage) do
    %{
      projectSnapshots: %{
        used: usage.project_snapshots.used,
        limit: usage.project_snapshots.limit
      },
      namedVersions: %{
        used: usage.named_versions.used,
        limit: usage.named_versions.limit
      }
    }
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
          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(
              :version_control_form,
              to_form(version_control_changeset(project), as: "version_control")
            )
            |> assign(:version_usage, Billing.project_usage(project.id, project.workspace_id))

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
  def handle_event("save_version_control", %{"version_control" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      attrs = %{
        auto_snapshots_enabled: params["auto_snapshots_enabled"] == "true",
        auto_version_flows: params["auto_version_flows"] == "true",
        auto_version_scenes: params["auto_version_scenes"] == "true",
        auto_version_sheets: params["auto_version_sheets"] == "true"
      }

      case Projects.update_project(socket.assigns.project, attrs) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(
             :version_control_form,
             to_form(version_control_changeset(project), as: "version_control")
           )
           |> put_flash(:info, dgettext("projects", "Version control settings saved."))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to save settings."))}
      end
    end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp version_control_changeset(project) do
    types = %{
      auto_snapshots_enabled: :boolean,
      auto_version_flows: :boolean,
      auto_version_scenes: :boolean,
      auto_version_sheets: :boolean
    }

    data = %{
      auto_snapshots_enabled: project.auto_snapshots_enabled,
      auto_version_flows: project.auto_version_flows,
      auto_version_scenes: project.auto_version_scenes,
      auto_version_sheets: project.auto_version_sheets
    }

    {data, types}
    |> Ecto.Changeset.cast(%{}, Map.keys(types))
  end
end

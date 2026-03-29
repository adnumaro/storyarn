defmodule StoryarnWeb.ProjectLive.Settings do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Versioning

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

      <.vue
        v-component="pages/workspaces/projects/settings/index"
        v-socket={@socket}
        id="project-settings"
        section={to_string(@live_action)}
        project-name={@project.name}
        project-description={@project.description || ""}
        source-language={serialize_source_language(@source_language)}
        source-language-name={Localization.language_name(@source_language.locale_code)}
        theme-primary={@theme_primary}
        theme-accent={@theme_accent}
        has-custom-theme={@has_custom_theme}
        provider-api-endpoint={provider_endpoint(@provider_form)}
        has-api-key={@has_api_key}
        provider-usage={serialize_provider_usage(@provider_usage)}
        members={serialize_members(@members)}
        current-user-id={@current_scope.user.id}
        snapshots={serialize_snapshots(@snapshots)}
        can-create-snapshot={@can_create_snapshot}
        restoration-in-progress={@restoration_in_progress}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
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
  # Serialization helpers for Vue props
  # ===========================================================================

  defp serialize_source_language(nil), do: nil

  defp serialize_source_language(lang) do
    %{localeCode: lang.locale_code}
  end

  defp provider_endpoint(nil), do: "https://api-free.deepl.com"

  defp provider_endpoint(form) do
    case form[:api_endpoint] do
      %{value: val} when is_binary(val) -> val
      _ -> "https://api-free.deepl.com"
    end
  end

  defp serialize_provider_usage(nil), do: nil

  defp serialize_provider_usage(usage) do
    %{
      characterCount: usage.character_count,
      characterLimit: usage.character_limit
    }
  end

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

  defp serialize_snapshots(snapshots) do
    Enum.map(snapshots, fn s ->
      %{
        id: s.id,
        title: s.title,
        description: s.description,
        versionNumber: s.version_number,
        insertedAt: s.inserted_at && DateTime.to_iso8601(s.inserted_at),
        snapshotSizeBytes: s.snapshot_size_bytes,
        entityCounts: s.entity_counts,
        createdByEmail: s.created_by && s.created_by.email
      }
    end)
  end

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
          members = Projects.list_project_members(project.id)
          {:ok, source_language} = Localization.ensure_source_language(project)

          project_changeset = Projects.change_project(project)
          provider_config = get_provider_config(project.id)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(:members, members)
            |> assign(:source_language, source_language)
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
            |> assign(:snapshots, [])
            |> assign(:snapshot_form, to_form(snapshot_changeset(%{}), as: "snapshot"))
            |> assign(:can_create_snapshot, true)
            |> assign(:version_control_form, nil)
            |> assign(:version_usage, nil)
            |> assign(:restoration_in_progress, restoration_in_progress?(project.id))
            |> assign_theme(project)
            |> maybe_subscribe_restoration(project.id)

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
      |> maybe_load_snapshots()
      |> maybe_load_version_control()

    {:noreply, socket}
  end

  defp maybe_load_snapshots(%{assigns: %{live_action: :snapshots}} = socket) do
    project = socket.assigns.project

    socket
    |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
    |> assign(
      :can_create_snapshot,
      Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
    )
  end

  defp maybe_load_snapshots(socket), do: socket

  defp maybe_load_version_control(%{assigns: %{live_action: :version_control}} = socket) do
    project = socket.assigns.project

    socket
    |> assign(
      :version_control_form,
      to_form(version_control_changeset(project), as: "version_control")
    )
    |> assign(:version_usage, Billing.project_usage(project.id, project.workspace_id))
  end

  defp maybe_load_version_control(socket), do: socket

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

  def handle_event("create_snapshot", %{"snapshot" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_create_snapshot(socket, params)
    end)
  end

  def handle_event("restore_snapshot", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_restore_snapshot(socket, id)
    end)
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_delete_snapshot(socket, id)
    end)
  end

  def handle_event("save_version_control", %{"version_control" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      # Checkboxes: absent = false, present = true
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

  def handle_event("save_provider_config", %{"provider" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_save_provider_config(socket, params)
    end)
  end

  def handle_event("test_provider_connection", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
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

  def handle_event("clear_stale_lock", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case Projects.clear_stale_restoration_lock(socket.assigns.project.id) do
        {:ok, :cleared} ->
          {:noreply,
           socket
           |> assign(:restoration_in_progress, false)
           |> put_flash(:info, dgettext("projects", "Stale restoration lock cleared."))}

        {:error, :not_stale} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("projects", "Lock is not stale yet. Please wait or let the restore finish.")
           )}
      end
    end)
  end

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
      {:noreply,
       put_flash(socket, :error, dgettext("projects", "Invalid color format. Use #RRGGBB."))}
    end
  end

  # ===========================================================================
  # Handle Info (restoration events)
  # ===========================================================================

  @impl true
  def handle_info({:project_restoration_started, _payload}, socket) do
    {:noreply, assign(socket, :restoration_in_progress, true)}
  end

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket) do
    project = socket.assigns.project

    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> assign(:snapshots, Versioning.list_project_snapshots(project.id))
     |> assign(
       :can_create_snapshot,
       Billing.can_create_project_snapshot?(project.id, project.workspace_id) == :ok
     )
     |> put_flash(
       :info,
       dgettext(
         "projects",
         "Project restored. %{restored} entities restored, %{skipped} skipped.",
         restored: payload.restored,
         skipped: payload.skipped
       )
     )}
  end

  @impl true
  def handle_info({:project_restoration_failed, _payload}, socket) do
    {:noreply,
     socket
     |> assign(:restoration_in_progress, false)
     |> put_flash(
       :error,
       dgettext("projects", "Project restoration failed. Please try again.")
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===========================================================================
  # Private
  # ===========================================================================

  defp section_title(:general), do: dgettext("projects", "General")
  defp section_title(:localization), do: dgettext("projects", "Localization")
  defp section_title(:members), do: dgettext("projects", "Members")
  defp section_title(:snapshots), do: dgettext("projects", "Snapshots")
  defp section_title(:version_control), do: dgettext("projects", "Version Control")

  defp section_subtitle(:general),
    do: dgettext("projects", "Project details, theme, and maintenance")

  defp section_subtitle(:localization),
    do: dgettext("projects", "Translation provider configuration")

  defp section_subtitle(:members),
    do: dgettext("projects", "Manage project members and invitations")

  defp section_subtitle(:snapshots),
    do: dgettext("projects", "Create and restore point-in-time project backups")

  defp section_subtitle(:version_control),
    do: dgettext("projects", "Configure automatic snapshots and auto-versioning")

  defp maybe_subscribe_restoration(socket, project_id) do
    if connected?(socket), do: Collaboration.subscribe_restoration(project_id)
    socket
  end

  defp restoration_in_progress?(project_id) do
    case Projects.restoration_in_progress?(project_id) do
      {true, _} -> true
      _ -> false
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

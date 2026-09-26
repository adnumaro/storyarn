defmodule StoryarnWeb.TemplateLive.Show do
  @moduledoc """
  Shows one project template and installs it into a workspace.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.Live.Shared.PlanLimitFlash

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.get_project_template(socket.assigns.current_scope, id) do
      {:ok, template} ->
        installable_workspaces = installable_workspaces(socket.assigns.current_scope)

        if connected?(socket) do
          Projects.subscribe_project_template_publications(template)
          Projects.subscribe_user_template_installations(socket.assigns.current_scope)
        end

        {:ok,
         socket
         |> assign_new(:current_workspace, fn -> nil end)
         |> assign_new(:workspaces, fn -> [] end)
         |> assign(:dismissed_installation_failure_ids, MapSet.new())
         |> assign(:installation_failure, nil)
         |> assign_template(template)
         |> assign(:installable_workspaces, installable_workspaces)
         |> assign(:install_form, install_form(template, installable_workspaces))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Template not found."))
         |> push_navigate(to: ~p"/templates")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.WorkspaceLayout.workspace
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
    >
      <.vue
        v-component="live/template/show/TemplateShow"
        v-socket={@socket}
        v-inject="workspace-layout"
        id="template-show-page"
        template={serialize_template(@template, @can_publish)}
        current-version={serialize_current_version(@current_version)}
        versions={Enum.map(@versions, &serialize_version(&1, @current_version, @can_publish))}
        publications={if(@can_publish, do: Enum.map(@publications, &serialize_publication/1), else: [])}
        has-active-publication={@has_active_publication}
        installs={if(@can_publish, do: Enum.map(@installs, &serialize_install/1), else: [])}
        install={serialize_install_state(assigns)}
        installation-failure={serialize_installation_failure(@installation_failure)}
        templates-href={~p"/templates"}
      />
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("install", %{"install" => install_params}, socket) do
    with {:ok, workspace_id} <- parse_workspace_id(install_params["workspace_id"]),
         {:ok, workspace, _membership} <- Workspaces.get_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, version} <- fetch_install_version(socket, install_params["version_id"]),
         {:ok, _installation} <-
           Projects.request_project_template_instantiation(
             socket.assigns.current_scope,
             socket.assigns.template.id,
             version.id,
             workspace.id,
             Map.put(install_params, "source", "template_show")
           ) do
      {:noreply,
       socket
       |> refresh_active_installations()
       |> put_flash(:info, dgettext("projects", "Template installation started."))}
    else
      {:error, :limit_reached, _details} ->
        {:ok, workspace_id} = parse_workspace_id(install_params["workspace_id"])

        {:noreply,
         PlanLimitFlash.put(socket, workspace_id, dgettext("workspaces", "Project limit reached for your plan"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}

      _other ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}
    end
  end

  def handle_event("dismiss_template_installation_failure", %{"installation_id" => installation_id}, socket) do
    with {:ok, installation_id} <- parse_installation_id(installation_id),
         %{
           id: ^installation_id,
           workspace: %{id: _} = workspace
         } <- socket.assigns.installation_failure,
         {:ok, _installation} <-
           Projects.dismiss_project_template_installation_failure(
             socket.assigns.current_scope,
             workspace.id,
             installation_id
           ) do
      {:noreply,
       socket
       |> remember_dismissed_installation_failure(installation_id)
       |> refresh_pending_installation_failures()}
    else
      _error -> {:noreply, refresh_pending_installation_failures(socket)}
    end
  end

  def handle_event("publish_new_version", params, socket) do
    template = socket.assigns.template
    version_notes = get_in(params, ["publication", "version_notes"])

    case template.source_project do
      %{id: source_project_id} ->
        case Projects.request_project_template_version_publication(
               socket.assigns.current_scope,
               template.id,
               source_project_id,
               %{
                 "name" => template.name,
                 "description" => template.description,
                 "version_notes" => version_notes
               }
             ) do
          {:ok, _publication} ->
            {:noreply,
             socket
             |> put_flash(:info, dgettext("projects", "Template publication queued."))
             |> assign_template(template)
             |> assign(:install_form, install_form(template, socket.assigns.installable_workspaces))}

          {:error, :publication_already_active} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "A template publication is already running."))}

          {:error, :limit_reached, %{resource: :project_template_versions_per_template}} ->
            {:noreply,
             PlanLimitFlash.put(
               socket,
               template.source_project.workspace_id,
               dgettext("projects", "Template version limit reached for your plan.")
             )}

          {:error, :limit_reached, _details} ->
            {:noreply,
             PlanLimitFlash.put(
               socket,
               template.source_project.workspace_id,
               dgettext("projects", "Template limit reached for your plan.")
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Template publication could not be queued."))}
        end

      _source_project ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template publication could not be queued."))}
    end
  end

  def handle_event("archive_template", _params, socket) do
    case Projects.archive_project_template(socket.assigns.current_scope, socket.assigns.template) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("projects", "Template archived."))
         |> push_navigate(to: ~p"/templates")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be archived."))}
    end
  end

  @impl true
  def handle_info({:project_template_publication_updated, _publication}, socket) do
    case Projects.get_project_template(socket.assigns.current_scope, socket.assigns.template.id) do
      {:ok, template} ->
        {:noreply,
         socket
         |> assign_template(template)
         |> assign(:install_form, install_form(template, socket.assigns.installable_workspaces))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("projects", "Template not found."))
         |> push_navigate(to: ~p"/templates")}
    end
  end

  def handle_info({:project_template_installation_updated, installation}, socket) do
    socket =
      if installation_for_template?(installation, socket.assigns.template.id) do
        socket
        |> refresh_active_installations()
        |> apply_installation_update(installation)
      else
        socket
      end

    {:noreply, socket}
  end

  defp apply_installation_update(socket, %{status: "completed"} = installation) do
    socket
    |> put_flash(:info, dgettext("projects", "Your project is ready."))
    |> push_navigate(to: ~p"/workspaces/#{installation.workspace.slug}/projects/#{installation.project.slug}")
  end

  defp apply_installation_update(socket, %{status: "failed", feedback_dismissed_at: nil} = installation) do
    if dismissed_installation_failure?(socket, installation.id),
      do: socket,
      else: refresh_pending_installation_failures(socket)
  end

  defp apply_installation_update(socket, %{status: "failed"} = installation) do
    socket
    |> remember_dismissed_installation_failure(installation.id)
    |> refresh_pending_installation_failures()
  end

  defp apply_installation_update(socket, _installation), do: socket

  defp assign_template(socket, template) do
    versions = Projects.list_project_template_versions(socket.assigns.current_scope, template)

    publications =
      Projects.list_project_template_publications(socket.assigns.current_scope,
        project_template_id: template.id
      )

    socket
    |> assign(:page_title, template.name)
    |> assign(:template, template)
    |> assign(:current_version, template.current_version)
    |> assign(:versions, versions)
    |> assign(:can_publish, Projects.can_manage_project_template?(socket.assigns.current_scope, template))
    |> assign(:publications, publications)
    |> assign(:has_active_publication, Enum.any?(publications, &active_publication?/1))
    |> assign(
      :installs,
      Projects.list_project_template_installs(socket.assigns.current_scope, template, limit: 10)
    )
    |> assign_active_installations(template)
    |> assign_pending_installation_failures(template)
  end

  defp assign_active_installations(socket, template) do
    installations =
      Projects.list_active_project_template_installations(socket.assigns.current_scope, template)

    socket
    |> assign(:active_installations, installations)
    |> assign(:has_active_installation, installations != [])
  end

  defp refresh_active_installations(socket) do
    assign_active_installations(socket, socket.assigns.template)
  end

  defp assign_pending_installation_failures(socket, template) do
    failures =
      Projects.list_pending_project_template_installation_failures(
        socket.assigns.current_scope,
        template
      )

    visible_failure =
      Enum.find(
        failures,
        &(not dismissed_installation_failure?(socket, &1.id))
      )

    assign(socket, :installation_failure, visible_failure)
  end

  defp refresh_pending_installation_failures(socket) do
    assign_pending_installation_failures(socket, socket.assigns.template)
  end

  defp installation_for_template?(installation, template_id) do
    installation.project_template_version.project_template_id == template_id
  end

  defp dismissed_installation_failure?(socket, installation_id) do
    MapSet.member?(socket.assigns.dismissed_installation_failure_ids, installation_id)
  end

  defp remember_dismissed_installation_failure(socket, installation_id) do
    socket =
      update(
        socket,
        :dismissed_installation_failure_ids,
        &MapSet.put(&1, installation_id)
      )

    case socket.assigns.installation_failure do
      %{id: ^installation_id} -> assign(socket, :installation_failure, nil)
      _installation -> socket
    end
  end

  defp installable_workspaces(scope) do
    scope
    |> Workspaces.list_workspaces()
    |> Enum.filter(&Workspaces.can?(&1.role, :create_project))
    |> Enum.map(& &1.workspace)
  end

  defp install_form(template, workspaces) do
    to_form(
      %{
        "workspace_id" => default_workspace_id(workspaces),
        "version_id" => current_version_id(template),
        "name" => template.name
      },
      as: :install
    )
  end

  defp default_workspace_id([]), do: ""
  defp default_workspace_id([workspace | _]), do: to_string(workspace.id)

  defp current_version_id(%{current_version: %{id: version_id}}), do: to_string(version_id)
  defp current_version_id(_template), do: ""

  defp active_publication?(%{status: status}), do: status in ~w(queued running retrying)

  defp parse_workspace_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_workspace}
    end
  end

  defp parse_workspace_id(_value), do: {:error, :invalid_workspace}

  defp parse_installation_id(value) when is_integer(value), do: {:ok, value}

  defp parse_installation_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> {:error, :invalid_installation}
    end
  end

  defp parse_installation_id(_value), do: {:error, :invalid_installation}

  defp fetch_install_version(socket, value) when is_binary(value) and value != "" do
    with {version_id, ""} <- Integer.parse(value),
         %{} = version <- Enum.find(socket.assigns.versions, &(&1.id == version_id)) do
      {:ok, version}
    else
      _ -> {:error, :invalid_template_version}
    end
  end

  defp fetch_install_version(%{assigns: %{current_version: %{} = version}}, _value), do: {:ok, version}
  defp fetch_install_version(_socket, _value), do: {:error, :invalid_template_version}

  defp serialize_template(template, can_publish) do
    %{
      id: template.id,
      name: template.name,
      description: template.description,
      visibility: template.visibility,
      status: template.status,
      canPublish: can_publish
    }
  end

  defp serialize_current_version(nil), do: nil

  defp serialize_current_version(version) do
    version
    |> serialize_version(version, false)
    |> Map.merge(%{entityCounts: entity_counts(version), preview: preview(version)})
  end

  # Who published a version is shown only to readers who manage the template.
  defp serialize_version(version, current_version, can_publish) do
    %{
      id: version.id,
      versionNumber: version.version_number,
      notes: version.version_notes,
      publishedAt: version.published_at,
      publishedByEmail: if(can_publish, do: published_by_email(version)),
      isCurrent: current_version?(version, current_version)
    }
  end

  defp serialize_publication(publication) do
    %{
      id: publication.id,
      name: publication.name,
      status: publication.status,
      mode: publication.mode,
      versionNumber: publication_version_number(publication),
      errorMessage: if(publication.status == "failed", do: publication.error_message),
      insertedAt: publication.inserted_at
    }
  end

  defp publication_version_number(%{project_template_version: %{version_number: number}}), do: number
  defp publication_version_number(_publication), do: nil

  defp serialize_install(install) do
    %{
      id: install.id,
      versionNumber: install.project_template_version.version_number,
      installedAt: install.installed_at
    }
  end

  defp serialize_active_installation(installation) do
    %{id: installation.id, projectName: installation.project_name, stage: installation.stage}
  end

  # Only the error code crosses: the page names it, never the stored message.
  defp serialize_installation_failure(nil), do: nil
  defp serialize_installation_failure(installation), do: %{id: installation.id, errorCode: installation.error_code}

  defp serialize_install_state(assigns) do
    form = assigns.install_form

    %{
      workspaces: Enum.map(assigns.installable_workspaces, &%{id: to_string(&1.id), name: &1.name}),
      defaults: %{
        workspaceId: form[:workspace_id].value || "",
        versionId: form[:version_id].value || "",
        name: form[:name].value || ""
      },
      activeInstallations: Enum.map(assigns.active_installations, &serialize_active_installation/1)
    }
  end

  defp current_version?(%{id: version_id}, %{id: version_id}), do: true
  defp current_version?(_version, _current_version), do: false

  defp published_by_email(%{published_by: %{email: email}}) when is_binary(email), do: email
  defp published_by_email(_version), do: nil

  defp entity_counts(%{entity_counts: counts}) when is_map(counts) do
    counts
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.take(12)
    |> Enum.map(fn {key, value} -> [key, value] end)
  end

  defp entity_counts(_version), do: []

  defp preview(%{preview: %{} = preview}) do
    Map.new(~w(sheets flows scenes)a, fn type ->
      {type, preview |> Map.get(Atom.to_string(type), []) |> Enum.map(&Map.get(&1, "name")) |> Enum.reject(&is_nil/1)}
    end)
  end

  defp preview(_version), do: %{sheets: [], flows: [], scenes: []}
end

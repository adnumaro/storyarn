defmodule StoryarnWeb.TemplateLive.Show do
  @moduledoc """
  Shows one project template and installs it into a workspace.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.TemplateLive.Helpers

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case ProjectTemplates.get_template(socket.assigns.current_scope, id) do
      {:ok, template} ->
        installable_workspaces = installable_workspaces(socket.assigns.current_scope)

        if connected?(socket) do
          ProjectTemplates.subscribe_template_publications(template)
          ProjectTemplates.subscribe_user_installations(socket.assigns.current_scope)
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
      <main id="template-show" class="min-h-dvh bg-base-100 px-6 py-8 lg:px-10">
        <div class="mx-auto grid w-full max-w-6xl gap-6 lg:grid-cols-[minmax(0,1fr)_360px]">
          <section class="flex flex-col gap-6">
            <nav class="text-sm">
              <.link navigate={~p"/templates"} class="link link-hover text-base-content/60">
                {dgettext("projects", "Templates")}
              </.link>
            </nav>

            <header class="flex flex-col gap-4 border-b border-base-300 pb-6">
              <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                <div class="min-w-0">
                  <div class="mb-2 flex items-center gap-2">
                    <span class={["badge", visibility_badge_class(@template.visibility)]}>
                      {visibility_label(@template.visibility)}
                    </span>
                    <span class="badge badge-outline">{status_label(@template.status)}</span>
                  </div>
                  <h1 class="text-3xl font-semibold tracking-normal text-base-content">
                    {@template.name}
                  </h1>
                  <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/65">
                    {template_description(@template)}
                  </p>
                </div>

                <.form
                  :if={@can_publish}
                  for={@publish_form}
                  id="publish-template-version-form"
                  class="flex w-full flex-col gap-2 md:w-80"
                  phx-submit="publish_new_version"
                >
                  <textarea
                    id="template-version-notes"
                    name={@publish_form[:version_notes].name}
                    class="textarea textarea-bordered textarea-sm min-h-20"
                    maxlength="2000"
                    placeholder={dgettext("projects", "Version notes")}
                    disabled={@has_active_publication}
                  >{@publish_form[:version_notes].value}</textarea>
                  <button
                    id="publish-template-version-button"
                    type="submit"
                    class="btn btn-outline btn-sm"
                    disabled={@has_active_publication}
                  >
                    <%= if @has_active_publication do %>
                      {dgettext("projects", "Publication running")}
                    <% else %>
                      {dgettext("projects", "Publish new version")}
                    <% end %>
                  </button>
                </.form>

                <button
                  :if={@can_publish}
                  id="archive-template-button"
                  type="button"
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="archive_template"
                >
                  {dgettext("projects", "Archive")}
                </button>
              </div>
            </header>

            <section
              id="template-version-panel"
              class="rounded-box border border-base-300 bg-base-100 p-5"
            >
              <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                <div>
                  <h2 class="text-base font-semibold text-base-content">
                    {dgettext("projects", "Current version")}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/60">
                    {version_summary(@current_version)}
                  </p>
                </div>

                <div class="text-sm text-base-content/60">
                  {published_at(@current_version)}
                </div>
              </div>

              <div class="mt-5 flex flex-wrap gap-2">
                <%= for {key, value} <- entity_counts(@current_version) do %>
                  <span class="badge badge-ghost gap-1">
                    <span>{key}</span>
                    <span class="font-semibold">{value}</span>
                  </span>
                <% end %>
              </div>

              <p :if={version_notes(@current_version) != ""} class="mt-4 text-sm text-base-content/70">
                {version_notes(@current_version)}
              </p>

              <div
                :if={preview_groups(@current_version) != []}
                id="template-current-preview"
                class="mt-5 grid gap-3 md:grid-cols-3"
              >
                <div
                  :for={group <- preview_groups(@current_version)}
                  class="rounded-box border border-base-300 bg-base-200/40 p-3"
                >
                  <p class="text-xs font-semibold uppercase tracking-normal text-base-content/50">
                    {group.label}
                  </p>
                  <ul class="mt-2 space-y-1 text-sm text-base-content/75">
                    <li :for={item <- group.items} class="truncate">{item}</li>
                  </ul>
                </div>
              </div>
            </section>

            <section
              :if={@can_publish and @publications != []}
              id="template-publications-panel"
              class="rounded-box border border-base-300 bg-base-100 p-5"
            >
              <div class="flex items-center justify-between">
                <h2 class="text-base font-semibold text-base-content">
                  {dgettext("projects", "Publication history")}
                </h2>
                <span class="badge badge-neutral">{length(@publications)}</span>
              </div>

              <div class="mt-4 flex flex-col divide-y divide-base-300">
                <div
                  :for={publication <- @publications}
                  id={"template-publication-#{publication.id}"}
                  class="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
                >
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class={["badge badge-sm", publication_badge_class(publication.status)]}>
                        {publication_status_label(publication.status)}
                      </span>
                      <span class="truncate text-sm font-medium text-base-content">
                        {publication.name}
                      </span>
                    </div>
                    <p class="mt-1 text-xs text-base-content/60">
                      {publication_summary(publication)}
                    </p>
                  </div>
                  <div class="shrink-0 text-xs text-base-content/50">
                    {format_datetime(publication.inserted_at)}
                  </div>
                </div>
              </div>
            </section>

            <section
              id="template-versions-panel"
              class="rounded-box border border-base-300 bg-base-100 p-5"
            >
              <div class="flex items-center justify-between">
                <h2 class="text-base font-semibold text-base-content">
                  {dgettext("projects", "Versions")}
                </h2>
                <span id="template-version-count" class="badge badge-neutral">
                  {length(@versions)}
                </span>
              </div>

              <div class="mt-4 overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{dgettext("projects", "Version")}</th>
                      <th>{dgettext("projects", "Published")}</th>
                      <th :if={@can_publish}>{dgettext("projects", "By")}</th>
                    </tr>
                  </thead>
                  <tbody id="template-versions">
                    <tr :for={version <- @versions} id={"template-version-#{version.id}"}>
                      <td>
                        <div class="flex items-center gap-2">
                          <span class="font-medium">{version_summary(version)}</span>
                          <span
                            :if={current_version?(version, @current_version)}
                            class="badge badge-primary badge-sm"
                          >
                            {dgettext("projects", "Current")}
                          </span>
                        </div>
                        <p
                          :if={version_notes(version) != ""}
                          class="mt-1 max-w-lg text-xs text-base-content/60"
                        >
                          {version_notes(version)}
                        </p>
                      </td>
                      <td>{format_datetime(version.published_at)}</td>
                      <td :if={@can_publish}>{published_by_email(version)}</td>
                    </tr>
                    <tr :if={@versions == []} id="template-versions-empty">
                      <td colspan={if(@can_publish, do: "3", else: "2")} class="text-base-content/60">
                        {dgettext("projects", "No versions published yet.")}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section
              :if={@can_publish}
              id="template-install-history"
              class="rounded-box border border-base-300 bg-base-100 p-5"
            >
              <div class="mb-4 flex items-center justify-between">
                <h2 class="text-base font-semibold text-base-content">
                  {dgettext("projects", "Install history")}
                </h2>
                <span class="badge badge-neutral">{length(@installs)}</span>
              </div>

              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{dgettext("projects", "Version")}</th>
                      <th>{dgettext("projects", "Installed")}</th>
                    </tr>
                  </thead>
                  <tbody id="template-installs">
                    <tr :for={install <- @installs} id={"template-install-#{install.id}"}>
                      <td>{install.project_template_version.version_number}</td>
                      <td>{format_datetime(install.installed_at)}</td>
                    </tr>
                    <tr :if={@installs == []} id="template-installs-empty">
                      <td colspan="2" class="text-base-content/60">
                        {dgettext("projects", "No installs yet.")}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </section>
          </section>

          <aside class="lg:sticky lg:top-8 lg:self-start">
            <section
              id="template-install-panel"
              class="rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <h2 class="text-base font-semibold text-base-content">
                {dgettext("projects", "Create project")}
              </h2>

              <div
                :if={@active_installations != []}
                id="template-active-installations"
                class="mt-4 space-y-3"
                aria-live="polite"
              >
                <article
                  :for={installation <- @active_installations}
                  id={"template-active-installation-#{installation.id}"}
                  class="rounded-box border border-primary/30 bg-primary/5 p-4"
                >
                  <div class="flex items-start gap-3">
                    <span class="loading loading-spinner loading-sm mt-0.5 text-primary"></span>
                    <div class="min-w-0">
                      <p class="truncate text-sm font-semibold text-base-content">
                        {installation.project_name}
                      </p>
                      <p class="mt-1 text-xs text-base-content/65">
                        {installation_stage_label(installation.stage)}
                      </p>
                      <p class="mt-2 text-xs text-base-content/50">
                        {dgettext("projects", "Installation reference: %{reference}",
                          reference: installation.id
                        )}
                      </p>
                    </div>
                  </div>
                </article>
              </div>

              <.form
                for={@install_form}
                id="template-install-form"
                class="mt-4 flex flex-col gap-4"
                phx-submit="install"
              >
                <label class="form-control gap-2">
                  <span class="label-text">{dgettext("workspaces", "Workspace")}</span>
                  <select
                    id="template-install-workspace"
                    name={@install_form[:workspace_id].name}
                    class="select select-bordered w-full"
                    disabled={@installable_workspaces == [] or @has_active_installation}
                  >
                    <option
                      :for={workspace <- @installable_workspaces}
                      value={workspace.id}
                      selected={to_string(workspace.id) == @install_form[:workspace_id].value}
                    >
                      {workspace.name}
                    </option>
                  </select>
                </label>

                <label class="form-control gap-2">
                  <span class="label-text">{dgettext("projects", "Template version")}</span>
                  <select
                    id="template-install-version"
                    name={@install_form[:version_id].name}
                    class="select select-bordered w-full"
                    disabled={@versions == [] or @has_active_installation}
                  >
                    <option
                      :for={version <- @versions}
                      value={version.id}
                      selected={to_string(version.id) == @install_form[:version_id].value}
                    >
                      {version_option_label(version, @current_version)}
                    </option>
                  </select>
                </label>

                <label class="form-control gap-2">
                  <span class="label-text">{dgettext("projects", "Project name")}</span>
                  <input
                    id="template-install-name"
                    name={@install_form[:name].name}
                    value={@install_form[:name].value}
                    type="text"
                    class="input input-bordered w-full"
                    maxlength="100"
                    required
                    disabled={@has_active_installation}
                  />
                </label>

                <button
                  id="template-install-submit"
                  type="submit"
                  class="btn btn-primary w-full"
                  disabled={
                    @installable_workspaces == [] or is_nil(@current_version) or
                      @has_active_installation
                  }
                  phx-disable-with={dgettext("projects", "Starting installation…")}
                >
                  <%= if @has_active_installation do %>
                    <span class="loading loading-spinner loading-sm"></span>
                    {dgettext("projects", "Installation in progress")}
                  <% else %>
                    {dgettext("projects", "Create from template")}
                  <% end %>
                </button>
              </.form>
            </section>
          </aside>
        </div>
      </main>

      <div
        :if={@installation_failure}
        id="template-installation-failure-toast"
        class="toast toast-end bottom-20 z-[2000] w-full max-w-sm"
        aria-live="polite"
      >
        <div role="alert" class="alert alert-error items-start border border-error/40 shadow-lg">
          <p class="min-w-0 flex-1 text-sm">
            {installation_failure_message(@installation_failure)}
          </p>
          <button
            id="dismiss-template-installation-failure"
            type="button"
            class="btn btn-ghost btn-xs btn-square shrink-0"
            phx-click="dismiss_template_installation_failure"
            phx-value-installation_id={@installation_failure.id}
            aria-label={dgettext("projects", "Dismiss installation failure")}
          >
            <.icon name="x" class="size-4" />
          </button>
        </div>
      </div>
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("install", %{"install" => install_params}, socket) do
    with {:ok, workspace_id} <- parse_workspace_id(install_params["workspace_id"]),
         {:ok, workspace, _membership} <- Workspaces.get_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, version} <- fetch_install_version(socket, install_params["version_id"]),
         {:ok, _installation} <-
           ProjectTemplates.request_template_instantiation(
             socket.assigns.current_scope,
             version,
             workspace,
             Map.put(install_params, "source", "template_show")
           ) do
      {:noreply,
       socket
       |> refresh_active_installations()
       |> put_flash(:info, dgettext("projects", "Template installation started."))}
    else
      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Project limit reached for your plan"))}

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
           workspace: %Workspace{} = workspace
         } <- socket.assigns.installation_failure,
         {:ok, _installation} <-
           ProjectTemplates.dismiss_installation_failure(
             socket.assigns.current_scope,
             workspace,
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
      %Project{} = source_project ->
        case ProjectTemplates.request_template_version_publication(
               socket.assigns.current_scope,
               template,
               source_project,
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
             |> assign(:publish_form, publish_form())
             |> assign(:install_form, install_form(template, socket.assigns.installable_workspaces))}

          {:error, :publication_already_active} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "A template publication is already running."))}

          {:error, :limit_reached, %{resource: :project_template_versions_per_template}} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Template version limit reached for your plan."))}

          {:error, :limit_reached, _details} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Template limit reached for your plan."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Template publication could not be queued."))}
        end

      _source_project ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template publication could not be queued."))}
    end
  end

  def handle_event("archive_template", _params, socket) do
    case ProjectTemplates.archive_template(socket.assigns.current_scope, socket.assigns.template) do
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
    case ProjectTemplates.get_template(socket.assigns.current_scope, socket.assigns.template.id) do
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
    versions = ProjectTemplates.list_template_versions(socket.assigns.current_scope, template)

    publications =
      ProjectTemplates.list_template_publications(socket.assigns.current_scope, project_template_id: template.id)

    socket
    |> assign(:page_title, template.name)
    |> assign(:template, template)
    |> assign(:current_version, template.current_version)
    |> assign(:versions, versions)
    |> assign(:can_publish, ProjectTemplates.can_manage_template?(socket.assigns.current_scope, template))
    |> assign(:publish_form, publish_form())
    |> assign(:publications, publications)
    |> assign(:has_active_publication, Enum.any?(publications, &active_publication?/1))
    |> assign(:installs, ProjectTemplates.list_template_installs(socket.assigns.current_scope, template, limit: 10))
    |> assign_active_installations(template)
    |> assign_pending_installation_failures(template)
  end

  defp assign_active_installations(socket, template) do
    installations =
      ProjectTemplates.list_active_template_installations(socket.assigns.current_scope, template)

    socket
    |> assign(:active_installations, installations)
    |> assign(:has_active_installation, installations != [])
  end

  defp refresh_active_installations(socket) do
    assign_active_installations(socket, socket.assigns.template)
  end

  defp assign_pending_installation_failures(socket, template) do
    failures =
      ProjectTemplates.list_pending_template_installation_failures(
        socket.assigns.current_scope,
        template
      )

    visible_failure =
      Enum.find(
        failures,
        &(not dismissed_installation_failure?(socket, &1.id))
      )

    socket
    |> assign(:installation_failures, failures)
    |> assign(:installation_failure, visible_failure)
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

  @safe_installation_failure_messages [
    "A template asset could not be copied.",
    "The installation could not be completed.",
    "This template is no longer available.",
    "The template failed its integrity check.",
    "This template version is incompatible and must be republished.",
    "This template version contains an invalid subflow exit and must be republished.",
    "The workspace project limit has been reached.",
    "The template asset manifest is unavailable.",
    "The template integrity information is unavailable.",
    "The template or workspace is no longer available.",
    "You no longer have permission to install this template."
  ]

  defp installation_failure_message(installation) do
    dgettext(
      "projects",
      "Template installation failed: %{reason} Reference: %{reference}",
      reason: safe_installation_failure_reason(installation),
      reference: installation.id
    )
  end

  defp safe_installation_failure_reason(%{error_message: message}) when message in @safe_installation_failure_messages,
    do: message

  defp safe_installation_failure_reason(_installation),
    do: dgettext("projects", "The installation could not be completed.")

  defp installation_stage_label("queued"), do: dgettext("projects", "Waiting to start…")
  defp installation_stage_label("verifying"), do: dgettext("projects", "Verifying template integrity…")
  defp installation_stage_label("materializing"), do: dgettext("projects", "Copying project content and assets…")
  defp installation_stage_label("retrying"), do: dgettext("projects", "Retrying after a temporary issue…")
  defp installation_stage_label(_stage), do: dgettext("projects", "Creating project…")

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

  defp publish_form do
    to_form(%{"version_notes" => ""}, as: :publication)
  end

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

  defp publication_summary(%{status: "published", project_template_version: %{version_number: version_number}}) do
    dgettext("projects", "Published version %{version}", version: version_number)
  end

  defp publication_summary(%{status: "failed", error_message: message}) when is_binary(message) and message != "" do
    message
  end

  defp publication_summary(%{mode: "new"}), do: dgettext("projects", "New template publication")
  defp publication_summary(%{mode: "update"}), do: dgettext("projects", "Template version publication")
  defp publication_summary(_publication), do: ""

  defp version_summary(version), do: version_label(version)

  defp version_option_label(version, current_version) do
    label = version_summary(version)

    if current_version?(version, current_version) do
      "#{label} - #{dgettext("projects", "Current")}"
    else
      label
    end
  end

  defp current_version?(%{id: version_id}, %{id: version_id}), do: true
  defp current_version?(_version, _current_version), do: false

  defp published_by_email(%{published_by: %{email: email}}) when is_binary(email), do: email
  defp published_by_email(_version), do: ""

  defp published_at(%{published_at: published_at}) do
    dgettext("projects", "Published %{date}", date: format_datetime(published_at))
  end

  defp published_at(_version), do: ""

  defp entity_counts(%{entity_counts: counts}) when is_map(counts) do
    counts
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.take(12)
  end

  defp entity_counts(_version), do: []

  defp version_notes(%{version_notes: notes}) when is_binary(notes), do: notes
  defp version_notes(_version), do: ""

  defp preview_groups(%{preview: %{} = preview}) do
    Enum.reject(
      [
        preview_group(dgettext("projects", "Sheets"), Map.get(preview, "sheets", [])),
        preview_group(dgettext("projects", "Flows"), Map.get(preview, "flows", [])),
        preview_group(dgettext("projects", "Scenes"), Map.get(preview, "scenes", []))
      ],
      &(&1.items == [])
    )
  end

  defp preview_groups(_version), do: []

  defp preview_group(label, entries) do
    %{
      label: label,
      items:
        entries
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.reject(&is_nil/1)
    }
  end
end

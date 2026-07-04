defmodule StoryarnWeb.TemplateLive.Show do
  @moduledoc """
  Shows one project template and installs it into a workspace.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates
  alias Storyarn.Workspaces

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    template = ProjectTemplates.get_template!(socket.assigns.current_scope, id)
    installable_workspaces = installable_workspaces(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign_new(:current_workspace, fn -> nil end)
     |> assign_new(:workspaces, fn -> [] end)
     |> assign_template(template)
     |> assign(:installable_workspaces, installable_workspaces)
     |> assign(:install_form, install_form(template, installable_workspaces))}
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

                <button
                  :if={@can_publish}
                  id="publish-template-version-button"
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="publish_new_version"
                >
                  {dgettext("projects", "Publish new version")}
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
                      <th>{dgettext("projects", "Project")}</th>
                      <th>{dgettext("workspaces", "Workspace")}</th>
                      <th>{dgettext("projects", "Version")}</th>
                      <th>{dgettext("projects", "Installed")}</th>
                    </tr>
                  </thead>
                  <tbody id="template-installs">
                    <tr :for={install <- @installs} id={"template-install-#{install.id}"}>
                      <td>{install.project && install.project.name}</td>
                      <td>{install.workspace && install.workspace.name}</td>
                      <td>{install.project_template_version.version_number}</td>
                      <td>{format_datetime(install.installed_at)}</td>
                    </tr>
                    <tr :if={@installs == []} id="template-installs-empty">
                      <td colspan="4" class="text-base-content/60">
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
                    disabled={@installable_workspaces == []}
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
                  <span class="label-text">{dgettext("projects", "Project name")}</span>
                  <input
                    id="template-install-name"
                    name={@install_form[:name].name}
                    value={@install_form[:name].value}
                    type="text"
                    class="input input-bordered w-full"
                    maxlength="100"
                    required
                  />
                </label>

                <button
                  id="template-install-submit"
                  type="submit"
                  class="btn btn-primary w-full"
                  disabled={@installable_workspaces == [] or is_nil(@current_version)}
                >
                  {dgettext("projects", "Create from template")}
                </button>
              </.form>
            </section>
          </aside>
        </div>
      </main>
    </StoryarnWeb.Components.WorkspaceLayout.workspace>
    """
  end

  @impl true
  def handle_event("install", %{"install" => install_params}, socket) do
    with {:ok, workspace_id} <- parse_workspace_id(install_params["workspace_id"]),
         {:ok, workspace, _membership} <- Workspaces.get_workspace(socket.assigns.current_scope, workspace_id),
         %{current_version: version} when not is_nil(version) <- socket.assigns.template,
         {:ok, project} <-
           ProjectTemplates.instantiate_template(socket.assigns.current_scope, version, workspace, install_params) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("projects", "Project created successfully."))
       |> push_navigate(to: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}")}
    else
      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Project limit reached for your plan"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}

      _other ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template could not be installed."))}
    end
  end

  def handle_event("publish_new_version", _params, socket) do
    template = socket.assigns.template

    case template.source_project do
      %Project{} = source_project ->
        case ProjectTemplates.publish_new_version(socket.assigns.current_scope, template, source_project) do
          {:ok, template} ->
            {:noreply,
             socket
             |> put_flash(:info, dgettext("projects", "Template version published."))
             |> assign_template(template)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Template version could not be published."))}
        end

      _source_project ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Template version could not be published."))}
    end
  end

  defp assign_template(socket, template) do
    socket
    |> assign(:page_title, template.name)
    |> assign(:template, template)
    |> assign(:current_version, template.current_version)
    |> assign(:can_publish, can_publish?(socket.assigns.current_scope, template))
    |> assign(:installs, ProjectTemplates.list_template_installs(socket.assigns.current_scope, template, limit: 10))
  end

  defp installable_workspaces(scope) do
    scope
    |> Workspaces.list_workspaces()
    |> Enum.filter(&Workspaces.can?(&1.role, :create_project))
    |> Enum.map(& &1.workspace)
  end

  defp install_form(template, []), do: to_form(%{"workspace_id" => "", "name" => template.name}, as: :install)

  defp install_form(template, [workspace | _]) do
    to_form(%{"workspace_id" => to_string(workspace.id), "name" => template.name}, as: :install)
  end

  defp can_publish?(%{user: %{id: user_id}}, %{owner_id: user_id, visibility: "private"}), do: true
  defp can_publish?(_scope, _template), do: false

  defp parse_workspace_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :invalid_workspace}
    end
  end

  defp parse_workspace_id(_value), do: {:error, :invalid_workspace}

  defp template_description(%{description: description}) when is_binary(description) and description != "" do
    description
  end

  defp template_description(_template), do: dgettext("projects", "No description")

  defp visibility_label("public"), do: dgettext("projects", "Public")
  defp visibility_label(_visibility), do: dgettext("projects", "Private")

  defp visibility_badge_class("public"), do: "badge-info"
  defp visibility_badge_class(_visibility), do: "badge-outline"

  defp status_label("archived"), do: dgettext("projects", "Archived")
  defp status_label(_status), do: dgettext("projects", "Active")

  defp version_summary(%{version_number: version_number}) when is_integer(version_number) do
    dgettext("projects", "Version %{version}", version: version_number)
  end

  defp version_summary(_version), do: dgettext("projects", "No version")

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

  defp format_datetime(nil), do: ""

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> format_datetime()
  end
end

defmodule StoryarnWeb.CompareLive.Sheet do
  @moduledoc """
  Side-by-side sheet comparison view (GitHub-style).

  Renders two iframes loading `VersionLive.Viewer`: the left shows the current
  sheet state, the right shows a historical version. Navigable by URL with
  prev/next version stepping.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias Storyarn.Versioning

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen flex flex-col bg-base-100">
      <%!-- Compare header bar --%>
      <header class="h-11 flex-shrink-0 flex items-center justify-between px-4 bg-base-200 border-b border-base-300">
        <div class="flex items-center gap-3">
          <.link
            navigate={@back_url}
            class="btn btn-ghost btn-sm btn-square"
            aria-label={gettext("Back to editor")}
          >
            <.icon name="arrow-left" class="size-4" />
          </.link>
          <div class="flex items-center gap-1.5 text-sm text-base-content/70">
            <.icon name="columns-2" class="size-4" />
            <span class="font-medium">{gettext("Comparing versions")}</span>
          </div>
        </div>
        <div class="flex items-center gap-1">
          <.link
            :if={@prev_version}
            patch={compare_url(assigns, @prev_version)}
            class="btn btn-ghost btn-xs btn-square"
            aria-label={gettext("Previous version")}
          >
            <.icon name="chevron-left" class="size-3.5" />
          </.link>
          <span class="text-xs text-base-content/60 px-1">{@version_label}</span>
          <.link
            :if={@next_version}
            patch={compare_url(assigns, @next_version)}
            class="btn btn-ghost btn-xs btn-square"
            aria-label={gettext("Next version")}
          >
            <.icon name="chevron-right" class="size-3.5" />
          </.link>
        </div>
      </header>

      <%!-- Split panes --%>
      <div class="flex-1 overflow-hidden grid grid-cols-2 divide-x divide-base-300">
        <%!-- Left: current state --%>
        <div class="flex flex-col overflow-hidden">
          <div class="h-8 flex-shrink-0 flex items-center justify-center bg-base-200/50 border-b border-base-300 text-xs font-medium text-base-content/50">
            {gettext("Current")}
          </div>
          <iframe src={@current_url} class="flex-1 w-full border-0" title={gettext("Current")}>
          </iframe>
        </div>

        <%!-- Right: historical version --%>
        <div class="flex flex-col overflow-hidden">
          <div class="h-8 flex-shrink-0 flex items-center justify-center bg-base-200/50 border-b border-base-300 text-xs font-medium text-base-content/50">
            {@version_label}
          </div>
          <iframe src={@version_url} class="flex-1 w-full border-0" title={@version_label}></iframe>
        </div>
      </div>
    </div>
    """
  end

  # ========== Mount ==========

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => sheet_id_str
        },
        _session,
        socket
      ) do
    with {sheet_id, ""} <- Integer.parse(sheet_id_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(
             socket.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         sheet when not is_nil(sheet) <- Sheets.get_sheet(project.id, sheet_id) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:workspace, project.workspace)
       |> assign(:sheet, sheet)
       |> assign(:back_url, sheet_url(project, sheet))
       # Version-specific assigns set in handle_params
       |> assign(:version_label, "")
       |> assign(:prev_version, nil)
       |> assign(:next_version, nil)
       |> assign(:current_url, "")
       |> assign(:version_url, ""), layout: false}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Sheet not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_str}, _url, socket) do
    %{sheet: sheet, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_str),
         version when not is_nil(version) <-
           Versioning.get_version("sheet", sheet.id, version_number) do
      version_label =
        if version.title do
          "v#{version.version_number} — #{version.title}"
        else
          "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
        end

      {prev_number, next_number} =
        Versioning.get_adjacent_version_numbers("sheet", sheet.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}?layout=compact"

      version_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/versions/sheet/#{sheet.id}/#{version.version_number}"

      {:noreply,
       socket
       |> assign(:version_label, version_label)
       |> assign(:prev_version, prev_number)
       |> assign(:next_version, next_number)
       |> assign(:current_url, current_url)
       |> assign(:version_url, version_url)
       |> assign(:page_title, version_label)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Version not found"))
         |> push_navigate(to: socket.assigns.back_url)}
    end
  end

  # ========== Private ==========

  defp compare_url(assigns, version_number) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{assigns.sheet.id}/compare/#{version_number}"
  end

  defp sheet_url(project, sheet) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end
end

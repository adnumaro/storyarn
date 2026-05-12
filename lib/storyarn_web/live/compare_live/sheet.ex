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
  alias StoryarnWeb.Components.CompareLayout

  @impl true
  def render(assigns) do
    ~H"""
    <CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/compare/Page"
        v-socket={@socket}
        v-inject="compare-layout"
        id="sheet-compare-vue"
        back-url={@back_url}
        version-label={@version_label}
        prev-version-url={@prev_version && compare_url(assigns, @prev_version)}
        next-version-url={@next_version && compare_url(assigns, @next_version)}
        current-url={@current_url}
        version-url={@version_url}
      />
    </CompareLayout.compare>
    """
  end

  # ========== Mount ==========

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => sheet_id_str}, _session, socket) do
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
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/versions/#{version.version_number}/viewer"

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

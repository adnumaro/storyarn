defmodule StoryarnWeb.SheetLive.Compare do
  @moduledoc """
  Side-by-side comparison for the current Sheet and one of its versions.

  This surface belongs to the Sheets boundary: both the Sheet read model and
  version navigation are obtained exclusively through `Storyarn.Sheets`.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/compare/VersioningCompare"
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
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  @impl true
  def mount(%{"id" => sheet_id_string}, _session, socket) do
    %{project: project, workspace: workspace} = socket.assigns

    with {sheet_id, ""} <- Integer.parse(sheet_id_string),
         sheet when not is_nil(sheet) <- Sheets.get_sheet(project.id, sheet_id) do
      {:ok,
       socket
       |> assign(:sheet, sheet)
       |> assign(:back_url, sheet_url(workspace, project, sheet))
       |> assign(:version_label, "")
       |> assign(:prev_version, nil)
       |> assign(:next_version, nil)
       |> assign(:current_url, "")
       |> assign(:version_url, ""), layout: false}
    else
      _error ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Sheet not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_string}, _url, socket) do
    %{sheet: sheet, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_string),
         version when not is_nil(version) <- Sheets.get_version(sheet.id, version_number) do
      {previous_number, next_number} =
        Sheets.get_adjacent_version_numbers(sheet.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}?layout=compact"

      version_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/versions/#{version.version_number}/viewer"

      {:noreply,
       socket
       |> assign(:version_label, version_label(version))
       |> assign(:prev_version, previous_number)
       |> assign(:next_version, next_number)
       |> assign(:current_url, current_url)
       |> assign(:version_url, version_url)
       |> assign(:page_title, version_label(version))}
    else
      _error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Version not found"))
         |> push_navigate(to: socket.assigns.back_url)}
    end
  end

  defp compare_url(assigns, version_number) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{assigns.sheet.id}/compare/#{version_number}"
  end

  defp sheet_url(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end
end

defmodule StoryarnWeb.FlowLive.Compare do
  @moduledoc """
  Side-by-side comparison for the current Flow and one of its versions.

  This surface belongs to the Flows boundary: it obtains both the Flow read
  model and version navigation exclusively through `Storyarn.Flows`.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Flows

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/compare/VersioningCompare"
        v-socket={@socket}
        v-inject="compare-layout"
        id="flow-compare-vue"
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
  def mount(%{"id" => flow_id_str}, _session, socket) do
    %{project: project, workspace: workspace} = socket.assigns

    with {flow_id, ""} <- Integer.parse(flow_id_str),
         flow when not is_nil(flow) <- Flows.get_flow_brief(project.id, flow_id) do
      {:ok,
       socket
       |> assign(:flow, flow)
       |> assign(:back_url, flow_url(workspace, project, flow))
       |> assign(:version_label, "")
       |> assign(:prev_version, nil)
       |> assign(:next_version, nil)
       |> assign(:current_url, "")
       |> assign(:version_url, ""), layout: false}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "Flow not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_str}, _url, socket) do
    %{flow: flow, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_str),
         version when not is_nil(version) <- Flows.get_version(flow.id, version_number) do
      {prev_number, next_number} =
        Flows.get_adjacent_version_numbers(flow.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"

      version_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/versions/#{version.version_number}/viewer"

      {:noreply,
       socket
       |> assign(:version_label, version_label(version))
       |> assign(:prev_version, prev_number)
       |> assign(:next_version, next_number)
       |> assign(:current_url, current_url)
       |> assign(:version_url, version_url)
       |> assign(:page_title, version_label(version))}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Version not found"))
         |> push_navigate(to: socket.assigns.back_url)}
    end
  end

  defp compare_url(assigns, version_number) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{assigns.flow.id}/compare/#{version_number}"
  end

  defp flow_url(workspace, project, flow) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end
end

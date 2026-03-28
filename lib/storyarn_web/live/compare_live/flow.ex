defmodule StoryarnWeb.CompareLive.Flow do
  @moduledoc """
  Side-by-side flow comparison view.

  Renders two iframes: the left shows the current flow state (compact editor),
  the right shows a historical version snapshot (read-only canvas).
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Versioning

  @impl true
  def render(assigns) do
    ~H"""
    <.vue
      v-component="compare/FlowCompare"
      v-socket={@socket}
      id="flow-compare-vue"
      back-url={@back_url}
      version-label={@version_label}
      prev-version-url={@prev_version && compare_url(assigns, @prev_version)}
      next-version-url={@next_version && compare_url(assigns, @next_version)}
      current-url={@current_url}
      version-url={@version_url}
    />
    """
  end

  # ========== Mount ==========

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => flow_id_str
        },
        _session,
        socket
      ) do
    with {flow_id, ""} <- Integer.parse(flow_id_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(
             socket.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         flow when not is_nil(flow) <- Flows.get_flow_brief(project.id, flow_id) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:workspace, project.workspace)
       |> assign(:flow, flow)
       |> assign(:back_url, flow_url(project, flow))
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
         |> put_flash(:error, dgettext("flows", "Flow not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_str}, _url, socket) do
    %{flow: flow, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_str),
         version when not is_nil(version) <-
           Versioning.get_version("flow", flow.id, version_number) do
      version_label =
        if version.title do
          "v#{version.version_number} — #{version.title}"
        else
          "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
        end

      {prev_number, next_number} =
        Versioning.get_adjacent_version_numbers("flow", flow.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"

      version_url =
        "#version-viewer-pending"

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
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{assigns.flow.id}/compare/#{version_number}"
  end

  defp flow_url(project, flow) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end
end

defmodule StoryarnWeb.SceneLive.Compare do
  @moduledoc """
  Side-by-side comparison for the current Scene and one of its versions.

  This surface belongs to the Scenes boundary: both the Scene read model and
  version navigation are obtained exclusively through `Storyarn.Scenes`.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Scenes

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/compare/VersioningCompare"
        v-socket={@socket}
        v-inject="compare-layout"
        id="scene-compare-vue"
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
  def mount(%{"id" => scene_id_string}, _session, socket) do
    %{project: project, workspace: workspace} = socket.assigns

    with {scene_id, ""} <- Integer.parse(scene_id_string),
         scene when not is_nil(scene) <- Scenes.get_scene_brief(project.id, scene_id) do
      {:ok,
       socket
       |> assign(:scene, scene)
       |> assign(:back_url, scene_url(workspace, project, scene))
       |> assign(:version_label, "")
       |> assign(:prev_version, nil)
       |> assign(:next_version, nil)
       |> assign(:current_url, "")
       |> assign(:version_url, ""), layout: false}
    else
      _error ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "Scene not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_string}, _url, socket) do
    %{scene: scene, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_string),
         version when not is_nil(version) <- Scenes.get_version(scene.id, version_number) do
      {previous_number, next_number} =
        Scenes.get_adjacent_version_numbers(scene.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}?layout=compact"

      version_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/versions/#{version.version_number}/viewer"

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
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{assigns.scene.id}/compare/#{version_number}"
  end

  defp scene_url(workspace, project, scene) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end
end

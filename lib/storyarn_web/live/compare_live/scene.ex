defmodule StoryarnWeb.CompareLive.Scene do
  @moduledoc """
  Side-by-side scene comparison view.

  Renders two iframes: the left shows the current scene state (compact editor),
  the right shows a historical version snapshot (read-only canvas).
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Versioning

  @impl true
  def render(assigns) do
    ~H"""
    <.vue
      v-component="compare/SceneCompare"
      v-socket={@socket}
      id="scene-compare-vue"
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
          "id" => scene_id_str
        },
        _session,
        socket
      ) do
    with {scene_id, ""} <- Integer.parse(scene_id_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(
             socket.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         scene when not is_nil(scene) <- Scenes.get_scene_brief(project.id, scene_id) do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:workspace, project.workspace)
       |> assign(:scene, scene)
       |> assign(:back_url, scene_url(project, scene))
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
         |> put_flash(:error, dgettext("scenes", "Scene not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  @impl true
  def handle_params(%{"version_number" => version_number_str}, _url, socket) do
    %{scene: scene, workspace: workspace, project: project} = socket.assigns

    with {version_number, ""} <- Integer.parse(version_number_str),
         version when not is_nil(version) <-
           Versioning.get_version("scene", scene.id, version_number) do
      version_label =
        if version.title do
          "v#{version.version_number} — #{version.title}"
        else
          "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
        end

      {prev_number, next_number} =
        Versioning.get_adjacent_version_numbers("scene", scene.id, version.version_number)

      current_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}?layout=compact"

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
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{assigns.scene.id}/compare/#{version_number}"
  end

  defp scene_url(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end
end

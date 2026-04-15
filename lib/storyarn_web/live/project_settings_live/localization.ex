defmodule StoryarnWeb.ProjectSettingsLive.Localization do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
      back_label={dgettext("projects", "Back to project")}
      sidebar_sections={project_settings_sections(@workspace, @project)}
    >
      <:title>{dgettext("projects", "Localization")}</:title>
      <:subtitle>{dgettext("projects", "Translation provider configuration")}</:subtitle>

      <.vue
        v-component="modules/project-settings/Localization"
        v-socket={@socket}
        id="project-settings-localization"
        provider-api-endpoint={provider_endpoint(@provider_form)}
        has-api-key={@has_api_key}
        provider-usage={serialize_provider_usage(@provider_usage)}
      />
    </Layouts.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp provider_endpoint(nil), do: "https://api-free.deepl.com"

  defp provider_endpoint(form) do
    case form[:api_endpoint] do
      %{value: val} when is_binary(val) -> val
      _ -> "https://api-free.deepl.com"
    end
  end

  defp serialize_provider_usage(nil), do: nil

  defp serialize_provider_usage(usage) do
    %{
      characterCount: usage.character_count,
      characterLimit: usage.character_limit
    }
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) do
          provider_config = get_provider_config(project.id)

          socket =
            socket
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:membership, membership)
            |> assign(:current_workspace, project.workspace)
            |> assign(
              :provider_form,
              to_form(provider_changeset(provider_config), as: "provider")
            )
            |> assign(
              :has_api_key,
              provider_config != nil && provider_config.api_key_encrypted != nil
            )
            |> assign(:provider_usage, nil)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(
             :error,
             dgettext("projects", "You don't have permission to manage this project.")
           )
           |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    socket =
      socket
      |> assign(:page_title, dgettext("projects", "Project Settings"))
      |> assign(:current_path, current_path)

    {:noreply, socket}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("save_provider_config", %{"provider" => params}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_save_provider_config(socket, params)
    end)
  end

  def handle_event("test_provider_connection", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      do_test_provider_connection(socket)
    end)
  end
end

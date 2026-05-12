defmodule StoryarnWeb.ProjectSettingsLive.Localization do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias StoryarnWeb.Components.SettingsLayout
  alias StoryarnWeb.Helpers.Authorize

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      workspace={@workspace}
      project={@project}
    >
      <:title>{dgettext("projects", "Localization")}</:title>
      <:subtitle>{dgettext("projects", "Translation provider configuration")}</:subtitle>

      <.vue
        v-component="live/project/settings/Localization"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-localization"
        provider-api-endpoint={provider_endpoint(@provider_form)}
        has-api-key={@has_api_key}
        provider-usage={serialize_provider_usage(@provider_usage)}
      />
    </SettingsLayout.settings>
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
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      provider_config = get_provider_config(project.id)

      socket =
        socket
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
       |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
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

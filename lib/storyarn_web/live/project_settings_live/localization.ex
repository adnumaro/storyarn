defmodule StoryarnWeb.ProjectSettingsLive.Localization do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
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
        v-component="live/project/settings/ProjectSettingsLocalization"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-localization"
        provider-api-endpoint={provider_endpoint(@provider_form)}
        has-api-key={@has_api_key}
        provider-usage={serialize_provider_usage(@provider_usage)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
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
      save_provider_config(socket, params)
    end)
  end

  def handle_event("test_provider_connection", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      test_provider_connection(socket)
    end)
  end

  defp save_provider_config(socket, params) do
    params =
      if String.trim(params["api_key_encrypted"] || "") == "" do
        Map.delete(params, "api_key_encrypted")
      else
        Map.update!(params, "api_key_encrypted", &String.trim/1)
      end

    case Localization.upsert_provider_config(socket.assigns.project, params) do
      {:ok, config} ->
        socket =
          socket
          |> assign(:provider_form, to_form(provider_changeset(config), as: "provider"))
          |> assign(:has_api_key, not is_nil(config.api_key_encrypted))
          |> assign(:provider_usage, nil)
          |> put_flash(:info, dgettext("projects", "Provider settings saved."))

        {:reply, %{ok: true}, socket}

      {:error, changeset} ->
        socket =
          assign(
            socket,
            :provider_form,
            changeset |> Map.put(:action, :validate) |> to_form(as: "provider")
          )

        {:reply, %{ok: false, errors: changeset_errors(changeset)}, socket}
    end
  end

  defp test_provider_connection(socket) do
    config = Localization.get_provider_config(socket.assigns.project.id)

    if is_nil(config) or is_nil(config.api_key_encrypted) do
      {:reply, %{ok: false, error: "no_api_key"}, socket}
    else
      case Localization.get_deepl_usage(config) do
        {:ok, usage} ->
          socket =
            socket
            |> assign(:provider_usage, usage)
            |> put_flash(:info, dgettext("projects", "Connection successful."))

          {:reply, %{ok: true, usage: serialize_provider_usage(usage)}, socket}

        {:error, reason} ->
          {:reply, %{ok: false, error: inspect(reason)}, socket}
      end
    end
  end

  defp changeset_errors(changeset) do
    Map.new(changeset.errors, fn {field, {message, _metadata}} -> {field, message} end)
  end
end

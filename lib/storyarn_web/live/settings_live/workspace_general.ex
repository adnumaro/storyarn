defmodule StoryarnWeb.SettingsLive.WorkspaceGeneral do
  @moduledoc """
  LiveView for workspace general settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.AI
  alias Storyarn.Assets
  alias Storyarn.Assets.ImageProcessor
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.UploadPolicy
  alias Storyarn.FeatureFlags
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.PrivateMedia

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if Workspaces.can?(membership.role, :access_workspace_general_settings) do
      changeset = Workspaces.change_workspace(workspace)

      {:ok,
       socket
       |> assign(:page_title, dgettext("workspaces", "Workspace Settings"))
       |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/general")
       |> assign(:form, to_form(changeset))
       |> assign_ai_settings()}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("workspaces", "You don't have permission to manage this workspace.")
       )
       |> push_navigate(to: ~p"/users/settings")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      general_workspace_slugs={@general_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsGeneral"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-general"
        workspace-name={@workspace.name || ""}
        workspace-description={@workspace.description || ""}
        workspace-banner-url={PrivateMedia.workspace_banner_url(@workspace) || ""}
        source-locale={@workspace.source_locale || ""}
        language-options={LanguagePickerOption.all()}
        is-owner={@membership.role == "owner"}
        can-edit-workspace={Workspaces.can?(@membership.role, :manage_workspace)}
        ai={serialize_ai_settings(assigns)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("update_managed_ai_policy", %{"enabled" => enabled}, socket) when is_boolean(enabled) do
    if FeatureFlags.enabled?(:ai_integrations, for: socket.assigns.current_scope.user) do
      update_managed_ai_policy(socket, enabled)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
    end
  end

  def handle_event("update_managed_ai_policy", _params, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
  end

  def handle_event("update_personal_ai_policy", %{"enabled" => enabled}, socket) when is_boolean(enabled) do
    if FeatureFlags.enabled?(:ai_integrations, for: socket.assigns.current_scope.user) do
      update_personal_ai_policy(socket, enabled)
    else
      {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI policy could not be updated."))}
    end
  end

  def handle_event("update_personal_ai_policy", _params, socket) do
    {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI policy could not be updated."))}
  end

  @impl true
  def handle_event("validate", %{"workspace" => workspace_params}, socket) do
    changeset =
      socket.assigns.workspace
      |> Workspaces.change_workspace(workspace_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"workspace" => workspace_params}, socket) do
    Authorize.with_authorization(socket, :manage_workspace, fn socket ->
      case Workspaces.update_workspace(socket.assigns.workspace, workspace_params) do
        {:ok, workspace} ->
          {:noreply,
           socket
           |> assign(:workspace, workspace)
           |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
           |> put_flash(:info, dgettext("workspaces", "Workspace updated successfully."))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end)
  end

  @impl true
  def handle_event(
        "upload_workspace_banner",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    Authorize.with_authorization(socket, :manage_workspace, fn socket ->
      with [header, base64_data] <- split_banner_data(data),
           {:ok, profile} <- UploadPolicy.profile_for(:banner),
           :ok <- validate_banner_metadata(profile, filename, content_type, header),
           :ok <- UploadPolicy.validate_base64_size(profile, base64_data),
           {:ok, binary_data} <- Base.decode64(base64_data),
           :ok <- validate_banner_binary(profile, binary_data, content_type),
           safe_filename = Assets.sanitize_filename(filename),
           key = "workspaces/#{socket.assigns.workspace.slug}/banner/#{safe_filename}",
           {:ok, url} <- Storage.upload(key, binary_data, content_type),
           {:ok, workspace} <-
             Workspaces.update_workspace(socket.assigns.workspace, %{banner_url: url}) do
        {:noreply,
         socket
         |> assign(:workspace, workspace)
         |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
         |> put_flash(:info, dgettext("workspaces", "Banner uploaded successfully."))}
      else
        _ ->
          {:noreply,
           put_flash(
             socket,
             :error,
             dgettext("workspaces", "Invalid file data or upload failed.")
           )}
      end
    end)
  end

  @impl true
  def handle_event("remove_workspace_banner", _params, socket) do
    Authorize.with_authorization(socket, :manage_workspace, fn socket ->
      case Workspaces.update_workspace(socket.assigns.workspace, %{banner_url: nil}) do
        {:ok, workspace} ->
          {:noreply,
           socket
           |> assign(:workspace, workspace)
           |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
           |> put_flash(:info, dgettext("workspaces", "Banner removed successfully."))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    # Only owner can delete workspace
    if socket.assigns.membership.role == "owner" do
      case Workspaces.delete_workspace(socket.assigns.workspace) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("workspaces", "Workspace deleted."))
           |> push_navigate(to: ~p"/users/settings")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("workspaces", "Failed to delete workspace."))}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("workspaces", "Only the workspace owner can delete the workspace.")
       )}
    end
  end

  defp split_banner_data(data) when is_binary(data), do: String.split(data, ",", parts: 2)
  defp split_banner_data(_data), do: []

  defp validate_banner_metadata(profile, filename, content_type, header)
       when is_binary(filename) and is_binary(content_type) and is_binary(header) do
    safe_filename = Assets.sanitize_filename(filename)

    with true <- String.trim(filename) != "",
         true <- safe_filename not in ["", ".", ".."],
         true <- header == "data:#{content_type};base64",
         true <- MIME.from_path(safe_filename) == content_type,
         :ok <- UploadPolicy.validate(profile, %{content_type: content_type, size: 0}) do
      :ok
    else
      _ -> {:error, :invalid_banner_upload}
    end
  end

  defp validate_banner_metadata(_profile, _filename, _content_type, _header), do: {:error, :invalid_banner_upload}

  defp validate_banner_binary(profile, binary_data, content_type) do
    with :ok <-
           UploadPolicy.validate(profile, %{
             content_type: content_type,
             size: byte_size(binary_data)
           }),
         {:ok, ^content_type} <- ImageProcessor.content_type_from_binary(binary_data) do
      :ok
    else
      _ -> {:error, :invalid_banner_upload}
    end
  end

  defp assign_ai_settings(socket) do
    user = socket.assigns.current_scope.user
    visible? = FeatureFlags.enabled?(:ai_integrations, for: user)

    if visible? do
      {:ok, policy} = AI.get_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id)
      {:ok, allowance} = AI.allowance_summary(socket.assigns.current_scope, socket.assigns.workspace.id)

      socket
      |> assign(:ai_visible, true)
      |> assign(:ai_policy_lanes, policy.allowed_lanes)
      |> assign(:ai_managed_allowed, "managed" in policy.allowed_lanes)
      |> assign(:ai_personal_allowed, "personal_byok" in policy.allowed_lanes)
      |> assign(:ai_allowance, allowance)
      |> assign(:ai_provenance, AI.managed_provenance())
    else
      socket
      |> assign(:ai_visible, false)
      |> assign(:ai_policy_lanes, [])
      |> assign(:ai_managed_allowed, false)
      |> assign(:ai_personal_allowed, false)
      |> assign(:ai_allowance, %{})
      |> assign(:ai_provenance, nil)
    end
  end

  defp update_personal_ai_policy(socket, enabled) do
    lanes =
      if enabled,
        do: Enum.uniq(["personal_byok" | socket.assigns.ai_policy_lanes]),
        else: List.delete(socket.assigns.ai_policy_lanes, "personal_byok")

    case AI.update_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id, lanes) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign_ai_settings()
         |> put_flash(:info, dgettext("workspaces", "Personal AI policy updated."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("workspaces", "Only the workspace owner can change Personal AI policy."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Personal AI policy could not be updated."))}
    end
  end

  defp update_managed_ai_policy(socket, enabled) do
    lanes =
      if enabled,
        do: Enum.uniq(["managed" | socket.assigns.ai_policy_lanes]),
        else: List.delete(socket.assigns.ai_policy_lanes, "managed")

    case AI.update_workspace_policy(socket.assigns.current_scope, socket.assigns.workspace.id, lanes) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign_ai_settings()
         |> put_flash(:info, dgettext("workspaces", "Storyarn AI policy updated."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("workspaces", "Only the workspace owner can change Storyarn AI policy."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("workspaces", "Storyarn AI policy could not be updated."))}
    end
  end

  defp serialize_ai_allowance(%{} = allowance) do
    %{
      status: Map.get(allowance, :status),
      availableUnits: Map.get(allowance, :available_units, 0),
      reservedUnits: Map.get(allowance, :reserved_units, 0),
      committedUnits: Map.get(allowance, :committed_units, 0)
    }
  end

  defp serialize_ai_provenance(%{} = provenance) do
    %{
      provider: Map.get(provenance, :provider),
      model: Map.get(provenance, :model),
      region: Map.get(provenance, :region),
      dataRetention: Map.get(provenance, :data_retention),
      trainingUsage: Map.get(provenance, :training_usage)
    }
  end

  defp serialize_ai_provenance(nil), do: nil

  defp serialize_ai_settings(assigns) do
    %{
      visible: assigns.ai_visible,
      managedAllowed: assigns.ai_managed_allowed,
      personalAllowed: assigns.ai_personal_allowed,
      allowance: serialize_ai_allowance(assigns.ai_allowance),
      provenance: serialize_ai_provenance(assigns.ai_provenance)
    }
  end
end

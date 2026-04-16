defmodule StoryarnWeb.SettingsLive.WorkspaceGeneral do
  @moduledoc """
  LiveView for workspace general settings.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Localization
  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if membership.role in ["owner", "admin"] do
      changeset = Workspaces.change_workspace(workspace)

      {:ok,
       socket
       |> assign(:page_title, dgettext("workspaces", "Workspace Settings"))
       |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/general")
       |> assign(:form, to_form(changeset))}
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
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      managed_workspace_slugs={@managed_workspace_slugs}
      current_path={@current_path}
    >
      <.vue
        v-component="modules/settings/WorkspaceGeneral"
        v-socket={@socket}
        id="workspace-settings-general"
        workspace-name={@workspace.name || ""}
        workspace-description={@workspace.description || ""}
        workspace-banner-url={@workspace.banner_url || ""}
        source-locale={@workspace.source_locale || ""}
        language-options={
          Enum.map(Localization.language_options_for_select(), fn {k, v} -> [k, v] end)
        }
        is-owner={@membership.role == "owner"}
      />
    </Layouts.settings>
    """
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
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data),
           key = "workspaces/#{socket.assigns.workspace.slug}/banner/#{filename}",
           {:ok, url} <- Storyarn.Assets.Storage.upload(key, binary_data, content_type),
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
end

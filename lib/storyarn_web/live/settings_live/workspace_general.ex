defmodule StoryarnWeb.SettingsLive.WorkspaceGeneral do
  @moduledoc """
  Workspace › General: identity, banner and source language, plus the danger
  zone. Only the owner edits; admins and members read.
  """
  use StoryarnWeb, :live_view

  alias Storyarn.Workspaces
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.SaveStatusTimer
  alias StoryarnWeb.LanguagePickerOption
  alias StoryarnWeb.Live.Hooks.SettingsNav
  alias StoryarnWeb.PrivateMedia

  @impl true
  def mount(_params, _session, socket) do
    stale_workspace = socket.assigns.workspace

    if connected?(socket) do
      :ok = Workspaces.subscribe_workspace_ownership_changes(stale_workspace.id)
    end

    case Workspaces.authorize(
           socket.assigns.current_scope,
           stale_workspace.id,
           :access_workspace_general_settings
         ) do
      {:ok, workspace, membership} ->
        changeset = Workspaces.change_workspace(workspace)

        {:ok,
         socket
         |> assign(:workspace, workspace)
         |> assign(:membership, membership)
         |> assign(:page_title, dgettext("workspaces", "Workspace Settings"))
         |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/general")
         |> assign(:form, to_form(changeset))
         |> assign(:save_status, :idle)}

      {:error, _reason} ->
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
      current_path={@current_path}
      settings_nav={@settings_nav}
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
        language-options={source_locale_options()}
        is-owner={@workspace.owner_id == @current_scope.user.id}
        can-edit-workspace={
          @workspace.owner_id == @current_scope.user.id and
            Workspaces.can?(@membership.role, :manage_workspace)
        }
        save-status={Atom.to_string(@save_status)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
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

  def handle_event("save", %{"workspace" => workspace_params}, socket) do
    Authorize.with_authorization(
      socket,
      :manage_workspace,
      fn socket ->
        case Workspaces.update_workspace(
               socket.assigns.current_scope,
               socket.assigns.workspace.id,
               workspace_params
             ) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:workspace, workspace)
             |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
             |> SaveStatusTimer.mark_saved()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}

          {:error, :ownership_invariant_violation} ->
            workspace_update_ownership_invariant_error(socket)

          {:error, :unauthorized} ->
            workspace_update_unauthorized_error(socket)
        end
      end,
      &workspace_owner_authorization_failure/2
    )
  end

  def handle_event(
        "upload_workspace_banner",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    Authorize.with_authorization(
      socket,
      :manage_workspace,
      fn socket ->
        attrs = %{filename: filename, content_type: content_type, data: data}

        case Workspaces.upload_workspace_banner(
               socket.assigns.current_scope,
               socket.assigns.workspace.id,
               attrs
             ) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:workspace, workspace)
             |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
             |> put_flash(:info, dgettext("workspaces", "Banner uploaded successfully."))}

          {:error, :ownership_invariant_violation} ->
            workspace_update_ownership_invariant_error(socket)

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("workspaces", "Invalid file data or upload failed.")
             )}
        end
      end,
      &workspace_owner_authorization_failure/2
    )
  end

  def handle_event("remove_workspace_banner", _params, socket) do
    Authorize.with_authorization(
      socket,
      :manage_workspace,
      fn socket ->
        case Workspaces.remove_workspace_banner(
               socket.assigns.current_scope,
               socket.assigns.workspace.id
             ) do
          {:ok, workspace} ->
            {:noreply,
             socket
             |> assign(:workspace, workspace)
             |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
             |> put_flash(:info, dgettext("workspaces", "Banner removed successfully."))}

          {:error, :ownership_invariant_violation} ->
            workspace_update_ownership_invariant_error(socket)

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("workspaces", "Banner could not be removed.")
             )}
        end
      end,
      &workspace_owner_authorization_failure/2
    )
  end

  def handle_event("delete", _params, socket) do
    Authorize.with_authorization(
      socket,
      :manage_workspace,
      fn socket ->
        case Workspaces.delete_workspace(
               socket.assigns.current_scope,
               socket.assigns.workspace.id
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, dgettext("workspaces", "Workspace deleted."))
             |> push_navigate(to: ~p"/users/settings")}

          {:error, :ownership_invariant_violation} ->
            workspace_update_ownership_invariant_error(socket)

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("workspaces", "Failed to delete workspace."))}
        end
      end,
      &workspace_owner_authorization_failure/2
    )
  end

  @impl true
  def handle_info(
        {:workspace_ownership_transferred, %{workspace_id: workspace_id}},
        %{assigns: %{workspace: %{id: workspace_id}}} = socket
      ) do
    case Workspaces.authorize(
           socket.assigns.current_scope,
           workspace_id,
           :access_workspace_general_settings
         ) do
      {:ok, workspace, membership} ->
        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:membership, membership)
          |> assign(:form, to_form(Workspaces.change_workspace(workspace)))
          |> refresh_workspace_navigation()

        {:noreply, assign(socket, :settings_nav, SettingsNav.build_nav(socket.assigns))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("workspaces", "You don't have permission to manage this workspace.")
         )
         |> push_navigate(to: ~p"/users/settings")}
    end
  end

  def handle_info({:reset_save_status, token}, socket) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply, assign(socket, :save_status, :idle)}
    else
      {:noreply, socket}
    end
  end

  defp workspace_update_ownership_invariant_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext(
         "workspaces",
         "Storyarn could not verify the current workspace owner, so no changes were made. Contact support if the problem continues."
       )
     )}
  end

  defp workspace_update_unauthorized_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("workspaces", "Only the current workspace owner can update this workspace.")
     )}
  end

  defp workspace_owner_authorization_failure(socket, :ownership_invariant_violation) do
    workspace_update_ownership_invariant_error(socket)
  end

  defp workspace_owner_authorization_failure(socket, _reason) do
    {:noreply,
     put_flash(
       socket,
       :error,
       gettext("You don't have permission to perform this action.")
     )}
  end

  defp source_locale_options do
    Enum.map(Workspaces.source_locale_options(), fn locale ->
      LanguagePickerOption.from_code(locale.code, label: locale.name)
    end)
  end

  # The rail derives workspace access from these assigns; refresh them after an
  # ownership transfer so the nav reflects the new roles without a reload.
  defp refresh_workspace_navigation(socket) do
    workspace_data = Workspaces.list_workspaces(socket.assigns.current_scope)

    managed_slugs =
      workspace_data
      |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_settings))
      |> MapSet.new(& &1.workspace.slug)

    general_slugs =
      workspace_data
      |> Enum.filter(&Workspaces.can?(&1.role, :access_workspace_general_settings))
      |> MapSet.new(& &1.workspace.slug)

    socket
    |> assign(:workspaces, Enum.map(workspace_data, & &1.workspace))
    |> assign(:managed_workspace_slugs, managed_slugs)
    |> assign(:general_workspace_slugs, general_slugs)
  end
end

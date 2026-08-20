defmodule StoryarnWeb.SettingsLive.WorkspaceImports do
  @moduledoc """
  Imports a downloaded project snapshot into the current workspace.

  Admission is synchronous: the snapshot is validated and workspace storage is
  reserved before the durable background import appears in the UI.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if Workspaces.can?(membership.role, :access_workspace_settings) do
      socket =
        socket
        |> assign(:page_title, dgettext("workspaces", "Imports"))
        |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/imports")
        |> assign(:quota_rejection, nil)
        |> assign(:request_error_code, nil)
        |> assign(:upload_error_code, nil)
        |> allow_upload(:snapshot_zip,
          accept: [".zip"],
          max_entries: 1,
          max_file_size: ProjectSnapshotArchiveReader.max_archive_size_bytes()
        )
        |> reload_imports()

      if connected?(socket) do
        :ok = Versioning.subscribe_workspace_snapshot_imports(workspace.id)
      end

      {:ok, socket}
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
        v-component="live/workspace/settings/WorkspaceSettingsImports"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-imports"
        imports={serialize_imports(@workspace, @imports)}
        quota-rejection={serialize_quota_rejection(@quota_rejection)}
        request-error-code={@request_error_code}
        upload-error-code={@upload_error_code}
        upload-config={@uploads.snapshot_zip}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  @impl true
  def handle_event("validate_snapshot_zip", _params, socket) do
    errors =
      for entry <- socket.assigns.uploads.snapshot_zip.entries,
          error <- upload_errors(socket.assigns.uploads.snapshot_zip, entry),
          do: error

    {:noreply,
     socket
     |> assign(:quota_rejection, nil)
     |> assign(:request_error_code, nil)
     |> assign(:upload_error_code, upload_error_code(List.first(errors)))}
  end

  def handle_event("import_snapshot", _params, socket) do
    case Workspaces.authorize(
           socket.assigns.current_scope,
           socket.assigns.workspace.id,
           :access_workspace_settings
         ) do
      {:ok, workspace, _membership} ->
        results = consume_snapshot_upload(socket, workspace)
        {:noreply, apply_request_result(socket, List.first(results))}

      {:error, _reason} ->
        {:noreply, assign(socket, :request_error_code, "unauthorized")}
    end
  end

  @impl true
  def handle_info({:workspace_snapshot_import_updated, _import}, socket) do
    {:noreply, reload_imports(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp consume_snapshot_upload(socket, workspace) do
    consume_uploaded_entries(socket, :snapshot_zip, fn %{path: path}, entry ->
      result =
        Versioning.request_workspace_snapshot_import(
          socket.assigns.current_scope,
          workspace,
          path,
          %{original_filename: entry.client_name}
        )

      {:ok, result}
    end)
  end

  defp apply_request_result(socket, {:ok, _import}) do
    socket
    |> assign(:quota_rejection, nil)
    |> assign(:request_error_code, nil)
    |> assign(:upload_error_code, nil)
    |> reload_imports()
  end

  defp apply_request_result(
         socket,
         {:error, :limit_reached, %{required_bytes: required, available_bytes: available, limit_bytes: limit}}
       ) do
    socket
    |> assign(:quota_rejection, %{
      required_bytes: required,
      available_bytes: available,
      limit_bytes: limit
    })
    |> assign(:request_error_code, nil)
    |> assign(:upload_error_code, nil)
    |> reload_imports()
  end

  defp apply_request_result(socket, {:error, reason}) do
    socket
    |> assign(:quota_rejection, nil)
    |> assign(:request_error_code, request_error_code(reason))
    |> assign(:upload_error_code, nil)
    |> reload_imports()
  end

  defp apply_request_result(socket, nil) do
    assign(socket, :request_error_code, "invalid_file")
  end

  defp reload_imports(socket) do
    imports =
      Versioning.list_workspace_snapshot_imports(
        socket.assigns.current_scope,
        socket.assigns.workspace
      )

    assign(socket, :imports, imports)
  end

  defp serialize_imports(workspace, imports) do
    Enum.map(imports, &serialize_import(workspace, &1))
  end

  defp serialize_import(workspace, import) do
    project = Map.get(import, :project)

    %{
      id: Map.fetch!(import, :id),
      fileName: Map.get(import, :original_filename),
      projectName: Map.get(import, :project_name) || project_name(project),
      status: Map.get(import, :status),
      phase: Map.get(import, :stage),
      progressBytes: serialize_byte_count(Map.get(import, :progress_bytes, 0)),
      progressTotalBytes: serialize_optional_byte_count(Map.get(import, :progress_total_bytes)),
      attempt: Map.get(import, :attempt, 0),
      maxAttempts: Map.get(import, :max_attempts),
      insertedAt: serialize_datetime(Map.get(import, :inserted_at)),
      completedAt: serialize_datetime(Map.get(import, :completed_at)),
      failureCode: Map.get(import, :failure_code),
      projectPath: project_path(workspace, project)
    }
  end

  defp serialize_quota_rejection(nil), do: nil

  defp serialize_quota_rejection(rejection) do
    %{
      requiredBytes: serialize_byte_count(rejection.required_bytes),
      availableBytes: serialize_byte_count(rejection.available_bytes),
      limitBytes: serialize_byte_count(rejection.limit_bytes)
    }
  end

  defp serialize_byte_count(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)
  defp serialize_byte_count(value) when is_binary(value), do: value
  defp serialize_byte_count(_value), do: "0"

  defp serialize_optional_byte_count(nil), do: nil
  defp serialize_optional_byte_count(value), do: serialize_byte_count(value)

  defp serialize_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp serialize_datetime(_value), do: nil

  defp project_name(%{name: name}) when is_binary(name), do: name
  defp project_name(_project), do: nil

  defp project_path(workspace, %{slug: slug, deleted_at: nil}) when is_binary(slug) do
    ~p"/workspaces/#{workspace.slug}/projects/#{slug}"
  end

  defp project_path(_workspace, _project), do: nil

  defp upload_error_code(:too_large), do: "file_too_large"
  defp upload_error_code(:not_accepted), do: "invalid_file"
  defp upload_error_code(:too_many_files), do: "invalid_file"
  defp upload_error_code(nil), do: nil
  defp upload_error_code(_error), do: "invalid_file"

  defp request_error_code(reason)
       when reason in [
              :invalid_archive,
              :invalid_snapshot_archive,
              :invalid_snapshot_manifest,
              :invalid_snapshot_zip,
              :snapshot_archive_corrupt,
              :unsupported_snapshot_format
            ], do: "invalid_file"

  defp request_error_code({reason, _details})
       when reason in [
              :invalid_archive,
              :invalid_snapshot_archive,
              :invalid_snapshot_manifest,
              :snapshot_archive_corrupt,
              :snapshot_size_limit_exceeded
            ], do: "invalid_file"

  defp request_error_code(:unauthorized), do: "unauthorized"
  defp request_error_code(_reason), do: "unavailable"
end

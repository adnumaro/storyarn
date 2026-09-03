defmodule StoryarnWeb.SettingsLive.WorkspaceProjects do
  @moduledoc """
  Workspace › Projects: import a downloaded project snapshot into the
  workspace, follow the import history, and see the projects retained in the
  workspace trash.

  The browser uploads directly to object storage in production. Admission then
  validates the bounded archive metadata and reserves workspace capacity before
  the durable background import starts. The former `/imports` and
  `/deleted-projects` pages redirect here.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: action}} = socket)
      when action in [:legacy_imports, :legacy_deleted_projects] do
    {:ok,
     push_navigate(socket,
       to: ~p"/users/settings/workspaces/#{socket.assigns.workspace.slug}/projects",
       replace: true
     )}
  end

  def mount(_params, _session, socket) do
    %{workspace: workspace, membership: membership} = socket.assigns

    if Workspaces.can?(membership.role, :access_workspace_settings) do
      socket =
        socket
        |> assign(:page_title, dgettext("workspaces", "Projects"))
        |> assign(:current_path, ~p"/users/settings/workspaces/#{workspace.slug}/projects")
        |> assign(:quota_rejection, nil)
        |> assign(:request_error_code, nil)
        |> assign(:upload_error_code, nil)
        |> assign(:external_upload?, Projects.external_project_storage?())
        |> allow_snapshot_upload()
        |> reload_imports()
        |> reload_deleted_projects()

      if connected?(socket) do
        :ok = Projects.subscribe_workspace_snapshot_imports(workspace.id)
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
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/workspace/settings/WorkspaceSettingsProjects"
        v-socket={@socket}
        v-inject="settings-layout"
        id="workspace-settings-projects"
        imports={serialize_imports(@workspace, @imports)}
        quota-rejection={serialize_quota_rejection(@quota_rejection)}
        request-error-code={@request_error_code}
        upload-error-code={@upload_error_code}
        upload-config={@uploads.snapshot_zip}
        deleted-projects={serialize_deleted_projects(@deleted_projects)}
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

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    meta = upload_meta(socket, ref)
    maybe_cancel_upload_owner(socket, meta)

    {:noreply,
     socket
     |> cancel_upload(:snapshot_zip, ref)
     |> reload_imports()}
  end

  def handle_event("cancel_snapshot_upload", %{"id" => import_id}, socket) do
    case Integer.parse(to_string(import_id)) do
      {id, ""} ->
        _ =
          Projects.cancel_workspace_snapshot_upload(
            socket.assigns.current_scope,
            socket.assigns.workspace.id,
            id
          )

        {:noreply, socket |> cancel_upload_entry(id) |> reload_imports()}

      _invalid ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:workspace_snapshot_import_updated, %{id: id, __meta__: %Ecto.Schema.Metadata{state: :deleted}}},
        socket
      ) do
    {:noreply,
     socket
     |> push_event("workspace-snapshot-upload-cancelled", %{import_id: id})
     |> cancel_upload_entry(id)
     |> reload_imports()}
  end

  def handle_info({:workspace_snapshot_import_updated, _import}, socket) do
    {:noreply, socket |> reload_imports() |> reload_deleted_projects()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp consume_snapshot_upload(%{assigns: %{external_upload?: false}} = socket, workspace) do
    consume_uploaded_entries(socket, :snapshot_zip, fn %{path: path}, entry ->
      result =
        Projects.request_workspace_snapshot_import(
          socket.assigns.current_scope,
          workspace.id,
          path,
          %{original_filename: entry.client_name}
        )

      {:ok, result}
    end)
  end

  defp consume_snapshot_upload(%{assigns: %{external_upload?: true}} = socket, workspace) do
    consume_uploaded_entries(socket, :snapshot_zip, fn %{import_id: import_id}, _entry ->
      {:ok,
       Projects.request_stored_workspace_snapshot_import(
         socket.assigns.current_scope,
         workspace.id,
         import_id
       )}
    end)
  end

  defp allow_snapshot_upload(%{assigns: %{external_upload?: external?}} = socket) do
    opts = [
      accept: [".zip"],
      max_entries: 1,
      max_file_size: Projects.project_snapshot_archive_max_size_bytes(),
      progress: &snapshot_upload_progress/3
    ]

    opts = if external?, do: Keyword.put(opts, :external, &presign_snapshot_upload/2), else: opts
    allow_upload(socket, :snapshot_zip, opts)
  end

  defp presign_snapshot_upload(entry, socket) do
    result =
      Projects.prepare_external_workspace_snapshot_import(
        socket.assigns.current_scope,
        socket.assigns.workspace.id,
        %{original_filename: entry.client_name, archive_size_bytes: entry.client_size}
      )

    case result do
      {:ok, direct} ->
        meta = %{uploader: "WorkspaceSnapshot", url: direct.url, headers: direct.headers, import_id: direct.import_id}
        {:ok, meta, socket}

      {:error, _reason} = error ->
        {:error, %{reason: request_error_code(elem(error, 1))}, apply_request_result(socket, error)}

      {:error, _reason, _details} = error ->
        {:error, %{reason: "quota"}, apply_request_result(socket, error)}
    end
  end

  defp snapshot_upload_progress(:snapshot_zip, entry, socket) do
    meta = upload_meta(socket, entry.ref)

    if upload_errors(socket.assigns.uploads.snapshot_zip, entry) == [] do
      with %{import_id: import_id} <- meta do
        _ =
          Projects.update_workspace_snapshot_upload_progress(
            socket.assigns.current_scope,
            socket.assigns.workspace.id,
            import_id,
            entry.progress
          )
      end

      {:noreply, socket}
    else
      maybe_cancel_upload_owner(socket, meta)

      {:noreply,
       socket |> cancel_upload(:snapshot_zip, entry.ref) |> assign(:upload_error_code, "unavailable") |> reload_imports()}
    end
  end

  defp upload_meta(socket, ref), do: Map.get(socket.assigns.uploads.snapshot_zip.entry_refs_to_metas, ref, %{})

  defp cancel_upload_entry(socket, import_id) do
    ref =
      Enum.find_value(socket.assigns.uploads.snapshot_zip.entry_refs_to_metas, fn {ref, meta} ->
        if Map.get(meta, :import_id) == import_id, do: ref
      end)

    if ref, do: cancel_upload(socket, :snapshot_zip, ref), else: socket
  end

  defp maybe_cancel_upload_owner(socket, %{import_id: import_id}) do
    Projects.cancel_workspace_snapshot_upload(
      socket.assigns.current_scope,
      socket.assigns.workspace.id,
      import_id
    )
  end

  defp maybe_cancel_upload_owner(_socket, _meta), do: :ok

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
      Projects.list_workspace_snapshot_imports(
        socket.assigns.current_scope,
        socket.assigns.workspace.id
      )

    assign(socket, :imports, imports)
  end

  defp reload_deleted_projects(socket) do
    assign(socket, :deleted_projects, Projects.list_deleted_projects(socket.assigns.workspace.id))
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

  defp serialize_deleted_projects(projects) do
    Enum.map(projects, fn project ->
      %{
        id: project.id,
        name: project.name,
        deletedTimeAgo: dgettext("workspaces", "Deleted %{time_ago}", time_ago: format_time_ago(project.deleted_at)),
        deletedByText:
          if(project.deleted_by,
            do: dgettext("workspaces", "by %{email}", email: project.deleted_by.email)
          )
      }
    end)
  end

  defp format_time_ago(datetime) do
    diff = DateTime.diff(TimeHelpers.now(), datetime, :second)

    cond do
      diff < 60 ->
        dgettext("workspaces", "just now")

      diff < 3600 ->
        dngettext("workspaces", "%{count} minute ago", "%{count} minutes ago", div(diff, 60), count: div(diff, 60))

      diff < 86_400 ->
        dngettext("workspaces", "%{count} hour ago", "%{count} hours ago", div(diff, 3600), count: div(diff, 3600))

      true ->
        dngettext("workspaces", "%{count} day ago", "%{count} days ago", div(diff, 86_400), count: div(diff, 86_400))
    end
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
  defp upload_error_code(:external_client_failure), do: "unavailable"
  defp upload_error_code(%{reason: reason}) when is_binary(reason), do: reason
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
  defp request_error_code(:workspace_snapshot_import_in_progress), do: "in_progress"
  defp request_error_code(:workspace_snapshot_upload_rate_limited), do: "rate_limited"
  defp request_error_code(_reason), do: "unavailable"
end

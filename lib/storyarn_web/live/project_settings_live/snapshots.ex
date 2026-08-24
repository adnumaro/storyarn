defmodule StoryarnWeb.ProjectSettingsLive.Snapshots do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias StoryarnWeb.Helpers.Authorize

  @active_restore_statuses ~w(queued running retrying)
  @build_status_refresh_ms 2_000

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
      <:title>{dgettext("projects", "Snapshots")}</:title>
      <:subtitle>
        {dgettext("projects", "Review snapshot storage, reservations, and integrity")}
      </:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsSnapshots"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-snapshots"
        snapshots={
          serialize_snapshots(
            @project,
            @snapshots,
            @snapshot_reservations,
            @snapshot_restores,
            @snapshot_build_statuses
          )
        }
        restore-operation-active={project_restore_active?(@snapshot_restores)}
        storage-usage={serialize_storage_usage(@storage_usage, @storage_limit)}
        snapshot-limit={serialize_snapshot_limit(@snapshot_slots_used, @snapshot_slots_limit)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_snapshots(project, snapshots, reservations, restores, build_statuses) do
    restores_by_snapshot =
      Enum.reduce(restores, %{}, fn restore, acc ->
        Map.put_new(acc, restore.project_snapshot_id, restore)
      end)

    active_restore? = project_restore_active?(restores)

    Enum.map(snapshots, fn snapshot ->
      serialize_snapshot(
        project,
        snapshot,
        reservations,
        Map.get(restores_by_snapshot, snapshot.id),
        active_restore?,
        build_statuses
      )
    end)
  end

  defp serialize_snapshot(project, snapshot, reservations, restore, active_restore?, build_statuses) do
    reservation = Map.get(reservations, snapshot.id, %{active_bytes: 0, export_bytes: 0, active_count: 0})
    build_status = Map.get(build_statuses, snapshot.id, %{})
    retrying = build_status[:retrying] == true or snapshot.progress_phase == "retrying"

    %{
      id: snapshot.id,
      title: snapshot.title,
      description: snapshot.description,
      versionNumber: snapshot.version_number,
      insertedAt: serialize_datetime(snapshot.inserted_at),
      mode: snapshot.mode,
      lifecycleStatus: snapshot.lifecycle_state,
      integrityStatus: snapshot.integrity_state,
      accountedSizeBytes: serialize_optional_byte_count(snapshot.accounted_size_bytes),
      archiveSizeBytes: snapshot |> measured_archive_bytes() |> serialize_optional_byte_count(),
      sidecarSizeBytes: snapshot |> measured_sidecar_bytes() |> serialize_optional_byte_count(),
      assetCount: snapshot.asset_count,
      blobCount: snapshot.blob_count,
      activeReservationBytes: reservation |> non_export_reservation_bytes() |> serialize_byte_count(),
      exportReservationBytes: serialize_byte_count(reservation.export_bytes),
      accountingVersion: snapshot.accounting_version,
      accountingMeasuredAt: serialize_datetime(snapshot.accounting_measured_at),
      plannedSizeBytes: serialize_optional_byte_count(snapshot.total_size_bytes),
      progressPhase: snapshot.progress_phase,
      progressBytes: serialize_byte_count(snapshot.progress_bytes || 0),
      progressTotalBytes: snapshot |> measured_progress_total_bytes() |> serialize_optional_byte_count(),
      buildJobState: build_status[:job_state],
      buildAttempt: max(snapshot.build_attempt || 0, build_status[:attempt] || 0),
      buildMaxAttempts: build_status[:max_attempts],
      retrying: retrying,
      nextRetryAt: serialize_datetime(build_status[:next_retry_at]),
      retryErrorCode: if(retrying, do: build_status[:retry_error_code] || "build_failed"),
      failureCode: snapshot.failure_code,
      failureMessage: snapshot.failure_message,
      capturedAt: serialize_datetime(snapshot.captured_at),
      cancelRequestedAt: serialize_datetime(snapshot.cancel_requested_at),
      canCancel: snapshot_cancellable?(snapshot),
      canDelete: snapshot_deletable?(snapshot, reservation, active_restore?),
      deleteStatus: snapshot_delete_status(snapshot, reservation, active_restore?),
      canRestore: snapshot_restorable?(snapshot) and not active_restore?,
      restoreOperation: serialize_restore_operation(restore),
      downloadUrl: snapshot_download_url(project, snapshot),
      entityCounts: snapshot.entity_counts,
      createdByEmail: snapshot_creator_email(snapshot)
    }
  end

  defp serialize_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp serialize_datetime(_value), do: nil

  defp snapshot_cancellable?(snapshot) do
    snapshot.lifecycle_state in ["pending", "building", "verifying"] and
      snapshot.progress_phase != "finalizing" and is_nil(snapshot.cancel_requested_at)
  end

  defp snapshot_deletable?(snapshot, reservation, active_restore?) do
    snapshot_delete_status(snapshot, reservation, active_restore?) == "ready"
  end

  defp snapshot_delete_status(%{lifecycle_state: state}, _reservation, _active_restore?)
       when state not in ["ready", "failed", "cancelled"], do: nil

  defp snapshot_delete_status(_snapshot, _reservation, true), do: "restore_operation"

  defp snapshot_delete_status(_snapshot, %{active_count: 0}, false), do: "ready"

  defp snapshot_delete_status(_snapshot, %{active_count: count, active_bytes: 0}, false) when count > 0,
    do: "download_lease"

  defp snapshot_delete_status(_snapshot, _reservation, false), do: "active_operation"

  defp snapshot_restorable?(snapshot) do
    Versioning.project_snapshot_restore_enabled?() and
      snapshot.format_version == 2 and snapshot.mode == "full" and
      snapshot.lifecycle_state == "ready" and snapshot.integrity_state == "verified" and
      snapshot.accounting_version == 1 and snapshot.restore_contract_version == 1
  end

  defp serialize_restore_operation(%ProjectSnapshotRestore{} = restore) do
    %{
      id: restore.id,
      status: restore.status,
      phase: restore.phase,
      attempt: restore.attempt,
      requestedAt: serialize_datetime(restore.requested_at),
      stateUpdatedAt: serialize_datetime(restore.state_updated_at),
      completedAt: serialize_datetime(restore.completed_at),
      failedAt: serialize_datetime(restore.failed_at),
      failureCode: restore.failure_code,
      failureMessage: restore.failure_message
    }
  end

  defp serialize_restore_operation(_restore), do: nil

  defp project_restore_active?(restores) do
    Enum.any?(restores, &(&1.status in @active_restore_statuses))
  end

  defp snapshot_download_url(project, snapshot) do
    if snapshot_downloadable?(snapshot) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot.id}/download"
    end
  end

  defp snapshot_downloadable?(%{
         mode: "full",
         lifecycle_state: "ready",
         integrity_state: "verified",
         project_id: project_id,
         object_prefix: prefix,
         archive_storage_key: archive_key,
         archive_size_bytes: archive_size,
         archive_checksum: archive_checksum
       })
       when is_binary(prefix) and is_binary(archive_key) and is_integer(archive_size) and archive_size > 0 and
              is_binary(archive_checksum) do
    SnapshotArchiveStorage.ready_archive_key?(project_id, prefix, archive_key) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, archive_checksum)
  end

  defp snapshot_downloadable?(_snapshot), do: false

  defp snapshot_creator_email(%{created_by: %{email: email}}), do: email
  defp snapshot_creator_email(_snapshot), do: nil

  defp measured_archive_bytes(%{archive_size_bytes: bytes}), do: bytes
  defp measured_archive_bytes(_snapshot), do: nil

  defp measured_sidecar_bytes(%{manifest_size_bytes: bytes}), do: bytes
  defp measured_sidecar_bytes(_snapshot), do: nil

  defp measured_progress_total_bytes(%{capture_digest: nil}), do: nil
  defp measured_progress_total_bytes(snapshot), do: snapshot.progress_total_bytes

  defp non_export_reservation_bytes(%{active_bytes: active_bytes, export_bytes: export_bytes}) do
    max(active_bytes - export_bytes, 0)
  end

  defp serialize_optional_byte_count(value) when is_integer(value) and value >= 0, do: serialize_byte_count(value)

  defp serialize_optional_byte_count(_value), do: nil

  defp serialize_snapshot_limit(used, limit) do
    %{
      used: used,
      limit: if(is_integer(limit) and limit >= 0, do: limit)
    }
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      accounting = snapshot_storage_accounting(project)
      restores = Versioning.list_project_snapshot_restores(project.id)

      if connected?(socket) do
        Versioning.subscribe_project_snapshots(project.id)
        Versioning.subscribe_project_snapshot_restores(project.id)
      end

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:snapshots, accounting.snapshots)
        |> assign(:snapshot_reservations, accounting.snapshot_reservations)
        |> assign(:snapshot_slots_used, accounting.snapshot_slots_used)
        |> assign(:snapshot_slots_limit, accounting.snapshot_slots_limit)
        |> assign(:storage_usage, accounting.storage_usage)
        |> assign(:storage_limit, accounting.storage_limit)
        |> assign(:snapshot_restores, restores)
        |> assign(:snapshot_build_statuses, Versioning.project_snapshot_build_statuses(accounting.snapshots))
        |> assign(:snapshot_build_status_timer, nil)
        |> schedule_build_status_refresh()

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
  # Events and durable build updates
  # ===========================================================================

  @impl true
  def handle_event("create_snapshot", params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      attrs = %{
        mode: "full",
        idempotency_key: params["idempotency_key"],
        title: params["title"],
        description: params["description"]
      }

      case Versioning.request_full_project_snapshot(
             socket.assigns.current_scope,
             socket.assigns.project,
             attrs
           ) do
        {:ok, snapshot} ->
          {:noreply,
           socket
           |> refresh_snapshot_accounting()
           |> push_event("snapshot_request_accepted", %{snapshotId: snapshot.id})
           |> put_flash(:info, dgettext("projects", "Snapshot creation started."))}

        {:error, :limit_reached, details} ->
          {:noreply, push_snapshot_request_error(socket, "storage_limit_reached", details)}

        {:error, :snapshot_limit_reached, details} ->
          {:noreply, push_snapshot_request_error(socket, "snapshot_limit_reached", details)}

        {:error, _reason} ->
          {:noreply, push_snapshot_request_error(socket, "request_failed", %{})}
      end
    end)
  end

  @impl true
  def handle_event("cancel_snapshot", params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      with {:ok, snapshot_id} <- parse_snapshot_id(params["id"]),
           {:ok, snapshot} <-
             Versioning.cancel_project_snapshot(
               socket.assigns.current_scope,
               socket.assigns.project,
               snapshot_id
             ) do
        {:noreply,
         socket
         |> refresh_snapshot_accounting()
         |> push_event("snapshot_cancel_accepted", %{snapshotId: snapshot.id})}
      else
        _invalid ->
          {:noreply,
           push_event(socket, "snapshot_cancel_failed", %{
             snapshotId: event_snapshot_id(params["id"]),
             message: dgettext("projects", "The snapshot could not be cancelled.")
           })}
      end
    end)
  end

  @impl true
  def handle_event("delete_snapshot", params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      with false <- project_restore_active_now?(socket.assigns.project.id),
           {:ok, snapshot_id} <- parse_snapshot_id(params["id"]),
           {:ok, _intent} <-
             Versioning.delete_project_snapshot(
               socket.assigns.current_scope,
               socket.assigns.project,
               snapshot_id
             ) do
        {:noreply,
         socket
         |> refresh_snapshot_accounting()
         |> push_event("snapshot_delete_accepted", %{snapshotId: snapshot_id})
         |> put_flash(:info, dgettext("projects", "Snapshot deletion started."))}
      else
        true ->
          {:noreply,
           push_event(socket, "snapshot_delete_failed", %{
             snapshotId: event_snapshot_id(params["id"]),
             reason: "restore_operation"
           })}

        _invalid ->
          {:noreply,
           push_event(socket, "snapshot_delete_failed", %{
             snapshotId: event_snapshot_id(params["id"]),
             message: dgettext("projects", "The snapshot could not be deleted.")
           })}
      end
    end)
  end

  @impl true
  def handle_event("restore_snapshot", params, socket) do
    with :ok <- Authorize.authorize(socket, :manage_project),
         {:ok, snapshot_id} <- parse_snapshot_id(params["id"]),
         {:ok, restore} <-
           Versioning.request_project_snapshot_restore(
             socket.assigns.current_scope,
             socket.assigns.project,
             snapshot_id,
             %{idempotency_key: params["idempotency_key"]}
           ) do
      {:noreply,
       socket
       |> refresh_snapshot_state()
       |> push_event("snapshot_restore_accepted", %{
         snapshotId: snapshot_id,
         restoreId: restore.id
       })}
    else
      {:error, reason} ->
        {:noreply,
         push_snapshot_restore_error(
           socket,
           event_snapshot_id(params["id"]),
           restore_request_error_reason(reason)
         )}

      :error ->
        {:noreply,
         push_snapshot_restore_error(
           socket,
           event_snapshot_id(params["id"]),
           "invalid_request"
         )}
    end
  end

  @impl true
  def handle_info({:project_snapshot_updated, _snapshot_id}, socket) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  @impl true
  def handle_info({:project_snapshot_restore_updated, _restore_id}, socket) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  @impl true
  def handle_info(:refresh_snapshot_build_statuses, socket) do
    socket =
      socket
      |> assign(:snapshot_build_status_timer, nil)
      |> refresh_snapshot_build_statuses()
      |> schedule_build_status_refresh()

    {:noreply, socket}
  end

  defp refresh_snapshot_state(socket) do
    socket
    |> refresh_snapshot_accounting()
    |> assign(
      :snapshot_restores,
      Versioning.list_project_snapshot_restores(socket.assigns.project.id)
    )
  end

  defp refresh_snapshot_accounting(socket) do
    accounting = snapshot_storage_accounting(socket.assigns.project)

    socket
    |> assign(:snapshots, accounting.snapshots)
    |> assign(:snapshot_reservations, accounting.snapshot_reservations)
    |> assign(:snapshot_slots_used, accounting.snapshot_slots_used)
    |> assign(:snapshot_slots_limit, accounting.snapshot_slots_limit)
    |> assign(:storage_usage, accounting.storage_usage)
    |> assign(:storage_limit, accounting.storage_limit)
    |> assign(:snapshot_build_statuses, Versioning.project_snapshot_build_statuses(accounting.snapshots))
    |> schedule_build_status_refresh()
  end

  defp refresh_snapshot_build_statuses(socket) do
    assign(
      socket,
      :snapshot_build_statuses,
      Versioning.project_snapshot_build_statuses(socket.assigns.snapshots)
    )
  end

  defp schedule_build_status_refresh(socket) do
    active_build? =
      Enum.any?(socket.assigns.snapshots, &(&1.lifecycle_state in ["pending", "building", "verifying"]))

    if connected?(socket) and active_build? and is_nil(socket.assigns.snapshot_build_status_timer) do
      timer = Process.send_after(self(), :refresh_snapshot_build_statuses, @build_status_refresh_ms)
      assign(socket, :snapshot_build_status_timer, timer)
    else
      socket
    end
  end

  defp push_snapshot_request_error(socket, reason, details) do
    push_event(socket, "snapshot_request_failed", %{
      reason: reason,
      requiredBytes: serialize_optional_byte_count(details[:required]),
      availableBytes: serialize_optional_byte_count(details[:available]),
      used: details[:used],
      limit: details[:limit]
    })
  end

  defp push_snapshot_restore_error(socket, snapshot_id, reason) do
    push_event(socket, "snapshot_restore_failed", %{
      snapshotId: snapshot_id,
      reason: reason
    })
  end

  defp restore_request_error_reason(reason)
       when reason in [
              :restore_temporarily_disabled,
              :project_snapshot_not_restorable,
              :project_snapshot_restore_in_progress,
              :project_snapshot_restore_idempotency_conflict,
              :project_snapshot_not_found,
              :unauthorized,
              :invalid_project_snapshot_restore_request
            ], do: Atom.to_string(reason)

  defp restore_request_error_reason(_reason), do: "request_failed"

  defp project_restore_active_now?(project_id) do
    project_id
    |> Versioning.list_project_snapshot_restores()
    |> project_restore_active?()
  end

  defp parse_snapshot_id(snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0, do: {:ok, snapshot_id}

  defp parse_snapshot_id(snapshot_id) when is_binary(snapshot_id) do
    case Integer.parse(snapshot_id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp parse_snapshot_id(_snapshot_id), do: :error

  defp event_snapshot_id(snapshot_id) do
    case parse_snapshot_id(snapshot_id) do
      {:ok, parsed} -> parsed
      :error -> nil
    end
  end
end

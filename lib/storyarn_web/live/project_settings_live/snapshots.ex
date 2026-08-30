defmodule StoryarnWeb.ProjectSettingsLive.Snapshots do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Commercial
  alias Storyarn.Projects
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
    Projects.project_snapshot_restore_enabled?() and
      snapshot.format_version == 2 and snapshot.mode == "full" and
      snapshot.lifecycle_state == "ready" and snapshot.integrity_state == "verified" and
      snapshot.accounting_version == 1 and snapshot.restore_contract_version == 1
  end

  defp serialize_restore_operation(%{
         id: id,
         status: status,
         phase: phase,
         attempt: attempt,
         requested_at: requested_at,
         state_updated_at: state_updated_at,
         completed_at: completed_at,
         failed_at: failed_at,
         failure_code: failure_code,
         failure_message: failure_message
       }) do
    %{
      id: id,
      status: status,
      phase: phase,
      attempt: attempt,
      requestedAt: serialize_datetime(requested_at),
      stateUpdatedAt: serialize_datetime(state_updated_at),
      completedAt: serialize_datetime(completed_at),
      failedAt: serialize_datetime(failed_at),
      failureCode: failure_code,
      failureMessage: failure_message
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
    Projects.ready_project_snapshot_archive_key?(project_id, prefix, archive_key) and
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
    stale_project = socket.assigns.project

    if connected?(socket) do
      # Ownership must be observed before refreshing access. Otherwise a
      # transfer committed between the read and the subscription could leave
      # an old owner mounted indefinitely.
      Projects.subscribe_project_ownership_changes(stale_project.id)
    end

    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, stale_project.id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project),
         :ok <- subscribe_snapshot_updates(socket, project),
         {:ok, accounting} <-
           Projects.project_snapshot_accounting(socket.assigns.current_scope, project.id) do
      restores = Projects.list_project_snapshot_restores(project.id)

      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(:snapshots, accounting.snapshots)
       |> assign(:snapshot_reservations, accounting.snapshot_reservations)
       |> assign(:snapshot_slots_used, accounting.snapshot_slots_used)
       |> assign(:snapshot_slots_limit, accounting.snapshot_slots_limit)
       |> assign(:storage_usage, accounting.storage_usage)
       |> assign(:storage_limit, accounting.storage_limit)
       |> assign(:snapshot_restores, restores)
       |> assign(:snapshot_build_statuses, Projects.project_snapshot_build_statuses(accounting.snapshots))
       |> assign(:snapshot_build_status_timer, nil)
       |> assign(:snapshot_access_active, true)
       |> schedule_build_status_refresh()}
    else
      _lost_access ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> redirect(to: ~p"/workspaces/#{stale_project.workspace.slug}/projects/#{stale_project.slug}")}
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

      case Projects.request_full_project_snapshot(
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
             Projects.cancel_project_snapshot(
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
             Projects.delete_project_snapshot(
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
           Projects.request_project_snapshot_restore(
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
  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  def handle_info({:project_snapshot_updated, _snapshot_id}, %{assigns: %{snapshot_access_active: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:project_snapshot_updated, _snapshot_id}, socket) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  @impl true
  def handle_info(
        {:commercial_snapshot_export_lease_state_invalidated, _snapshot_id},
        %{assigns: %{snapshot_access_active: false}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_info({:commercial_snapshot_export_lease_state_invalidated, _snapshot_id}, socket) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  @impl true
  def handle_info({:project_snapshot_restore_updated, _restore_id}, %{assigns: %{snapshot_access_active: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:project_snapshot_restore_updated, _restore_id}, socket) do
    {:noreply, refresh_snapshot_state(socket)}
  end

  @impl true
  def handle_info(:refresh_snapshot_build_statuses, %{assigns: %{snapshot_access_active: false}} = socket) do
    {:noreply, assign(socket, :snapshot_build_status_timer, nil)}
  end

  def handle_info(:refresh_snapshot_build_statuses, socket) do
    socket =
      socket
      |> assign(:snapshot_build_status_timer, nil)
      |> refresh_snapshot_build_statuses()
      |> schedule_build_status_refresh()

    {:noreply, socket}
  end

  defp refresh_snapshot_state(socket) do
    case authorized_snapshot_accounting(socket) do
      {:ok, authorized_socket, accounting} ->
        authorized_socket
        |> assign_snapshot_accounting(accounting)
        |> assign(
          :snapshot_restores,
          Projects.list_project_snapshot_restores(authorized_socket.assigns.project.id)
        )

      {:error, :access_lost} ->
        revoke_snapshot_access_and_navigate(socket)
    end
  end

  defp refresh_snapshot_accounting(socket) do
    case authorized_snapshot_accounting(socket) do
      {:ok, authorized_socket, accounting} ->
        assign_snapshot_accounting(authorized_socket, accounting)

      {:error, :access_lost} ->
        revoke_snapshot_access_and_navigate(socket)
    end
  end

  defp assign_snapshot_accounting(socket, accounting) do
    socket
    |> assign(:snapshots, accounting.snapshots)
    |> assign(:snapshot_reservations, accounting.snapshot_reservations)
    |> assign(:snapshot_slots_used, accounting.snapshot_slots_used)
    |> assign(:snapshot_slots_limit, accounting.snapshot_slots_limit)
    |> assign(:storage_usage, accounting.storage_usage)
    |> assign(:storage_limit, accounting.storage_limit)
    |> assign(:snapshot_build_statuses, Projects.project_snapshot_build_statuses(accounting.snapshots))
    |> schedule_build_status_refresh()
  end

  defp refresh_snapshot_build_statuses(socket) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, socket.assigns.project.id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project) do
      socket
      |> assign(:project, project)
      |> assign(:membership, membership)
      |> assign(:current_workspace, project.workspace)
      |> assign(
        :snapshot_build_statuses,
        Projects.project_snapshot_build_statuses(socket.assigns.snapshots)
      )
    else
      _lost_access -> revoke_snapshot_access_and_navigate(socket)
    end
  end

  defp authorized_snapshot_accounting(socket) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, socket.assigns.project.id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project),
         {:ok, accounting} <-
           Projects.project_snapshot_accounting(socket.assigns.current_scope, project.id) do
      authorized_socket =
        socket
        |> assign(:project, project)
        |> assign(:membership, membership)
        |> assign(:current_workspace, project.workspace)
        |> assign(:snapshot_access_active, true)

      {:ok, authorized_socket, accounting}
    else
      _lost_access -> {:error, :access_lost}
    end
  end

  defp schedule_build_status_refresh(socket) do
    active_build? =
      Enum.any?(socket.assigns.snapshots, &(&1.lifecycle_state in ["pending", "building", "verifying"]))

    if connected?(socket) and socket.assigns.snapshot_access_active and active_build? and
         is_nil(socket.assigns.snapshot_build_status_timer) do
      timer = Process.send_after(self(), :refresh_snapshot_build_statuses, @build_status_refresh_ms)
      assign(socket, :snapshot_build_status_timer, timer)
    else
      socket
    end
  end

  defp revoke_snapshot_access(socket) do
    case socket.assigns.snapshot_build_status_timer do
      timer when is_reference(timer) -> Process.cancel_timer(timer)
      _no_timer -> false
    end

    socket
    |> assign(:snapshot_access_active, false)
    |> assign(:snapshot_build_status_timer, nil)
  end

  defp revoke_snapshot_access_and_navigate(socket) do
    project = socket.assigns.project

    socket
    |> revoke_snapshot_access()
    |> put_flash(
      :error,
      dgettext("projects", "You don't have permission to manage this project.")
    )
    |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
  end

  defp subscribe_snapshot_updates(socket, project) do
    if connected?(socket) do
      # Subscribe before the initial reads so committed snapshot, restore and
      # lease changes cannot leave the first rendered state stale.
      with :ok <- Commercial.subscribe_project_snapshot_export_leases(project.id),
           :ok <- Projects.subscribe_project_snapshots(project.id) do
        Projects.subscribe_project_snapshot_restores(project.id)
      end
    else
      :ok
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
    |> Projects.list_project_snapshot_restores()
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

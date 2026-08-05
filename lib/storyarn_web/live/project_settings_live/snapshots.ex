defmodule StoryarnWeb.ProjectSettingsLive.Snapshots do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects
  alias Storyarn.Versioning
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
      <:title>{dgettext("projects", "Snapshots")}</:title>
      <:subtitle>
        {dgettext("projects", "Review snapshot storage, reservations, and integrity")}
      </:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsSnapshots"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-snapshots"
        snapshots={serialize_snapshots(@snapshots, @snapshot_reservations)}
        storage-usage={serialize_storage_usage(@storage_usage, @storage_limit)}
        snapshot-limit={serialize_snapshot_limit(@snapshot_slots_used, @snapshot_slots_limit)}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_snapshots(snapshots, reservations) do
    Enum.map(snapshots, &serialize_snapshot(&1, reservations))
  end

  defp serialize_snapshot(snapshot, reservations) do
    reservation = Map.get(reservations, snapshot.id, %{active_bytes: 0, export_bytes: 0, active_count: 0})

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
      projectDataSizeBytes: snapshot |> measured_project_data_bytes() |> serialize_optional_byte_count(),
      metadataSizeBytes: snapshot |> measured_metadata_bytes() |> serialize_optional_byte_count(),
      assetBlobSizeBytes: serialize_optional_byte_count(snapshot.asset_blob_size_bytes),
      assetCount: snapshot.asset_count,
      blobCount: snapshot.blob_count,
      activeReservationBytes: reservation |> non_export_reservation_bytes() |> serialize_byte_count(),
      exportReservationBytes: serialize_byte_count(reservation.export_bytes),
      accountingVersion: snapshot.accounting_version,
      accountingMeasuredAt: serialize_datetime(snapshot.accounting_measured_at),
      plannedSizeBytes: serialize_optional_byte_count(snapshot.total_size_bytes),
      progressPhase: snapshot.progress_phase,
      progressBytes: serialize_byte_count(snapshot.progress_bytes || 0),
      progressTotalBytes: serialize_optional_byte_count(snapshot.progress_total_bytes),
      failureCode: snapshot.failure_code,
      failureMessage: snapshot.failure_message,
      capturedAt: serialize_datetime(snapshot.captured_at),
      cancelRequestedAt: serialize_datetime(snapshot.cancel_requested_at),
      canCancel: snapshot_cancellable?(snapshot),
      canDelete: snapshot_deletable?(snapshot, reservation),
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

  defp snapshot_deletable?(snapshot, reservation) do
    snapshot.lifecycle_state in ["ready", "failed", "cancelled"] and reservation.active_count == 0
  end

  defp snapshot_creator_email(%{created_by: %{email: email}}), do: email
  defp snapshot_creator_email(_snapshot), do: nil

  defp measured_project_data_bytes(%{format_version: 1, project_size_bytes: bytes}), do: bytes

  defp measured_project_data_bytes(_snapshot), do: nil

  defp measured_metadata_bytes(%{format_version: 1, manifest_size_bytes: bytes}), do: bytes

  defp measured_metadata_bytes(_snapshot), do: nil

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

      if connected?(socket), do: Versioning.subscribe_project_snapshots(project.id)

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:snapshots, accounting.snapshots)
        |> assign(:snapshot_reservations, accounting.snapshot_reservations)
        |> assign(:snapshot_slots_used, accounting.snapshot_slots_used)
        |> assign(:snapshot_slots_limit, accounting.snapshot_slots_limit)
        |> assign(:storage_usage, accounting.storage_usage)
        |> assign(:storage_limit, accounting.storage_limit)

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
      with snapshot_id when not is_nil(snapshot_id) <- params["id"],
           {snapshot_id, ""} <- Integer.parse(to_string(snapshot_id)),
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
             snapshotId: params["id"],
             message: dgettext("projects", "The snapshot could not be cancelled.")
           })}
      end
    end)
  end

  @impl true
  def handle_event("delete_snapshot", params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      with snapshot_id when not is_nil(snapshot_id) <- params["id"],
           {snapshot_id, ""} <- Integer.parse(to_string(snapshot_id)),
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
        _invalid ->
          {:noreply,
           push_event(socket, "snapshot_delete_failed", %{
             snapshotId: params["id"],
             message: dgettext("projects", "The snapshot could not be deleted.")
           })}
      end
    end)
  end

  @impl true
  def handle_info({:project_snapshot_updated, _snapshot_id}, socket) do
    {:noreply, refresh_snapshot_accounting(socket)}
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
end

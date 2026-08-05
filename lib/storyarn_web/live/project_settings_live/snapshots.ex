defmodule StoryarnWeb.ProjectSettingsLive.Snapshots do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents

  alias Storyarn.Projects

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
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  defp serialize_snapshots(snapshots, reservations) do
    Enum.map(snapshots, fn s ->
      reservation = Map.get(reservations, s.id, %{active_bytes: 0, export_bytes: 0})

      %{
        id: s.id,
        title: s.title,
        description: s.description,
        versionNumber: s.version_number,
        insertedAt: s.inserted_at && DateTime.to_iso8601(s.inserted_at),
        mode: s.mode,
        lifecycleStatus: s.lifecycle_state,
        integrityStatus: s.integrity_state,
        accountedSizeBytes: serialize_optional_byte_count(s.accounted_size_bytes),
        projectDataSizeBytes: s |> measured_project_data_bytes() |> serialize_optional_byte_count(),
        metadataSizeBytes: s |> measured_metadata_bytes() |> serialize_optional_byte_count(),
        assetBlobSizeBytes: serialize_optional_byte_count(s.asset_blob_size_bytes),
        assetCount: s.asset_count,
        blobCount: s.blob_count,
        activeReservationBytes: reservation |> non_export_reservation_bytes() |> serialize_byte_count(),
        exportReservationBytes: serialize_byte_count(reservation.export_bytes),
        accountingVersion: s.accounting_version,
        accountingMeasuredAt: s.accounting_measured_at && DateTime.to_iso8601(s.accounting_measured_at),
        entityCounts: s.entity_counts,
        createdByEmail: s.created_by && s.created_by.email
      }
    end)
  end

  defp measured_project_data_bytes(%{accounting_version: 1, project_size_bytes: bytes}), do: bytes

  defp measured_project_data_bytes(_snapshot), do: nil

  defp measured_metadata_bytes(%{accounting_version: 1, manifest_size_bytes: bytes}), do: bytes

  defp measured_metadata_bytes(_snapshot), do: nil

  defp non_export_reservation_bytes(%{active_bytes: active_bytes, export_bytes: export_bytes}) do
    max(active_bytes - export_bytes, 0)
  end

  defp serialize_optional_byte_count(value) when is_integer(value) and value >= 0, do: serialize_byte_count(value)

  defp serialize_optional_byte_count(_value), do: nil

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns

    if Projects.can?(membership.role, :manage_project) do
      accounting = snapshot_storage_accounting(project)

      socket =
        socket
        |> assign(:current_workspace, project.workspace)
        |> assign(:snapshots, accounting.snapshots)
        |> assign(:snapshot_reservations, accounting.snapshot_reservations)
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
end

defmodule StoryarnWeb.FlowLive.VersionViewer do
  @moduledoc """
  Read-only Flow version surface embedded by the comparison view.

  Flow identity, version storage and snapshot serialization are all resolved
  through the public Flows facade so this surface can move with the context.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Flows
  alias Storyarn.Platform.Collaboration
  alias StoryarnWeb.PrivateMedia

  require Logger

  @not_found_error_reasons [
    :invalid_entity_id,
    :invalid_version_number,
    :entity_version_not_found,
    :not_found
  ]

  @impl true
  def render(%{view_error: _} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/viewer/VersionViewerError"
        v-socket={@socket}
        v-inject="compare-layout"
        id="flow-version-viewer-error"
        class="w-full h-full"
        reason={@view_error}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/flow/show/FlowCanvas"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"flow-version-viewer-#{@flow.id}-#{@version_number}"}
        class="w-full h-full"
        flow-data={Jason.encode!(@flow_data)}
        variable-map={Jason.encode!(@variable_map)}
        loading={false}
        readonly={true}
        user-id={@current_scope.user.id}
        user-color={Collaboration.user_color(@current_scope.user.id)}
        canvas-id={"flow-version-canvas-#{@flow.id}-#{@version_number}"}
        toolbar-data={Jason.encode!(@toolbar_data)}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  @impl true
  def mount(%{"id" => flow_id_str, "version_number" => version_number_str}, _session, socket) do
    case load_version_view(socket, flow_id_str, version_number_str) do
      {:ok, loaded_socket} ->
        {:ok, loaded_socket, layout: false}

      {:error, reason} ->
        {:ok, assign_view_error(socket, flow_id_str, version_number_str, reason), layout: false}
    end
  end

  defp load_version_view(socket, flow_id_str, version_number_str) do
    project = socket.assigns.project

    with {:ok, flow_id} <- parse_id(flow_id_str, :invalid_entity_id),
         {:ok, version_number} <- parse_id(version_number_str, :invalid_version_number),
         flow when not is_nil(flow) <- Flows.get_flow_brief(project.id, flow_id),
         version when not is_nil(version) <- Flows.get_version(flow_id, version_number),
         {:ok, snapshot} <- Flows.load_version_snapshot(version) do
      referenced_sheets = snapshot["referenced_sheets"] || %{}

      {:ok,
       socket
       |> assign(:flow, flow)
       |> assign(:version_number, version_number)
       |> assign(:page_title, version_label(version))
       |> assign(:flow_data, Flows.serialize_version_snapshot(snapshot))
       |> assign(:variable_map, flow_variable_map(referenced_sheets, project.id))
       |> assign(:toolbar_data, flow_toolbar_data(referenced_sheets))}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp assign_view_error(socket, flow_id_str, version_number_str, reason) do
    kind = view_error_kind(reason)
    log_view_error(kind, flow_id_str, version_number_str, reason)

    socket
    |> assign(:view_error, to_string(kind))
    |> assign(:page_title, view_error_title(kind))
  end

  defp view_error_kind({:invalid_expected_checksum, _}), do: :integrity
  defp view_error_kind({:checksum_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:compressed_size_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:invalid_expected_compressed_size, _}), do: :integrity
  defp view_error_kind(:entity_version_storage_key_mismatch), do: :integrity

  defp view_error_kind(reason) when reason in @not_found_error_reasons, do: :not_found

  defp view_error_kind(_reason), do: :unreadable

  defp log_view_error(:not_found, flow_id_str, version_number_str, reason) do
    Logger.info("Version viewer: no flow #{flow_id_str} v#{version_number_str} to show (#{inspect(reason)})")
  end

  defp log_view_error(kind, flow_id_str, version_number_str, reason) do
    Logger.warning("Version viewer: flow #{flow_id_str} v#{version_number_str} is #{kind} (#{inspect(reason)})")
  end

  defp view_error_title(:not_found), do: dgettext("versioning", "Version not found")
  defp view_error_title(_kind), do: dgettext("versioning", "Version unavailable")

  defp parse_id(value, error_reason) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, error_reason}
    end
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end

  defp flow_variable_map(referenced_sheets, project_id) do
    Map.new(referenced_sheets, fn {id, sheet} ->
      {to_string(id),
       %{
         id: sheet["id"],
         name: sheet["name"],
         avatar_url: PrivateMedia.project_url_from_stored(project_id, sheet["avatar_url"]),
         banner_url: PrivateMedia.project_url_from_stored(project_id, sheet["banner_url"]),
         color: sheet["color"],
         avatars: [],
         gallery_images: []
       }}
    end)
  end

  defp flow_toolbar_data(referenced_sheets) do
    %{
      hubs: [],
      projectFlows: [],
      sheetAvatars:
        Enum.map(referenced_sheets, fn {_id, sheet} ->
          %{id: sheet["id"], name: sheet["name"], color: sheet["color"], avatars: []}
        end),
      subflowExits: [],
      referencingJumps: [],
      referencingFlows: []
    }
  end
end

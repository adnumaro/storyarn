defmodule StoryarnWeb.SheetLive.VersionViewer do
  @moduledoc """
  Read-only Sheet version surface embedded by the comparison view.

  Sheet identity and version storage are resolved through the public Sheets
  facade. The Vue-facing snapshot mapping remains in StoryarnWeb.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Sheets
  alias StoryarnWeb.PrivateMedia

  require Logger

  @not_found_error_reasons [
    :invalid_entity_id,
    :invalid_version_number,
    :entity_version_not_found,
    :not_found
  ]

  @impl true
  def render(%{view_error: _error} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/viewer/VersionViewerError"
        v-socket={@socket}
        v-inject="compare-layout"
        id="version-viewer-error"
        class="w-full h-full"
        reason={@view_error}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare
      socket={@socket}
      flash={@flash}
      content_class="h-full overflow-y-auto bg-background p-4"
    >
      <.vue
        v-component="live/sheet/show/SheetSurface"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"sheet-version-surface-#{@entity_id}-#{@version_number}"}
        class="contents"
        sheet={@sheet}
        can-edit={false}
        source-shortcut={nil}
        surface={@surface}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  @impl true
  def mount(%{"id" => sheet_id_string, "version_number" => version_number_string}, _session, socket) do
    case load_version_view(socket, sheet_id_string, version_number_string) do
      {:ok, loaded_socket} ->
        {:ok, loaded_socket, layout: false}

      {:error, reason} ->
        {:ok, assign_view_error(socket, sheet_id_string, version_number_string, reason), layout: false}
    end
  end

  defp load_version_view(socket, sheet_id_string, version_number_string) do
    project = socket.assigns.project

    with {:ok, entity_id} <- parse_id(sheet_id_string, :invalid_entity_id),
         {:ok, version_number} <- parse_id(version_number_string, :invalid_version_number),
         sheet when not is_nil(sheet) <- Sheets.get_sheet(project.id, entity_id),
         version when not is_nil(version) <- Sheets.get_version(entity_id, version_number),
         {:ok, snapshot} <- Sheets.load_version_snapshot(version) do
      blocks = Sheets.serialize_version_snapshot(snapshot)

      {:ok,
       socket
       |> assign(:entity_id, entity_id)
       |> assign(:version_number, version_number)
       |> assign(:page_title, version_label(version))
       |> assign(:sheet, sheet_header(snapshot, project.id))
       |> assign(:surface, sheet_surface(socket.assigns, project, blocks))}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp assign_view_error(socket, sheet_id_string, version_number_string, reason) do
    kind = view_error_kind(reason)
    log_view_error(kind, sheet_id_string, version_number_string, reason)

    socket
    |> assign(:view_error, to_string(kind))
    |> assign(:page_title, view_error_title(kind))
  end

  defp view_error_kind({:invalid_expected_checksum, _value}), do: :integrity
  defp view_error_kind({:checksum_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:compressed_size_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:invalid_expected_compressed_size, _value}), do: :integrity
  defp view_error_kind(:entity_version_storage_key_mismatch), do: :integrity
  defp view_error_kind(reason) when reason in @not_found_error_reasons, do: :not_found
  defp view_error_kind(_reason), do: :unreadable

  defp log_view_error(:not_found, sheet_id_string, version_number_string, reason) do
    Logger.info("Version viewer: no sheet #{sheet_id_string} v#{version_number_string} to show (#{inspect(reason)})")
  end

  defp log_view_error(kind, sheet_id_string, version_number_string, reason) do
    Logger.warning("Version viewer: sheet #{sheet_id_string} v#{version_number_string} is #{kind} (#{inspect(reason)})")
  end

  defp view_error_title(:not_found), do: dgettext("versioning", "Version not found")
  defp view_error_title(_kind), do: dgettext("versioning", "Version unavailable")

  defp parse_id(value, error_reason) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _invalid -> {:error, error_reason}
    end
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end

  defp sheet_header(snapshot, project_id) do
    %{
      id: snapshot["original_id"] || -1,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      color: snapshot["color"],
      bannerUrl: snapshot_asset_url(snapshot["banner_asset_id"], snapshot, project_id),
      avatars: sheet_avatars(snapshot, project_id)
    }
  end

  defp sheet_avatars(snapshot, project_id) do
    case snapshot_asset_url(snapshot["avatar_asset_id"], snapshot, project_id) do
      nil -> []
      url -> [%{id: "snapshot-default-avatar", url: url, name: nil, is_default: true}]
    end
  end

  defp sheet_surface(assigns, project, blocks) do
    %{
      tabs: %{currentTab: "content", canEdit: false, compact: true},
      content: %{
        blocks: Enum.map(blocks, &sheet_layout_item/1),
        inheritedGroups: [],
        workspaceSlug: project.workspace.slug,
        projectSlug: project.slug,
        canEdit: false,
        formulaEditing: nil,
        blockLocks: %{},
        currentUserId: assigns.current_scope.user.id
      }
    }
  end

  defp sheet_layout_item(block), do: %{type: "full_width", block: sheet_block(block)}

  defp sheet_block(block) do
    %{
      id: block.id,
      type: block.type,
      position: block.position,
      is_constant: block.is_constant,
      variable_name: block.variable_name,
      scope: block.scope,
      inherited: false,
      detached: false,
      required: block.required,
      column_group_id: nil,
      column_index: 0,
      config: block.config,
      value: block.value,
      columns: block.table_columns,
      rows: block.table_rows,
      collapsed: get_in(block.config, ["collapsed"]) || false,
      gallery_images: [],
      reference_target: nil,
      can_reattach: false
    }
  end

  defp snapshot_asset_url(nil, _snapshot, _project_id), do: nil

  defp snapshot_asset_url(asset_id, snapshot, project_id) do
    metadata =
      snapshot
      |> Map.get("asset_metadata", %{})
      |> Map.get(to_string(asset_id), %{})

    PrivateMedia.project_snapshot_asset_url(project_id, metadata)
  end
end

defmodule StoryarnWeb.SheetLive.VersionHistory do
  @moduledoc """
  Sheet-owned version history loading and serialization for the Sheet editor.

  This module deliberately exposes no generic entity or versioning-context
  switch: the Sheet Web boundary consumes only `Storyarn.Sheets`.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Sheets

  @max_restore_request_id_bytes 64
  @versions_per_page 20

  defguardp valid_restore_request_id?(request_id)
            when is_binary(request_id) and byte_size(request_id) > 0 and
                   byte_size(request_id) <= @max_restore_request_id_bytes

  @doc """
  Extracts and validates a restore request ID.

  Clients predating restore request correlation may omit the ID. A present ID
  must be a non-empty, bounded string so malformed requests cannot be treated
  as legacy traffic or echoed back to the client.
  """
  def restore_request_id(params) when is_map(params) do
    case Map.fetch(params, "request_id") do
      :error -> {:ok, nil}
      {:ok, request_id} when valid_restore_request_id?(request_id) -> {:ok, request_id}
      {:ok, _invalid_request_id} -> :error
    end
  end

  @doc "Adds a validated restore request ID to an outbound payload when one was supplied."
  def put_restore_request_id(payload, nil) when is_map(payload), do: payload

  def put_restore_request_id(payload, request_id) when is_map(payload) and valid_restore_request_id?(request_id) do
    Map.put(payload, :request_id, request_id)
  end

  @doc "Loads version history for the current Sheet and assigns it to `:history_data`."
  def load_history_data(socket) do
    sheet = socket.assigns.sheet
    project_id = socket.assigns.project.id
    workspace_id = socket.assigns.workspace.id

    versions =
      Sheets.list_versions(sheet.id,
        limit: @versions_per_page + 1,
        offset: 0
      )

    has_more = length(versions) > @versions_per_page
    versions = Enum.take(versions, @versions_per_page)
    {named, auto} = Enum.split_with(versions, &(not &1.is_auto))

    can_name =
      Sheets.can_create_named_version?(project_id, workspace_id) == :ok

    assign(socket, :history_data, %{
      versions: serialize_versions(versions),
      named_versions: serialize_versions(named),
      auto_versions: serialize_versions(auto),
      has_more: has_more,
      page: 1,
      can_name_version: can_name,
      current_version_id: sheet.current_version_id,
      raw_versions: versions
    })
  end

  @doc "Loads the next page of versions and appends to existing history data."
  def load_more_history(socket, page) do
    sheet = socket.assigns.sheet
    offset = (page - 1) * @versions_per_page

    new_versions =
      Sheets.list_versions(sheet.id,
        limit: @versions_per_page + 1,
        offset: offset
      )

    has_more = length(new_versions) > @versions_per_page
    new_versions = Enum.take(new_versions, @versions_per_page)

    history = socket.assigns.history_data
    all_raw = history.raw_versions ++ new_versions
    {named, auto} = Enum.split_with(all_raw, &(not &1.is_auto))

    assign(socket, :history_data, %{
      history
      | versions: serialize_versions(all_raw),
        named_versions: serialize_versions(named),
        auto_versions: serialize_versions(auto),
        has_more: has_more,
        page: page,
        raw_versions: all_raw
    })
  end

  @doc "Serializes a list of version structs to camelCase maps for Vue."
  def serialize_versions(versions) do
    Enum.map(versions, fn v ->
      %{
        id: v.id,
        versionNumber: v.version_number,
        title: v.title,
        description: v.description,
        changeSummary: v.change_summary,
        changeDetails: v.change_details,
        isAuto: v.is_auto,
        entityType: v.entity_type,
        insertedAt: Calendar.strftime(v.inserted_at, "%b %d, %Y at %H:%M"),
        createdBy: if(v.created_by, do: v.created_by.display_name || v.created_by.email)
      }
    end)
  end

  @doc "Detects unsaved changes and shows appropriate restore modal."
  def detect_and_show_restore_preview(socket, sheet, version, request_id) do
    case Sheets.prepare_version_restore(sheet, version) do
      {:ok, :unsaved_changes} ->
        payload = put_restore_request_id(%{versionNumber: version.version_number}, request_id)
        {:noreply, push_event(socket, "show_unsaved_modal", payload)}

      {:ok, {:ready, report}} ->
        show_conflict_preview(socket, version, report, request_id)

      {:error, :target_snapshot_unreadable} ->
        snapshot_load_error(socket)
    end
  end

  @doc "Shows the conflict preview modal for a version restore."
  def show_conflict_preview(socket, version, report, request_id) do
    serialized_report = %{
      hasConflicts: report.has_conflicts,
      shortcutCollision: report.shortcut_collision,
      resolvedShortcut: report.resolved_shortcut,
      conflicts:
        Enum.map(report.conflicts, fn conflict ->
          %{type: to_string(conflict.type), id: conflict.id, contexts: conflict.contexts}
        end)
    }

    payload =
      put_restore_request_id(
        %{versionNumber: version.version_number, report: serialized_report},
        request_id
      )

    {:noreply, push_event(socket, "show_restore_modal", payload)}
  end

  def snapshot_load_error(socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       dgettext("versioning", "Could not load version snapshot.")
     )}
  end

  @doc "Parses a version number from string or integer."
  def parse_version_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  def parse_version_number(value) when is_integer(value), do: {:ok, value}
  def parse_version_number(_), do: :error
end

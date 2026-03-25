defmodule StoryarnWeb.Helpers.VersionHistoryHelpers do
  @moduledoc """
  Shared helpers for version history data loading and serialization.
  Used by sheet, scene, and flow LiveViews to pass version data to Vue components.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Billing
  alias Storyarn.Versioning

  @versions_per_page 20

  @doc """
  Loads version history for an entity and assigns it to `:history_data`.

  ## Options
    * `entity_type` - "sheet", "scene", or "flow"
    * `entity` - the entity struct (must have `:id` and `:current_version_id`)
    * `project_id` - the project ID
    * `workspace_id` - the workspace ID
  """
  def load_history_data(socket, entity_type, entity, project_id, workspace_id) do
    versions =
      Versioning.list_versions(entity_type, entity.id,
        limit: @versions_per_page + 1,
        offset: 0
      )

    has_more = length(versions) > @versions_per_page
    versions = Enum.take(versions, @versions_per_page)
    {named, auto} = Enum.split_with(versions, &(not &1.is_auto))

    can_name =
      Billing.can_create_named_version?(project_id, workspace_id) == :ok

    assign(socket, :history_data, %{
      versions: serialize_versions(versions),
      named_versions: serialize_versions(named),
      auto_versions: serialize_versions(auto),
      has_more: has_more,
      page: 1,
      can_name_version: can_name,
      current_version_id: entity.current_version_id,
      raw_versions: versions
    })
  end

  @doc "Loads the next page of versions and appends to existing history data."
  def load_more_history(socket, entity_type, entity_id, page) do
    offset = (page - 1) * @versions_per_page

    new_versions =
      Versioning.list_versions(entity_type, entity_id,
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
        createdBy:
          if(v.created_by, do: v.created_by.display_name || v.created_by.email)
      }
    end)
  end

  @doc "Detects unsaved changes and shows appropriate restore modal."
  def detect_and_show_restore_preview(socket, entity_type, entity, version) do
    builder = Versioning.get_builder!(entity_type)

    has_unsaved =
      case Versioning.get_latest_version(entity_type, entity.id) do
        nil ->
          true

        latest ->
          case Versioning.load_version_snapshot(latest) do
            {:ok, latest_snapshot} ->
              current_snapshot = builder.build_snapshot(entity)
              Versioning.snapshot_has_changes?(entity_type, latest_snapshot, current_snapshot)

            {:error, _} ->
              true
          end
      end

    if has_unsaved do
      {:noreply,
       push_event(socket, "show_unsaved_modal", %{
         versionNumber: version.version_number
       })}
    else
      show_conflict_preview(socket, entity_type, entity, version, true)
    end
  end

  @doc "Shows the conflict preview modal for a version restore."
  def show_conflict_preview(socket, entity_type, entity, version, skip_pre_snapshot) do
    case Versioning.load_version_snapshot(version) do
      {:ok, snapshot} ->
        report = Versioning.detect_restore_conflicts(entity_type, snapshot, entity)

        serialized_report = %{
          hasConflicts: report.has_conflicts,
          shortcutCollision: report.shortcut_collision,
          resolvedShortcut: report.resolved_shortcut,
          conflicts:
            Enum.map(report.conflicts, fn c ->
              %{type: to_string(c.type), id: c.id, contexts: c.contexts}
            end),
          autoResolved: report.auto_resolved
        }

        {:noreply,
         push_event(socket, "show_restore_modal", %{
           versionNumber: version.version_number,
           report: serialized_report,
           skipPreSnapshot: skip_pre_snapshot
         })}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("versioning", "Could not load version snapshot.")
         )}
    end
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

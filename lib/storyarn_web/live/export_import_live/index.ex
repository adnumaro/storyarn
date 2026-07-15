defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Exports
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Imports
  alias Storyarn.Imports.ProjectImportAttempt
  alias StoryarnWeb.Helpers.Authorize

  @all_sections ~w(sheets flows scenes screenplays localization)a
  @hidden_export_formats MapSet.new([:storyarn])
  @archive_export_formats ~w(ink yarn godot unreal articy)a

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
      onboarding={@onboarding}
      onboarding_guide={:export}
      onboarding_autostart
    >
      <:title>{dgettext("projects", "Import & Export")}</:title>
      <:subtitle>
        {dgettext("projects", "Move narrative content into or out of this project.")}
      </:subtitle>

      <.vue
        v-component="live/project/settings/export-import/ProjectSettingsExportImport"
        v-socket={@socket}
        v-inject="settings-layout"
        id="export-import-vue"
        can-edit={@can_edit}
        import-state={serialize_import_state(@import_state)}
        upload-config={if(@can_edit, do: @uploads.import_file, else: nil)}
        export-config={
          %{
            formatConfig: %{
              formats: serialize_formats(@formats),
              selected: to_string(@selected_format),
              extension: @selected_extension
            },
            sectionConfig: %{
              supported: Enum.map(@supported_sections, &to_string/1),
              selected: Enum.map(@sections, &to_string/1),
              entityCounts: serialize_entity_counts(@entity_counts)
            },
            options: %{
              assetMode: to_string(@asset_mode),
              localizationPolicy: to_string(@localization_policy),
              validateBeforeExport: @validate_before_export,
              prettyPrint: @pretty_print
            },
            validation: serialize_validation_result(@validation_result),
            downloadUrl: export_download_url(assigns)
          }
        }
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Vue serialization helpers
  # ===========================================================================

  defp serialize_formats(formats) do
    Enum.map(formats, fn fmt ->
      %{
        format: to_string(fmt.format),
        label: fmt.label,
        extension: fmt.extension,
        sections: Enum.map(fmt.sections, &to_string/1),
        localizationMode: to_string(fmt.localization_mode)
      }
    end)
  end

  defp serialize_entity_counts(counts) when is_map(counts) do
    Map.new(counts, fn {k, v} -> {to_string(k), v} end)
  end

  defp serialize_entity_counts(_), do: %{}

  defp serialize_validation_result(nil), do: nil

  defp serialize_validation_result(result) do
    %{
      status: to_string(result.status),
      errors: Enum.map(result.errors, &serialize_finding/1),
      warnings: Enum.map(result.warnings, &serialize_finding/1),
      info: Enum.map(result.info, &serialize_finding/1)
    }
  end

  defp serialize_finding(finding) do
    %{message: finding.message}
  end

  defp serialize_import_state(state) do
    %{
      step: state.step,
      attemptId: state.attempt_id,
      preview: state.preview,
      error: state.error,
      conflictStrategy: state.conflict_strategy,
      warningCodes: state.warning_codes,
      status: state.status
    }
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    formats = visible_export_formats()
    default_format = List.first(formats)
    default_sections = default_format.sections

    socket =
      socket
      |> assign(:current_path, "")
      # Export state
      |> assign(:formats, formats)
      |> assign(:selected_format, default_format.format)
      |> assign(:selected_extension, download_extension(default_format))
      |> assign(:supported_sections, default_sections)
      |> assign(:sections, MapSet.new(@all_sections))
      |> assign(:entity_counts, %{})
      |> assign_async(:entity_counts_async, fn ->
        opts = %ExportOptions{format: default_format.format}
        {:ok, %{entity_counts_async: Exports.count_entities(project.id, opts)}}
      end)
      |> assign(:asset_mode, :references)
      |> assign(:localization_policy, :release)
      |> assign(:validate_before_export, true)
      |> assign(:pretty_print, true)
      |> assign(:validation_result, nil)
      # Import state. Files are consumed from LiveView's bounded temporary
      # upload and are never written under their client-provided filename.
      |> assign(:import_state, empty_import_state())
      |> allow_upload(:import_file,
        accept: [".yarn", ".zip"],
        max_entries: 1,
        max_file_size: 50_000_000
      )

    if connected?(socket), do: Imports.subscribe_project_imports(project)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, url, socket) do
    {:noreply, assign(socket, :current_path, URI.parse(url).path)}
  end

  @impl true
  def handle_async(:entity_counts_async, {:ok, %{entity_counts_async: counts}}, socket) do
    {:noreply, assign(socket, :entity_counts, counts)}
  end

  def handle_async(:entity_counts_async, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  # ===========================================================================
  # Events — Export
  # ===========================================================================

  @valid_asset_modes ~w(references embedded bundled)a
  @valid_localization_policies ~w(release preview)a

  @impl true
  def handle_event("set_format", %{"format" => format_str}, socket) do
    case Enum.find(socket.assigns.formats, &(to_string(&1.format) == format_str)) do
      nil ->
        {:noreply, socket}

      fmt_meta ->
        socket =
          socket
          |> assign(:selected_format, fmt_meta.format)
          |> assign(:selected_extension, download_extension(fmt_meta))
          |> assign(:supported_sections, fmt_meta.sections)
          |> assign(:validation_result, nil)

        {:noreply, socket}
    end
  end

  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    case Enum.find(@all_sections, &(to_string(&1) == section_str)) do
      nil ->
        {:noreply, socket}

      section ->
        sections = socket.assigns.sections

        sections =
          if MapSet.member?(sections, section),
            do: MapSet.delete(sections, section),
            else: MapSet.put(sections, section)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:validation_result, nil)}
    end
  end

  def handle_event("set_asset_mode", %{"mode" => mode_str}, socket) do
    case Enum.find(@valid_asset_modes, &(to_string(&1) == mode_str)) do
      nil ->
        {:noreply, socket}

      mode ->
        {:noreply,
         socket
         |> assign(:asset_mode, mode)
         |> assign(:validation_result, nil)}
    end
  end

  def handle_event("set_localization_policy", %{"policy" => policy_str}, socket) do
    case Enum.find(@valid_localization_policies, &(to_string(&1) == policy_str)) do
      nil ->
        {:noreply, socket}

      policy ->
        {:noreply,
         socket
         |> assign(:localization_policy, policy)
         |> assign(:validation_result, nil)}
    end
  end

  def handle_event("toggle_option", %{"option" => "validate_before_export"}, socket) do
    {:noreply,
     socket
     |> assign(:validate_before_export, !socket.assigns.validate_before_export)
     |> assign(:validation_result, nil)}
  end

  def handle_event("toggle_option", %{"option" => "pretty_print"}, socket) do
    {:noreply,
     socket
     |> assign(:pretty_print, !socket.assigns.pretty_print)
     |> assign(:validation_result, nil)}
  end

  def handle_event("validate_export", _params, socket) do
    opts = build_export_options(socket.assigns)
    result = Exports.validate_project(socket.assigns.project.id, opts)
    {:noreply, assign(socket, :validation_result, result)}
  end

  # ===========================================================================
  # Events — Import
  # ===========================================================================

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("parse_import", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      results = consume_import_upload(socket)
      {:noreply, apply_prepare_result(socket, List.first(results))}
    end)
  end

  def handle_event("set_strategy", %{"strategy" => strategy}, socket) when strategy in ~w(skip overwrite rename) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      {:noreply, update_import_state(socket, &Map.put(&1, :conflict_strategy, strategy))}
    end)
  end

  def handle_event("set_strategy", _params, socket), do: {:noreply, socket}

  def handle_event("execute_import", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      execute_ready_import(socket, socket.assigns.import_state)
    end)
  end

  def handle_event("reset_import", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      maybe_cancel_ready_import(socket)
      {:noreply, assign(socket, :import_state, empty_import_state())}
    end)
  end

  @impl true
  def handle_info({:project_import_updated, %ProjectImportAttempt{} = attempt}, socket) do
    if socket.assigns.import_state.attempt_id == attempt.id do
      {:noreply, assign_import_attempt(socket, attempt)}
    else
      {:noreply, socket}
    end
  end

  # ===========================================================================
  # Helpers — Export
  # ===========================================================================

  defp visible_export_formats do
    Enum.reject(Exports.list_formats_with_metadata(), &MapSet.member?(@hidden_export_formats, &1.format))
  end

  defp download_extension(%{format: format}) when format in @archive_export_formats, do: "zip"
  defp download_extension(%{extension: extension}), do: extension

  defp build_export_options(assigns) do
    sections = assigns.sections

    %ExportOptions{
      format: assigns.selected_format,
      validate_before_export: assigns.validate_before_export,
      pretty_print: assigns.pretty_print,
      include_sheets: MapSet.member?(sections, :sheets),
      include_flows: MapSet.member?(sections, :flows),
      include_scenes: MapSet.member?(sections, :scenes),
      include_screenplays: MapSet.member?(sections, :screenplays),
      include_localization: MapSet.member?(sections, :localization),
      localization_policy: assigns.localization_policy,
      include_assets: assigns.asset_mode
    }
  end

  defp export_download_url(assigns) do
    base =
      ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/export/#{assigns.selected_format}"

    params = export_query_params(assigns)

    if params == "" do
      base
    else
      "#{base}?#{params}"
    end
  end

  defp export_query_params(assigns) do
    sections = assigns.sections

    params =
      []
      |> maybe_add("validate", "false", !assigns.validate_before_export)
      |> maybe_add("pretty", "false", !assigns.pretty_print)
      |> maybe_add("sheets", "false", not MapSet.member?(sections, :sheets))
      |> maybe_add("flows", "false", not MapSet.member?(sections, :flows))
      |> maybe_add("scenes", "false", not MapSet.member?(sections, :scenes))
      |> maybe_add("screenplays", "false", not MapSet.member?(sections, :screenplays))
      |> maybe_add("localization", "false", not MapSet.member?(sections, :localization))
      |> maybe_add("localization_policy", "preview", assigns.localization_policy == :preview)
      |> maybe_add("assets", to_string(assigns.asset_mode), assigns.asset_mode != :references)

    URI.encode_query(params)
  end

  defp maybe_add(params, key, value, true), do: [{key, value} | params]
  defp maybe_add(params, _key, _value, false), do: params

  # ===========================================================================
  # Helpers — Import
  # ===========================================================================

  defp empty_import_state do
    %{
      step: "upload",
      attempt_id: nil,
      preview: nil,
      error: nil,
      conflict_strategy: "rename",
      warning_codes: [],
      status: nil
    }
  end

  defp consume_import_upload(socket) do
    consume_uploaded_entries(socket, :import_file, fn %{path: path}, entry ->
      prepare_uploaded_entry(socket, path, entry.client_name)
    end)
  end

  defp prepare_uploaded_entry(socket, path, client_name) do
    case File.read(path) do
      {:ok, binary} ->
        {:ok,
         Imports.prepare_import(
           socket.assigns.current_scope,
           socket.assigns.project,
           client_name,
           binary
         )}

      {:error, _reason} ->
        {:ok, {:error, :upload_unavailable}}
    end
  end

  defp execute_ready_import(socket, %{step: "preview", attempt_id: attempt_id} = state) when is_integer(attempt_id) do
    case Imports.enqueue_import(socket.assigns.current_scope, attempt_id, state.conflict_strategy) do
      {:ok, attempt} -> {:noreply, assign_import_attempt(socket, attempt)}
      {:error, reason} -> {:noreply, assign_import_error(socket, reason)}
    end
  end

  defp execute_ready_import(socket, _state), do: {:noreply, socket}

  defp apply_prepare_result(socket, {:ok, attempt, preview}) do
    step = if attempt.status == "ready", do: "preview", else: "queued"

    state = %{
      step: step,
      attempt_id: attempt.id,
      preview: serialize_preview(preview),
      error: nil,
      conflict_strategy: "rename",
      warning_codes: attempt.warning_codes,
      status: attempt.status
    }

    assign(socket, :import_state, state)
  end

  defp apply_prepare_result(socket, {:error, reason}), do: assign_import_error(socket, reason)
  defp apply_prepare_result(socket, nil), do: assign_import_error(socket, :upload_unavailable)

  defp serialize_preview(preview) do
    %{
      counts: stringify_map_keys(preview.counts),
      conflicts: stringify_conflicts(preview.conflicts),
      has_conflicts: preview.has_conflicts
    }
  end

  defp stringify_map_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_conflicts(conflicts) do
    Map.new(conflicts, fn {key, values} -> {to_string(key), values} end)
  end

  defp assign_import_attempt(socket, attempt) do
    state = socket.assigns.import_state

    step =
      case attempt.status do
        "ready" -> "preview"
        status when status in ["queued", "running", "retrying"] -> "queued"
        "completed" -> "done"
        _status -> "error"
      end

    state = %{
      state
      | step: step,
        status: attempt.status,
        error: if(step == "error", do: attempt.error_message || generic_import_error())
    }

    assign(socket, :import_state, state)
  end

  defp assign_import_error(socket, reason) do
    state = %{
      socket.assigns.import_state
      | step: "error",
        error: import_error_message(reason),
        status: "failed"
    }

    assign(socket, :import_state, state)
  end

  defp update_import_state(socket, fun) do
    assign(socket, :import_state, fun.(socket.assigns.import_state))
  end

  defp maybe_cancel_ready_import(socket) do
    case socket.assigns.import_state do
      %{attempt_id: attempt_id, status: "ready"} when is_integer(attempt_id) ->
        Imports.cancel_import(socket.assigns.current_scope, attempt_id)

      _other ->
        :ok
    end
  end

  defp import_error_message(reason) when reason in [:duplicate_yarn_node_title, :import_plan_has_errors] do
    dgettext(
      "projects",
      "This Yarn project uses narrative logic that Storyarn cannot import safely. No project content was changed."
    )
  end

  defp import_error_message(reason)
       when reason in [
              :archive_entry_too_large,
              :archive_expansion_ratio_exceeded,
              :archive_missing_yarn_files,
              :archive_too_large,
              :archive_too_many_entries,
              :duplicate_archive_entry,
              :file_too_large,
              :invalid_archive,
              :invalid_archive_path,
              :invalid_text_encoding,
              :nested_archive_not_allowed,
              :unsupported_archive_entry,
              :unsupported_import_format,
              :yarn_document_limit_exceeded,
              :yarn_statement_limit_exceeded
            ] do
    dgettext("projects", "The selected Yarn project is invalid or exceeds the import safety limits.")
  end

  defp import_error_message(_reason), do: generic_import_error()

  defp generic_import_error do
    dgettext("projects", "The import could not be completed. No project content was changed.")
  end
end

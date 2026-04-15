defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Exports
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Imports
  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  @all_sections ~w(sheets flows scenes screenplays localization)a

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
      back_label={dgettext("projects", "Back to project")}
      sidebar_sections={project_settings_sections(@workspace, @project)}
    >
      <:title>{gettext("Export & Import")}</:title>
      <:subtitle>{gettext("Export your project data or import from a file.")}</:subtitle>

      <.vue
        v-component="modules/project-settings/ExportImport"
        v-socket={@socket}
        id="export-import-vue"
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
              validateBeforeExport: @validate_before_export,
              prettyPrint: @pretty_print
            },
            validation: serialize_validation_result(@validation_result),
            downloadUrl: export_download_url(assigns)
          }
        }
        can-edit={@can_edit}
        import-state={
          %{
            step: to_string(@import_step),
            preview: @import_preview,
            result: @import_result,
            error: serialize_import_error(@import_error),
            conflictStrategy: to_string(@conflict_strategy)
          }
        }
        upload-config={if @can_edit, do: @uploads.import_file, else: nil}
      />

      <%!--
      Hidden file upload form. The Vue component owns the visible import UI,
      but LiveView's upload plumbing needs a <.live_file_input> mounted in the
      DOM to receive the file entries. Keeping it hidden (and outside the Vue
      island) leaves the UX untouched while making the upload flow testable.
      --%>
      <form
        :if={@can_edit && @uploads[:import_file]}
        id="import-form"
        phx-change="validate_upload"
        phx-submit="parse_import"
        class="hidden"
      >
        <.live_file_input upload={@uploads.import_file} />
      </form>
    </Layouts.settings>
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
        sections: Enum.map(fmt.sections, &to_string/1)
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

  defp serialize_import_error(nil), do: nil
  defp serialize_import_error(error), do: format_import_error(error)

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)
        formats = Exports.list_formats_with_metadata()
        default_format = List.first(formats)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:current_path, "")
          # Export state
          |> assign(:formats, formats)
          |> assign(:selected_format, :storyarn)
          |> assign(:selected_extension, default_format.extension)
          |> assign(:supported_sections, default_format.sections)
          |> assign(:sections, MapSet.new(@all_sections))
          |> assign(:entity_counts, %{})
          |> assign_async(:entity_counts_async, fn ->
            opts = %ExportOptions{format: :storyarn}
            {:ok, %{entity_counts_async: Exports.count_entities(project.id, opts)}}
          end)
          |> assign(:asset_mode, :references)
          |> assign(:validate_before_export, true)
          |> assign(:pretty_print, true)
          |> assign(:validation_result, nil)
          # Import state
          |> assign(:import_step, :upload)
          |> assign(:import_preview, nil)
          |> assign(:import_result, nil)
          |> assign(:import_error, nil)
          |> assign(:conflict_strategy, :skip)
          |> assign(:parsed_data_ref, nil)
          |> maybe_allow_import_upload(can_edit)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
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
  @valid_strategies ~w(skip overwrite rename)a

  @impl true
  def handle_event("set_format", %{"format" => format_str}, socket) do
    case Enum.find(socket.assigns.formats, &(to_string(&1.format) == format_str)) do
      nil ->
        {:noreply, socket}

      fmt_meta ->
        socket =
          socket
          |> assign(:selected_format, fmt_meta.format)
          |> assign(:selected_extension, fmt_meta.extension)
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

        {:noreply, assign(socket, :sections, sections)}
    end
  end

  def handle_event("set_asset_mode", %{"mode" => mode_str}, socket) do
    case Enum.find(@valid_asset_modes, &(to_string(&1) == mode_str)) do
      nil -> {:noreply, socket}
      mode -> {:noreply, assign(socket, :asset_mode, mode)}
    end
  end

  def handle_event("toggle_option", %{"option" => "validate_before_export"}, socket) do
    {:noreply, assign(socket, :validate_before_export, !socket.assigns.validate_before_export)}
  end

  def handle_event("toggle_option", %{"option" => "pretty_print"}, socket) do
    {:noreply, assign(socket, :pretty_print, !socket.assigns.pretty_print)}
  end

  def handle_event("validate_export", _params, socket) do
    opts = build_export_options(socket.assigns)
    result = Exports.validate_project(socket.assigns.project.id, opts)
    {:noreply, assign(socket, :validation_result, result)}
  end

  # ===========================================================================
  # Events — Import
  # ===========================================================================

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("parse_import", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      socket
      |> consume_and_parse_import()
      |> handle_parse_result(socket)
    end)
  end

  def handle_event("set_strategy", %{"strategy" => strategy_str}, socket) do
    case Enum.find(@valid_strategies, &(to_string(&1) == strategy_str)) do
      nil -> {:noreply, socket}
      strategy -> {:noreply, assign(socket, :conflict_strategy, strategy)}
    end
  end

  def handle_event("execute_import", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      ref = socket.assigns.parsed_data_ref

      case take_import_data(ref) do
        nil ->
          {:noreply,
           socket
           |> assign(:import_step, :error)
           |> assign(:import_error, :session_expired)
           |> assign(:parsed_data_ref, nil)}

        data ->
          do_execute_import(socket, data)
      end
    end)
  end

  def handle_event("reset_import", _params, socket) do
    cleanup_import_staging(socket)

    {:noreply,
     socket
     |> assign(:import_step, :upload)
     |> assign(:import_preview, nil)
     |> assign(:import_result, nil)
     |> assign(:import_error, nil)
     |> assign(:conflict_strategy, :skip)
     |> assign(:parsed_data_ref, nil)}
  end

  defp consume_and_parse_import(socket) do
    case consume_uploaded_entries(socket, :import_file, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [binary] ->
        with {:ok, %{data: data}} <- Imports.parse_file(binary),
             {:ok, preview} <- Imports.preview(socket.assigns.project.id, data) do
          {:ok, data, preview}
        end

      [] ->
        {:error, :no_file}
    end
  end

  defp handle_parse_result({:ok, data, preview}, socket) do
    cleanup_import_staging(socket)
    ref = make_ref()
    :ets.insert(:import_staging, {ref, data})

    {:noreply,
     socket
     |> assign(:import_step, :preview)
     |> assign(:import_preview, preview)
     |> assign(:parsed_data_ref, ref)}
  end

  defp handle_parse_result({:error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:import_step, :error)
     |> assign(:import_error, reason)}
  end

  defp take_import_data(ref) do
    case :ets.lookup(:import_staging, ref) do
      [{^ref, data}] ->
        :ets.delete(:import_staging, ref)
        data

      [] ->
        nil
    end
  end

  defp do_execute_import(socket, data) do
    project = socket.assigns.project
    strategy = socket.assigns.conflict_strategy

    case Imports.execute(project, data, conflict_strategy: strategy) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:import_step, :done)
         |> assign(:import_result, result)
         |> assign(:parsed_data_ref, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:import_step, :error)
         |> assign(:import_error, reason)
         |> assign(:parsed_data_ref, nil)}
    end
  end

  # ===========================================================================
  # Helpers — Export
  # ===========================================================================

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
      |> maybe_add("assets", to_string(assigns.asset_mode), assigns.asset_mode != :references)

    URI.encode_query(params)
  end

  defp maybe_add(params, key, value, true), do: [{key, value} | params]
  defp maybe_add(params, _key, _value, false), do: params

  # ===========================================================================
  # Helpers — Import
  # ===========================================================================

  defp format_import_error(:no_file), do: gettext("No file was uploaded. Please select a file and try again.")

  defp format_import_error(:session_expired), do: gettext("Import session expired. Please upload the file again.")

  defp format_import_error(:invalid_json), do: gettext("Invalid JSON file.")

  defp format_import_error(:invalid_json_structure), do: gettext("File is not a valid JSON object.")

  defp format_import_error(:file_too_large), do: gettext("File exceeds the 50 MB size limit.")

  defp format_import_error({:missing_required_keys, keys}),
    do: gettext("Missing required keys: %{keys}", keys: Enum.join(keys, ", "))

  defp format_import_error({:invalid_field_types, fields}),
    do: gettext("Invalid field types: %{fields}", fields: Enum.join(fields, ", "))

  defp format_import_error({:entity_limits_exceeded, _details}), do: gettext("Import file exceeds entity count limits.")

  defp format_import_error({:import_failed, context, _changeset}),
    do: gettext("Import failed at %{context}.", context: inspect(context))

  defp format_import_error(other), do: gettext("Import error: %{details}", details: inspect(other))

  @impl true
  def terminate(_reason, socket) do
    cleanup_import_staging(socket)
    :ok
  end

  defp cleanup_import_staging(socket) do
    case socket.assigns[:parsed_data_ref] do
      nil -> :ok
      ref -> :ets.delete(:import_staging, ref)
    end
  end

  defp maybe_allow_import_upload(socket, true) do
    allow_upload(socket, :import_file,
      accept: ~w(.json),
      max_entries: 1,
      max_file_size: 50_000_000
    )
  end

  defp maybe_allow_import_upload(socket, false), do: socket

  defp project_settings_sections(workspace, project) do
    StoryarnWeb.ProjectLive.Components.SettingsComponents.project_settings_sections(
      workspace,
      project
    )
  end
end

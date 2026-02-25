defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Exports
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Imports
  alias Storyarn.Projects

  @all_sections ~w(sheets flows scenes screenplays localization)a

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:export_import}
      has_tree={false}
      can_edit={@can_edit}
    >
      <div class="max-w-2xl mx-auto mt-6 space-y-8 pb-12">
        <.header>
          {gettext("Export & Import")}
          <:subtitle>
            {gettext("Export your project data or import from a file.")}
          </:subtitle>
        </.header>

        <%!-- ===== Export section ===== --%>
        <section class="space-y-5">
          <h2 class="text-lg font-semibold">{gettext("Export")}</h2>

          <%!-- Format selector --%>
          <.format_selector
            formats={@formats}
            selected_format={@selected_format}
          />

          <%!-- Content section checkboxes --%>
          <.content_sections
            sections={@sections}
            entity_counts={@entity_counts}
            supported_sections={@supported_sections}
          />

          <%!-- Asset mode --%>
          <.asset_mode_selector asset_mode={@asset_mode} />

          <%!-- Options --%>
          <.export_options
            validate_before_export={@validate_before_export}
            pretty_print={@pretty_print}
          />

          <%!-- Actions --%>
          <div class="flex items-center gap-3 pt-2">
            <button phx-click="validate_export" class="btn btn-sm btn-outline">
              <.icon name="shield-check" class="size-4" />
              {gettext("Validate")}
            </button>

            <a
              href={export_download_url(assigns)}
              class="btn btn-sm btn-primary"
            >
              <.icon name="download" class="size-4" />
              {gettext("Download .%{ext}", ext: @selected_extension)}
            </a>
          </div>

          <.validation_results :if={@validation_result} result={@validation_result} />
        </section>

        <div class="divider" />

        <%!-- ===== Import section ===== --%>
        <section class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Import")}</h2>

          <%= if @can_edit do %>
            <.import_step_upload
              :if={@import_step == :upload}
              uploads={@uploads}
            />

            <.import_step_preview
              :if={@import_step == :preview}
              preview={@import_preview}
              conflict_strategy={@conflict_strategy}
            />

            <.import_step_done
              :if={@import_step == :done}
              result={@import_result}
            />

            <.import_step_error
              :if={@import_step == :error}
              error={@import_error}
            />
          <% else %>
            <div class="alert">
              <.icon name="lock" class="size-4" />
              <span>{gettext("You need edit permissions to import data.")}</span>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Export components
  # ===========================================================================

  defp format_selector(assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium">{gettext("Format")}</label>
      <div class="flex flex-col gap-1">
        <label
          :for={fmt <- @formats}
          class={[
            "label cursor-pointer justify-start gap-3 rounded-lg px-3 py-2",
            @selected_format == fmt.format && "bg-base-200"
          ]}
        >
          <input
            type="radio"
            name="format"
            value={fmt.format}
            checked={@selected_format == fmt.format}
            phx-click="set_format"
            phx-value-format={fmt.format}
            class="radio radio-sm radio-primary"
          />
          <span class="label-text">{fmt.label}</span>
        </label>
      </div>
    </div>
    """
  end

  defp content_sections(assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium">{gettext("Content")}</label>
      <div class="flex flex-col gap-1">
        <label
          :for={{section, label} <- section_labels()}
          class="label cursor-pointer justify-start gap-3"
        >
          <input
            type="checkbox"
            checked={section in @sections}
            disabled={section not in @supported_sections}
            phx-click="toggle_section"
            phx-value-section={section}
            class="checkbox checkbox-sm checkbox-primary"
          />
          <span class={[
            "label-text",
            section not in @supported_sections && "opacity-40"
          ]}>
            {label}
            <span :if={count = Map.get(@entity_counts, section)} class="text-base-content/50">
              ({count})
            </span>
          </span>
        </label>
      </div>
    </div>
    """
  end

  defp asset_mode_selector(assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium">{gettext("Assets")}</label>
      <div class="flex flex-col gap-1">
        <label
          :for={{value, label} <- asset_mode_options()}
          class="label cursor-pointer justify-start gap-3"
        >
          <input
            type="radio"
            name="asset_mode"
            value={value}
            checked={@asset_mode == value}
            phx-click="set_asset_mode"
            phx-value-mode={value}
            class="radio radio-sm"
          />
          <span class="label-text">{label}</span>
        </label>
      </div>
    </div>
    """
  end

  defp export_options(assigns) do
    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium">{gettext("Options")}</label>
      <div class="flex flex-col gap-1">
        <label class="label cursor-pointer justify-start gap-3">
          <input
            type="checkbox"
            checked={@validate_before_export}
            phx-click="toggle_option"
            phx-value-option="validate_before_export"
            class="checkbox checkbox-sm"
          />
          <span class="label-text">{gettext("Validate before export")}</span>
        </label>
        <label class="label cursor-pointer justify-start gap-3">
          <input
            type="checkbox"
            checked={@pretty_print}
            phx-click="toggle_option"
            phx-value-option="pretty_print"
            class="checkbox checkbox-sm"
          />
          <span class="label-text">{gettext("Pretty print output")}</span>
        </label>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Validation component
  # ===========================================================================

  defp validation_results(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class={[
        "badge gap-1",
        @result.status == :passed && "badge-success",
        @result.status == :warnings && "badge-warning",
        @result.status == :errors && "badge-error"
      ]}>
        {validation_status_label(@result.status)}
      </div>

      <div :if={@result.errors != []} class="space-y-1">
        <div
          :for={finding <- @result.errors}
          class="flex items-start gap-2 text-sm text-error"
        >
          <.icon name="circle-x" class="size-4 mt-0.5 shrink-0" />
          <span>{finding.message}</span>
        </div>
      </div>

      <div :if={@result.warnings != []} class="space-y-1">
        <div
          :for={finding <- @result.warnings}
          class="flex items-start gap-2 text-sm text-warning"
        >
          <.icon name="alert-triangle" class="size-4 mt-0.5 shrink-0" />
          <span>{finding.message}</span>
        </div>
      </div>

      <div :if={@result.info != []} class="space-y-1">
        <div
          :for={finding <- @result.info}
          class="flex items-start gap-2 text-sm text-info"
        >
          <.icon name="info" class="size-4 mt-0.5 shrink-0" />
          <span>{finding.message}</span>
        </div>
      </div>

      <p :if={@result.status == :passed && @result.info == []} class="text-sm text-success">
        {gettext("No issues found. Project is ready for export.")}
      </p>
    </div>
    """
  end

  # ===========================================================================
  # Import components
  # ===========================================================================

  defp import_step_upload(assigns) do
    ~H"""
    <form id="import-form" phx-submit="parse_import" phx-change="validate_upload" class="space-y-3">
      <div class="form-control">
        <label class="label">
          <span class="label-text">{gettext("Select a .storyarn.json file")}</span>
        </label>
        <.live_file_input upload={@uploads.import_file} class="file-input file-input-bordered w-full" />
      </div>

      <div :for={entry <- @uploads.import_file.entries} class="text-sm">
        <span>{entry.client_name}</span>
        <span class="text-base-content/60">({format_file_size(entry.client_size)})</span>
        <div :for={err <- upload_errors(@uploads.import_file, entry)} class="text-error text-sm">
          {upload_error_message(err)}
        </div>
      </div>

      <button
        type="submit"
        class="btn btn-sm btn-primary"
        disabled={@uploads.import_file.entries == []}
      >
        <.icon name="eye" class="size-4" />
        {gettext("Upload & Preview")}
      </button>
    </form>
    """
  end

  defp import_step_preview(assigns) do
    ~H"""
    <div class="space-y-4">
      <h3 class="text-base font-medium">{gettext("Import preview")}</h3>

      <%!-- Entity counts --%>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Entity")}</th>
              <th class="text-right">{gettext("Count")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{entity, count} <- entity_count_rows(@preview.counts)}>
              <td class="capitalize">{entity}</td>
              <td class="text-right">{count}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Conflicts --%>
      <div :if={@preview.has_conflicts} class="space-y-2">
        <h4 class="text-sm font-medium text-warning">{gettext("Shortcut conflicts detected")}</h4>
        <div :for={{type, shortcuts} <- @preview.conflicts} class="text-sm">
          <span class="font-medium capitalize">{type}:</span>
          <span class="text-base-content/70">{Enum.join(shortcuts, ", ")}</span>
        </div>

        <div class="form-control space-y-1">
          <label class="label">
            <span class="label-text">{gettext("Conflict resolution strategy")}</span>
          </label>
          <div class="flex flex-col gap-1">
            <label
              :for={{value, label} <- strategy_options()}
              class="label cursor-pointer justify-start gap-2"
            >
              <input
                type="radio"
                name="conflict_strategy"
                value={value}
                checked={@conflict_strategy == value}
                phx-click="set_strategy"
                phx-value-strategy={value}
                class="radio radio-sm"
              />
              <span class="label-text">{label}</span>
            </label>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <button phx-click="execute_import" class="btn btn-sm btn-primary">
          <.icon name="upload" class="size-4" />
          {gettext("Import")}
        </button>
        <button phx-click="reset_import" class="btn btn-sm btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end

  defp import_step_done(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="alert alert-success">
        <.icon name="check-circle" class="size-5" />
        <span>{gettext("Import completed successfully!")}</span>
      </div>

      <div :if={@result} class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Entity")}</th>
              <th class="text-right">{gettext("Imported")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{entity, items} <- import_result_rows(@result)}>
              <td class="capitalize">{entity}</td>
              <td class="text-right">{format_import_count(items)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <button phx-click="reset_import" class="btn btn-sm btn-ghost">
        {gettext("Import another")}
      </button>
    </div>
    """
  end

  defp import_step_error(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="alert alert-error">
        <.icon name="alert-triangle" class="size-5" />
        <span>{format_import_error(@error)}</span>
      </div>

      <button phx-click="reset_import" class="btn btn-sm btn-ghost">
        {gettext("Try again")}
      </button>
    </div>
    """
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
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
          |> assign(:can_edit, can_edit)
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
    with_authorization(socket, :edit_content, fn socket ->
      [binary] =
        consume_uploaded_entries(socket, :import_file, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      with {:ok, %{data: data}} <- Imports.parse_file(binary),
           {:ok, preview} <- Imports.preview(socket.assigns.project.id, data) do
        ref = make_ref()
        :ets.insert(:import_staging, {ref, data})

        {:noreply,
         socket
         |> assign(:import_step, :preview)
         |> assign(:import_preview, preview)
         |> assign(:parsed_data_ref, ref)}
      else
        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:import_step, :error)
           |> assign(:import_error, reason)}
      end
    end)
  end

  def handle_event("set_strategy", %{"strategy" => strategy_str}, socket) do
    case Enum.find(@valid_strategies, &(to_string(&1) == strategy_str)) do
      nil -> {:noreply, socket}
      strategy -> {:noreply, assign(socket, :conflict_strategy, strategy)}
    end
  end

  def handle_event("execute_import", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
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

  defp section_labels do
    [
      {:sheets, gettext("Sheets")},
      {:flows, gettext("Flows")},
      {:scenes, gettext("Scenes")},
      {:screenplays, gettext("Screenplays")},
      {:localization, gettext("Localization")}
    ]
  end

  defp asset_mode_options do
    [
      {:references, gettext("References only (URLs in output)")},
      {:embedded, gettext("Embedded (Base64 — larger file)")},
      {:bundled, gettext("Bundled (ZIP with assets folder)")}
    ]
  end

  # ===========================================================================
  # Helpers — Validation
  # ===========================================================================

  defp validation_status_label(:passed), do: gettext("Passed")
  defp validation_status_label(:warnings), do: gettext("Warnings")
  defp validation_status_label(:errors), do: gettext("Errors")

  # ===========================================================================
  # Helpers — Import
  # ===========================================================================

  defp entity_count_rows(counts) do
    [
      {gettext("Sheets"), Map.get(counts, :sheets, 0)},
      {gettext("Flows"), Map.get(counts, :flows, 0)},
      {gettext("Nodes"), Map.get(counts, :nodes, 0)},
      {gettext("Scenes"), Map.get(counts, :scenes, 0)},
      {gettext("Screenplays"), Map.get(counts, :screenplays, 0)},
      {gettext("Assets"), Map.get(counts, :assets, 0)}
    ]
    |> Enum.reject(fn {_, count} -> count == 0 end)
  end

  defp strategy_options do
    [
      {:skip, gettext("Skip — keep existing, ignore conflicts")},
      {:overwrite, gettext("Overwrite — replace existing entities")},
      {:rename, gettext("Rename — import with a new shortcut")}
    ]
  end

  defp import_result_rows(result) when is_map(result) do
    [
      {gettext("Assets"), Map.get(result, :assets)},
      {gettext("Sheets"), Map.get(result, :sheets)},
      {gettext("Flows"), Map.get(result, :flows)},
      {gettext("Scenes"), Map.get(result, :scenes)},
      {gettext("Screenplays"), Map.get(result, :screenplays)},
      {gettext("Localization"), Map.get(result, :localization)}
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == [] or v == %{} end)
  end

  defp format_import_count(items) when is_list(items), do: length(items)
  defp format_import_count(%{} = map), do: inspect(map)
  defp format_import_count(other), do: inspect(other)

  defp format_file_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_file_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_file_size(bytes), do: "#{bytes} B"

  defp format_import_error(:session_expired),
    do: gettext("Import session expired. Please upload the file again.")

  defp format_import_error(:invalid_json), do: gettext("Invalid JSON file.")

  defp format_import_error(:invalid_json_structure),
    do: gettext("File is not a valid JSON object.")

  defp format_import_error(:file_too_large), do: gettext("File exceeds the 50 MB size limit.")

  defp format_import_error({:missing_required_keys, keys}),
    do: gettext("Missing required keys: %{keys}", keys: Enum.join(keys, ", "))

  defp format_import_error({:entity_limits_exceeded, _details}),
    do: gettext("Import file exceeds entity count limits.")

  defp format_import_error({:import_failed, context, _changeset}),
    do: gettext("Import failed at %{context}.", context: inspect(context))

  defp format_import_error(other),
    do: gettext("Import error: %{details}", details: inspect(other))

  defp upload_error_message(:too_large), do: gettext("File is too large (max 50 MB).")
  defp upload_error_message(:not_accepted), do: gettext("Only .json files are accepted.")
  defp upload_error_message(:too_many_files), do: gettext("Only one file at a time.")

  defp upload_error_message(other),
    do: gettext("Upload error: %{details}", details: inspect(other))

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
end

defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Exports
  alias Storyarn.Exports.ExportOptions

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
      <:title>{dgettext("projects", "Export")}</:title>
      <:subtitle>{dgettext("projects", "Export your project data.")}</:subtitle>

      <.vue
        v-component="live/project/settings/export-import/ProjectSettingsExportImport"
        v-socket={@socket}
        v-inject="settings-layout"
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

        {:noreply, assign(socket, :sections, sections)}
    end
  end

  def handle_event("set_asset_mode", %{"mode" => mode_str}, socket) do
    case Enum.find(@valid_asset_modes, &(to_string(&1) == mode_str)) do
      nil -> {:noreply, socket}
      mode -> {:noreply, assign(socket, :asset_mode, mode)}
    end
  end

  def handle_event("set_localization_policy", %{"policy" => policy_str}, socket) do
    case Enum.find(@valid_localization_policies, &(to_string(&1) == policy_str)) do
      nil -> {:noreply, socket}
      policy -> {:noreply, assign(socket, :localization_policy, policy)}
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
end

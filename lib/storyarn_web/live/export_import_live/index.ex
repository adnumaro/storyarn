defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Exports
  alias Storyarn.Imports
  alias Storyarn.Projects

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

        <%!-- Export section --%>
        <section class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Export")}</h2>

          <div class="flex items-center gap-3">
            <button phx-click="validate_export" class="btn btn-sm btn-outline">
              <.icon name="shield-check" class="size-4" />
              {gettext("Validate")}
            </button>

            <a
              href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/export/storyarn"}
              class="btn btn-sm btn-primary"
            >
              <.icon name="download" class="size-4" />
              {gettext("Download .storyarn.json")}
            </a>
          </div>

          <.validation_results :if={@validation_result} result={@validation_result} />
        </section>

        <div class="divider" />

        <%!-- Import section --%>
        <section class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Import")}</h2>

          <%= if !@can_edit do %>
            <div class="alert">
              <.icon name="lock" class="size-4" />
              <span>{gettext("You need edit permissions to import data.")}</span>
            </div>
          <% else %>
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
          <% end %>
        </section>
      </div>
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Components
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
            <label :for={{value, label} <- strategy_options()} class="label cursor-pointer justify-start gap-2">
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
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:can_edit, can_edit)
          |> assign(:validation_result, nil)
          |> assign(:import_step, :upload)
          |> assign(:import_preview, nil)
          |> assign(:import_result, nil)
          |> assign(:import_error, nil)
          |> assign(:conflict_strategy, :skip)
          |> assign(:parsed_data, nil)
          |> maybe_allow_import_upload(can_edit)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("validate_export", _params, socket) do
    result = Exports.validate_project(socket.assigns.project.id)
    {:noreply, assign(socket, :validation_result, result)}
  end

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
        {:noreply,
         socket
         |> assign(:import_step, :preview)
         |> assign(:import_preview, preview)
         |> assign(:parsed_data, data)}
      else
        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:import_step, :error)
           |> assign(:import_error, reason)}
      end
    end)
  end

  def handle_event("set_strategy", %{"strategy" => strategy}, socket) do
    {:noreply, assign(socket, :conflict_strategy, String.to_existing_atom(strategy))}
  end

  def handle_event("execute_import", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      project = socket.assigns.project
      data = socket.assigns.parsed_data
      strategy = socket.assigns.conflict_strategy

      case Imports.execute(project, data, conflict_strategy: strategy) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(:import_step, :done)
           |> assign(:import_result, result)
           |> assign(:parsed_data, nil)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:import_step, :error)
           |> assign(:import_error, reason)
           |> assign(:parsed_data, nil)}
      end
    end)
  end

  def handle_event("reset_import", _params, socket) do
    {:noreply,
     socket
     |> assign(:import_step, :upload)
     |> assign(:import_preview, nil)
     |> assign(:import_result, nil)
     |> assign(:import_error, nil)
     |> assign(:conflict_strategy, :skip)
     |> assign(:parsed_data, nil)}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp validation_status_label(:passed), do: gettext("Passed")
  defp validation_status_label(:warnings), do: gettext("Warnings")
  defp validation_status_label(:errors), do: gettext("Errors")

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

  defp format_import_error(:invalid_json), do: gettext("Invalid JSON file.")
  defp format_import_error(:invalid_json_structure), do: gettext("File is not a valid JSON object.")
  defp format_import_error(:file_too_large), do: gettext("File exceeds the 50 MB size limit.")

  defp format_import_error({:missing_required_keys, keys}),
    do: gettext("Missing required keys: %{keys}", keys: Enum.join(keys, ", "))

  defp format_import_error({:entity_limits_exceeded, _details}),
    do: gettext("Import file exceeds entity count limits.")

  defp format_import_error({:import_failed, context, _changeset}),
    do: gettext("Import failed at %{context}.", context: inspect(context))

  defp format_import_error(other), do: gettext("Import error: %{details}", details: inspect(other))

  defp upload_error_message(:too_large), do: gettext("File is too large (max 50 MB).")
  defp upload_error_message(:not_accepted), do: gettext("Only .json files are accepted.")
  defp upload_error_message(:too_many_files), do: gettext("Only one file at a time.")
  defp upload_error_message(other), do: gettext("Upload error: %{details}", details: inspect(other))

  defp maybe_allow_import_upload(socket, true) do
    allow_upload(socket, :import_file,
      accept: ~w(.json),
      max_entries: 1,
      max_file_size: 50_000_000
    )
  end

  defp maybe_allow_import_upload(socket, false), do: socket
end

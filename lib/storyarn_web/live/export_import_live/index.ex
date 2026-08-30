defmodule StoryarnWeb.ExportImportLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias StoryarnWeb.Helpers.Authorize

  @all_sections ~w(sheets flows scenes localization)a
  @archive_export_formats ~w(ink yarn godot unreal articy)a
  @max_safe_import_attempt_id 9_007_199_254_740_991
  @recoverable_import_preflight_errors [
    :import_replace_not_eligible,
    :invalid_import_snapshot_request,
    :replace_import_confirmation_required,
    :stale_import_mode
  ]

  defguardp valid_import_attempt_id(attempt_id)
            when is_integer(attempt_id) and attempt_id > 0 and
                   attempt_id <= @max_safe_import_attempt_id

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
        can-import={@can_import}
        resume-storage-key={Projects.project_import_resume_storage_key(@current_scope, @project)}
        import-state={serialize_import_state(@import_state)}
        upload-config={if(@can_import, do: @uploads.import_file, else: nil)}
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
            validation: serialize_validation_result(@validation_result, assigns),
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

  defp serialize_validation_result(nil, _assigns), do: nil

  defp serialize_validation_result(result, assigns) do
    %{
      status: to_string(result.status),
      stale: validation_stale?(assigns),
      errors: Enum.map(result.errors, &serialize_finding(&1, assigns)),
      warnings: Enum.map(result.warnings, &serialize_finding(&1, assigns)),
      info: Enum.map(result.info, &serialize_finding(&1, assigns))
    }
  end

  defp serialize_finding(finding, assigns) do
    %{
      message: finding.message,
      rule: to_string(finding.rule),
      label: finding[:entity_label],
      count: finding[:count],
      entityType: finding[:entity_type],
      entityId: finding[:entity_id],
      href: finding_href(finding, assigns)
    }
  end

  defp finding_href(%{dashboard: :flows}, assigns) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows"
  end

  defp finding_href(%{flow_id: flow_id, node_id: node_id}, assigns) do
    base = ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{flow_id}"
    "#{base}?highlight=node:#{node_id}"
  end

  defp finding_href(%{flow_id: flow_id, entity_type: entity_type, entity_id: entity_id}, assigns)
       when entity_type != "flow" and not is_nil(entity_id) do
    base = ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{flow_id}"
    "#{base}?highlight=node:#{entity_id}"
  end

  defp finding_href(%{flow_id: flow_id}, assigns) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{flow_id}"
  end

  defp finding_href(%{sheet_id: sheet_id}, assigns) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/sheets/#{sheet_id}"
  end

  defp finding_href(_finding, _assigns), do: nil

  defp serialize_import_state(state) do
    %{
      step: state.step,
      stage: state.stage,
      attemptId: state.attempt_id,
      preview: state.preview,
      errorCode: state.error_code,
      conflictStrategy: state.conflict_strategy,
      importMode: state.import_mode,
      replaceEligible: state.replace_eligible,
      recoverySnapshotUrl: Map.get(state, :recovery_snapshot_url),
      warningCodes: state.warning_codes,
      status: state.status
    }
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    stale_project = socket.assigns.project

    if connected?(socket) do
      :ok = Projects.subscribe_project_ownership_changes(stale_project.id)
    end

    case Projects.reload_project(socket.assigns.current_scope, stale_project.id) do
      {:ok, project, membership} ->
        mount_project(socket, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces/#{stale_project.workspace.slug}")}
    end
  end

  defp mount_project(socket, project, membership) do
    current_user_id = socket.assigns.current_scope.user.id

    # Import rewrites project content wholesale, so it is owner-only. `can_edit`
    # is `:edit_content` and would have shown an editor a working file picker
    # that every import handler then rejects.
    can_import? =
      project.owner_id == current_user_id and
        Projects.can?(membership.role, :manage_project)

    formats = visible_export_formats()
    default_format = List.first(formats)
    default_sections = default_format.sections

    socket =
      socket
      |> assign(:project, project)
      |> assign(:workspace, project.workspace)
      |> assign(:membership, membership)
      |> assign(:can_edit, Projects.can?(membership.role, :edit_content))
      |> assign(:current_path, "")
      # Export state
      |> assign(:formats, formats)
      |> assign(:selected_format, default_format.format)
      |> assign(:selected_extension, download_extension(default_format))
      |> assign(:supported_sections, default_sections)
      |> assign(:sections, MapSet.new(@all_sections))
      |> assign(:entity_counts, %{})
      |> assign_async(:entity_counts_async, fn ->
        opts = Projects.project_export_options(%{format: default_format.format})
        {:ok, %{entity_counts_async: Projects.count_project_export_entities(project.id, opts)}}
      end)
      |> assign(:asset_mode, :references)
      |> assign(:localization_policy, :release)
      |> assign(:validate_before_export, true)
      |> assign(:pretty_print, true)
      |> assign(:validation_result, nil)
      |> assign(:validated_export_options, nil)
      # Import state. Files are consumed from LiveView's bounded temporary
      # upload and are never written under their client-provided filename.
      |> assign(:import_state, empty_import_state())
      |> assign(:can_import, can_import?)
      |> assign(:imports_subscribed?, false)
      |> allow_upload(:import_file,
        accept: [".yarn", ".zip"],
        max_entries: 1,
        max_file_size: 50_000_000
      )

    socket =
      if connected?(socket) and can_import? do
        socket
        |> ensure_project_import_subscription(project)
        |> recover_latest_import()
      else
        socket
      end

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
      nil ->
        {:noreply, socket}

      mode ->
        {:noreply, assign(socket, :asset_mode, mode)}
    end
  end

  def handle_event("set_localization_policy", %{"policy" => policy_str}, socket) do
    case Enum.find(@valid_localization_policies, &(to_string(&1) == policy_str)) do
      nil ->
        {:noreply, socket}

      policy ->
        {:noreply, assign(socket, :localization_policy, policy)}
    end
  end

  def handle_event("toggle_option", %{"option" => "validate_before_export"}, socket) do
    {:noreply, assign(socket, :validate_before_export, !socket.assigns.validate_before_export)}
  end

  def handle_event("toggle_option", %{"option" => "pretty_print"}, socket) do
    {:noreply, assign(socket, :pretty_print, !socket.assigns.pretty_print)}
  end

  def handle_event("validate_export", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      opts = build_export_options(socket.assigns)
      result = Projects.validate_project_export(socket.assigns.project.id, opts)

      {:noreply,
       socket
       |> assign(:validation_result, result)
       |> assign(:validated_export_options, opts)}
    end)
  end

  # ===========================================================================
  # Events — Import
  # ===========================================================================

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("parse_import", _params, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      results = consume_import_upload(socket)
      {:noreply, apply_prepare_result(socket, List.first(results))}
    end)
  end

  def handle_event("set_strategy", %{"attempt_id" => attempt_id, "strategy" => strategy}, socket)
      when valid_import_attempt_id(attempt_id) and strategy in ~w(skip overwrite rename) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case socket.assigns.import_state do
        %{step: "preview", attempt_id: ^attempt_id} ->
          update_import_strategy(socket, attempt_id, strategy)

        _stale_state ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("set_strategy", _params, socket), do: {:noreply, socket}

  def handle_event("set_import_mode", %{"attempt_id" => attempt_id, "import_mode" => import_mode}, socket)
      when valid_import_attempt_id(attempt_id) and import_mode in ~w(additive replace_project) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case socket.assigns.import_state do
        %{step: "preview", attempt_id: ^attempt_id} ->
          update_import_mode(socket, attempt_id, import_mode)

        _stale_state ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("set_import_mode", _params, socket), do: {:noreply, socket}

  def handle_event("save_import_review", %{"attempt_id" => attempt_id, "review_decisions" => decisions}, socket)
      when valid_import_attempt_id(attempt_id) and is_list(decisions) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case current_import_state(socket, attempt_id) do
        {:ok, state} -> save_import_review_draft(socket, state, decisions)
        :stale -> {:reply, %{ok: false, reason: "stale"}, socket}
      end
    end)
  end

  def handle_event("save_import_review", _params, socket) do
    {:reply, %{ok: false, reason: "invalid"}, socket}
  end

  def handle_event(
        "validate_import_review",
        %{"attempt_id" => attempt_id, "review_acknowledged" => acknowledged?, "review_decisions" => decisions},
        socket
      )
      when valid_import_attempt_id(attempt_id) and is_boolean(acknowledged?) and is_list(decisions) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case current_import_state(socket, attempt_id) do
        {:ok, state} -> validate_import_review(socket, state, acknowledged?, decisions)
        :stale -> {:reply, %{ok: false, reason: "stale"}, socket}
      end
    end)
  end

  def handle_event("validate_import_review", _params, socket) do
    {:reply, %{ok: false, reason: "invalid"}, socket}
  end

  def handle_event(
        "execute_import",
        %{
          "attempt_id" => attempt_id,
          "review_confirmation_fingerprint" => fingerprint,
          "import_mode" => import_mode,
          "replace_acknowledged" => replace_acknowledged?
        },
        socket
      )
      when valid_import_attempt_id(attempt_id) and is_binary(fingerprint) and import_mode in ~w(additive replace_project) and
             is_boolean(replace_acknowledged?) do
    execute_import_event(socket, attempt_id, fingerprint, import_mode, replace_acknowledged?)
  end

  # A tab loaded before this deployment can only know the additive workflow.
  # Keeping that in-flight action working is safe: a durable replacement mode
  # still fails the context's exact mode and acknowledgement preflight.
  def handle_event(
        "execute_import",
        %{"attempt_id" => attempt_id, "review_confirmation_fingerprint" => fingerprint},
        socket
      )
      when valid_import_attempt_id(attempt_id) and is_binary(fingerprint) do
    execute_import_event(socket, attempt_id, fingerprint, "additive", false)
  end

  def handle_event("execute_import", _params, socket) do
    {:reply, %{ok: false, reason: "invalid"}, socket}
  end

  # The reply is the client's cue to drop its durable browser reference: it
  # must never clear it before the server has actually terminalized the
  # attempt, or a refused reset silently loses the completed-restore path.
  def handle_event("reset_import", %{"attempt_id" => nil}, socket) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      if is_nil(socket.assigns.import_state.attempt_id) do
        {:reply, %{ok: true, attempt_id: nil}, assign(socket, :import_state, empty_import_state())}
      else
        {:reply, %{ok: false, reason: "stale"}, socket}
      end
    end)
  end

  def handle_event("reset_import", %{"attempt_id" => attempt_id}, socket) when valid_import_attempt_id(attempt_id) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      reset_import_attempt(socket, attempt_id)
    end)
  end

  def handle_event("reset_import", _params, socket) do
    {:reply, %{ok: false, reason: "invalid"}, socket}
  end

  def handle_event("resume_import", %{"attempt_id" => attempt_id}, socket) when valid_import_attempt_id(attempt_id) do
    reconcile_import_attempt(socket, attempt_id, wake_queue: true, protect_active: true)
  end

  def handle_event("reconcile_import", %{"attempt_id" => attempt_id}, socket) when valid_import_attempt_id(attempt_id) do
    if socket.assigns.import_state.attempt_id == attempt_id do
      reconcile_import_attempt(socket, attempt_id)
    else
      {:reply, %{ok: false, reason: "stale"}, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ["resume_import", "reconcile_import"] do
    {:reply, %{ok: false, reason: "invalid"}, socket}
  end

  @impl true
  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    case Projects.reload_project(socket.assigns.current_scope, project_id) do
      {:ok, project, membership} ->
        can_import? =
          project.owner_id == socket.assigns.current_scope.user.id and
            Projects.can?(membership.role, :manage_project)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, Projects.can?(membership.role, :edit_content))
          |> assign(:can_import, can_import?)

        socket =
          if can_import? do
            socket
            |> ensure_project_import_subscription(project)
            |> recover_latest_import()
          else
            assign(socket, :import_state, empty_import_state())
          end

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> push_navigate(to: ~p"/workspaces/#{socket.assigns.workspace.slug}")}
    end
  end

  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  def handle_info({:project_import_updated, _attempt}, %{assigns: %{can_import: false}} = socket) do
    {:noreply, socket}
  end

  def handle_info({:project_import_updated, %{id: _id} = attempt}, socket) do
    if socket.assigns.import_state.attempt_id == attempt.id do
      # PubSub delivery is not ordered across the enqueue caller and Oban
      # worker. Reload the durable attempt so a late queued/running message
      # cannot move a completed import back to an in-progress UI state.
      case Projects.get_project_import_attempt(socket.assigns.current_scope, attempt.id) do
        {:ok, current_attempt} ->
          socket = assign_import_attempt(socket, current_attempt)
          {:noreply, maybe_recover_active_after_terminal(socket, current_attempt)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp ensure_project_import_subscription(%{assigns: %{imports_subscribed?: true}} = socket, _project), do: socket

  defp ensure_project_import_subscription(socket, project) do
    :ok = Projects.subscribe_project_imports(project)
    assign(socket, :imports_subscribed?, true)
  end

  # ===========================================================================
  # Helpers — Export
  # ===========================================================================

  defp visible_export_formats, do: Projects.list_project_export_formats()

  defp download_extension(%{format: format}) when format in @archive_export_formats, do: "zip"
  defp download_extension(%{extension: extension}), do: extension

  defp build_export_options(assigns) do
    sections = assigns.sections

    Projects.project_export_options(%{
      format: assigns.selected_format,
      validate_before_export: assigns.validate_before_export,
      pretty_print: assigns.pretty_print,
      include_sheets: MapSet.member?(sections, :sheets),
      include_flows: MapSet.member?(sections, :flows),
      include_scenes: MapSet.member?(sections, :scenes),
      include_localization: MapSet.member?(sections, :localization),
      localization_policy: assigns.localization_policy,
      include_assets: assigns.asset_mode
    })
  end

  defp validation_stale?(assigns) do
    assigns.validated_export_options != build_export_options(assigns)
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

  defp execute_import_event(socket, attempt_id, fingerprint, import_mode, replace_acknowledged?) do
    Authorize.with_authorization(socket, :manage_project, fn socket ->
      case current_import_state(socket, attempt_id) do
        {:ok, state} ->
          execute_ready_import(
            socket,
            state,
            fingerprint,
            import_mode,
            replace_acknowledged?
          )

        :stale ->
          {:reply, %{ok: false, reason: "stale"}, socket}
      end
    end)
  end

  defp current_import_state(socket, attempt_id) do
    case socket.assigns.import_state do
      %{attempt_id: ^attempt_id} = state -> {:ok, state}
      _stale_state -> :stale
    end
  end

  defp reset_import_attempt(socket, attempt_id) do
    finish_import_reset(socket, attempt_id, cancel_import_attempt(socket, attempt_id))
  end

  defp finish_import_reset(socket, attempt_id, :ok) do
    socket =
      case current_import_state(socket, attempt_id) do
        {:ok, _state} -> socket |> assign(:import_state, empty_import_state()) |> recover_latest_import()
        :stale -> socket
      end

    {:reply, %{ok: true, attempt_id: attempt_id}, socket}
  end

  defp finish_import_reset(socket, attempt_id, {:error, :import_not_cancellable}) do
    case load_project_import_attempt(socket, attempt_id) do
      {:ok, attempt} ->
        finish_loaded_non_cancellable_reset(socket, attempt_id, attempt)

      :unavailable ->
        import_not_cancellable_reply(socket)
    end
  end

  # The queued job could not be cancelled: the import is still live, so the
  # panel and durable browser reference must both survive.
  defp finish_import_reset(socket, _attempt_id, {:error, :reset_failed}) do
    {:reply, %{ok: false, reason: "reset_failed"},
     put_flash(
       socket,
       :error,
       dgettext("projects", "The import could not be dismissed. Try again.")
     )}
  end

  defp finish_loaded_non_cancellable_reset(socket, attempt_id, attempt) do
    if attempt.status in Projects.project_import_active_statuses() do
      socket
      |> refresh_displayed_import_attempt(attempt_id, attempt)
      |> import_not_cancellable_reply()
    else
      # The socket lost the terminal PubSub update and tried to cancel the
      # stale ready/queued snapshot. The durable row is already safe to
      # dismiss, so acknowledge the reset instead of trapping the panel.
      finish_import_reset(socket, attempt_id, :ok)
    end
  end

  defp refresh_displayed_import_attempt(socket, attempt_id, attempt) do
    case current_import_state(socket, attempt_id) do
      {:ok, _state} -> assign_import_attempt(socket, attempt)
      :stale -> socket
    end
  end

  defp import_not_cancellable_reply(socket) do
    {:reply, %{ok: false, reason: "import_not_cancellable"},
     put_flash(
       socket,
       :error,
       dgettext(
         "projects",
         "This import is already running and cannot be dismissed. It will finish in the background."
       )
     )}
  end

  defp update_import_strategy(socket, attempt_id, strategy) do
    case Projects.update_project_import_strategy(socket.assigns.current_scope, attempt_id, strategy) do
      {:ok, attempt} ->
        {:noreply, assign_import_attempt(socket, attempt)}

      {:error, reason} ->
        {:noreply,
         reconcile_failed_import_mutation(socket, attempt_id, fn current_socket ->
           assign_import_error(current_socket, reason, current_socket.assigns.import_state.status)
         end)}
    end
  end

  defp update_import_mode(socket, attempt_id, import_mode) do
    case Projects.update_project_import_mode(socket.assigns.current_scope, attempt_id, import_mode) do
      {:ok, attempt} ->
        {:noreply, assign_import_attempt(socket, attempt)}

      {:error, _reason} ->
        {:noreply,
         reconcile_failed_import_mutation(
           socket,
           attempt_id,
           &Function.identity/1
         )}
    end
  end

  # Every mutation starts from an exact attempt id, but another tab can move
  # that row after the client rendered its ready snapshot. On any failure,
  # adopt a durable non-ready state before projecting a local error. Otherwise
  # a missed PubSub message can leave Reset operating forever on stale state.
  defp reconcile_failed_import_mutation(socket, attempt_id, ready_fallback) do
    case load_project_import_attempt(socket, attempt_id) do
      {:ok, %{status: "ready"}} ->
        ready_fallback.(socket)

      {:ok, attempt} ->
        socket
        |> assign_import_attempt(attempt)
        |> maybe_recover_active_after_terminal(attempt)

      :unavailable ->
        ready_fallback.(socket)
    end
  end

  defp reconcile_recoverable_import_preflight(socket, attempt_id, reason) do
    case load_project_import_attempt(socket, attempt_id) do
      {:ok, %{status: "ready"} = attempt} ->
        socket
        |> assign_import_attempt(attempt)
        |> assign_import_preview_error(reason)

      {:ok, attempt} ->
        socket
        |> assign_import_attempt(attempt)
        |> maybe_recover_active_after_terminal(attempt)

      :unavailable ->
        assign_import_preview_error(socket, reason)
    end
  end

  defp load_project_import_attempt(socket, attempt_id) do
    case Projects.get_project_import_attempt(socket.assigns.current_scope, attempt_id) do
      {:ok, %{project_id: project_id} = attempt}
      when project_id == socket.assigns.project.id ->
        {:ok, attempt}

      _unavailable ->
        :unavailable
    end
  end

  defp empty_import_state do
    %{
      step: "upload",
      stage: nil,
      attempt_id: nil,
      preview: nil,
      error: nil,
      error_code: nil,
      conflict_strategy: "rename",
      import_mode: "additive",
      replace_eligible: false,
      recovery_snapshot_url: nil,
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
         Projects.prepare_project_import(
           socket.assigns.current_scope,
           socket.assigns.project,
           client_name,
           binary
         )}

      {:error, _reason} ->
        {:ok, {:error, :upload_unavailable}}
    end
  end

  defp execute_ready_import(
         socket,
         %{step: "preview", attempt_id: attempt_id} = state,
         confirmation_fingerprint,
         import_mode,
         replace_acknowledged?
       )
       when is_integer(attempt_id) do
    case Projects.enqueue_project_import(socket.assigns.current_scope, attempt_id, state.conflict_strategy,
           review_confirmation_fingerprint: confirmation_fingerprint,
           import_mode: import_mode,
           replace_acknowledged: replace_acknowledged?
         ) do
      {:ok, attempt} ->
        {:reply, %{ok: true}, assign_import_attempt(socket, attempt)}

      {:error, reason} when reason in @recoverable_import_preflight_errors ->
        # These failures happen before queue acceptance and leave the durable
        # attempt ready. Keep the review usable, adopt any mode changed by a
        # concurrent tab, and expose only a stable code for localized copy.
        {:reply, %{ok: false, reason: "recoverable"}, reconcile_recoverable_import_preflight(socket, attempt_id, reason)}

      {:error, reason} when reason in [:import_review_required, :invalid_import_review_selection] ->
        # The stored review no longer authorizes this fingerprint; the client
        # must revalidate. A silent {:noreply} here left the button doing
        # nothing with no explanation.
        {:reply, %{ok: false, reason: "stale"},
         reconcile_failed_import_mutation(socket, attempt_id, &Function.identity/1)}

      {:error, reason} ->
        # Plan storage can fail without changing the durable attempt. Preserve
        # its ready status so Reset still terminalizes it instead of clearing
        # only the browser state and letting mount restore it again.
        {:reply, %{ok: false, reason: import_review_failure(reason)},
         reconcile_failed_import_mutation(socket, attempt_id, fn current_socket ->
           assign_import_error(current_socket, reason, state.status)
         end)}
    end
  end

  defp execute_ready_import(socket, _state, _confirmation_fingerprint, _import_mode, _replace_acknowledged?) do
    {:reply, %{ok: false, reason: "stale"}, socket}
  end

  defp save_import_review_draft(socket, %{step: "preview", attempt_id: attempt_id}, decisions)
       when is_integer(attempt_id) do
    case Projects.save_project_import_review(socket.assigns.current_scope, attempt_id, decisions) do
      {:ok, attempt, preview} ->
        {:reply, %{ok: true}, assign_import_attempt(socket, attempt, preview)}

      {:error, reason} ->
        {:reply, %{ok: false, reason: import_review_failure(reason)},
         reconcile_failed_import_mutation(socket, attempt_id, &Function.identity/1)}
    end
  end

  defp save_import_review_draft(socket, _state, _decisions) do
    {:reply, %{ok: false, reason: "stale"}, socket}
  end

  defp validate_import_review(socket, %{step: "preview", attempt_id: attempt_id}, acknowledged?, decisions)
       when is_integer(attempt_id) do
    case Projects.resolve_project_import_review(
           socket.assigns.current_scope,
           attempt_id,
           acknowledged?,
           decisions
         ) do
      {:ok, attempt, preview, fingerprint} ->
        {:reply, %{ok: true, review_confirmation_fingerprint: fingerprint},
         assign_import_attempt(socket, attempt, preview)}

      {:error, reason} ->
        {:reply, %{ok: false, reason: import_review_failure(reason)},
         reconcile_failed_import_mutation(socket, attempt_id, &Function.identity/1)}
    end
  end

  defp validate_import_review(socket, _state, _acknowledged?, _decisions) do
    {:reply, %{ok: false, reason: "stale"}, socket}
  end

  defp import_review_failure(reason)
       when reason in [
              :import_review_required,
              :invalid_import_review,
              :invalid_import_review_selection,
              :import_review_too_large
            ], do: "invalid"

  defp import_review_failure(reason) when reason in [:not_found, :import_not_ready, :stale_import_review], do: "stale"

  defp import_review_failure(:unauthorized), do: "unauthorized"
  defp import_review_failure(_reason), do: "unavailable"

  defp apply_prepare_result(socket, {:ok, attempt, preview}), do: assign_import_attempt(socket, attempt, preview)

  defp apply_prepare_result(socket, {:error, reason}), do: assign_import_error(socket, reason)
  defp apply_prepare_result(socket, nil), do: assign_import_error(socket, :upload_unavailable)

  defp serialize_preview(preview) do
    %{
      counts: stringify_map_keys(preview.counts),
      conflicts: stringify_conflicts(preview.conflicts),
      has_conflicts: preview.has_conflicts,
      import_review: serialize_import_review(Map.get(preview, :import_review)),
      import_review_draft: serialize_import_review_state(Map.get(preview, :import_review_draft)),
      import_review_resolution: serialize_import_review_state(Map.get(preview, :import_review_resolution)),
      issue_summary: serialize_issue_summary(Map.get(preview, :issue_summary))
    }
  end

  defp stringify_map_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_conflicts(conflicts) do
    Map.new(conflicts, fn {key, values} -> {to_string(key), values} end)
  end

  defp serialize_import_review(review) when is_map(review) and map_size(review) > 0, do: review
  defp serialize_import_review(_review), do: nil

  defp serialize_import_review_state(state) when is_map(state) and map_size(state) > 0, do: state

  defp serialize_import_review_state(_state), do: nil

  defp serialize_issue_summary(summary) when is_map(summary) do
    %{
      warning_count: Map.get(summary, :warning_count, 0),
      error_count: Map.get(summary, :error_count, 0),
      issue_count: Map.get(summary, :issue_count, 0),
      issues_truncated: Map.get(summary, :issues_truncated, false),
      counts_by_code: Map.get(summary, :counts_by_code, %{})
    }
  end

  defp serialize_issue_summary(_summary), do: nil

  defp recover_latest_import(%{assigns: %{can_import: true}} = socket) do
    case Projects.resume_latest_active_project_import(
           socket.assigns.current_scope,
           socket.assigns.project,
           wake_queue: true
         ) do
      {:ok, %{id: _id} = attempt, preview} ->
        assign_import_attempt(socket, attempt, preview)

      {:ok, nil} ->
        socket

      {:error, reason, %{id: _id} = attempt} ->
        # The durable attempt exists but its preview could not be rebuilt.
        # An in-panel error keeps the attempt id on screen, so Reset can
        # terminalize it — a flash over an empty uploader left the user with
        # no way to clear the attempt, resurfacing the failure every mount.
        assign(socket, :import_state, %{
          step: "error",
          stage: attempt.stage,
          attempt_id: attempt.id,
          preview: nil,
          error:
            dgettext(
              "projects",
              "Your previous import could not be restored. Reset it and upload the file again."
            ),
          error_code: import_error_code(reason),
          conflict_strategy: attempt.conflict_strategy || "rename",
          import_mode: attempt.import_mode || "additive",
          replace_eligible: attempt.replace_eligible == true,
          recovery_snapshot_url: recovery_snapshot_url(socket, attempt),
          warning_codes: attempt.warning_codes || [],
          status: attempt.status
        })

      {:error, _reason} ->
        socket
    end
  end

  defp recover_latest_import(socket), do: socket

  defp assign_import_attempt(socket, attempt, resumed_preview \\ nil) do
    step =
      case attempt.status do
        "ready" -> "preview"
        status when status in ["queued", "running", "retrying"] -> "queued"
        "completed" -> "done"
        _status -> "error"
      end

    preview = import_attempt_preview(socket.assigns.import_state, attempt, step, resumed_preview)

    state = %{
      step: step,
      stage: attempt.stage,
      attempt_id: attempt.id,
      preview: preview,
      error: if(step == "error", do: import_attempt_error(attempt)),
      error_code: attempt.error_code,
      conflict_strategy: attempt.conflict_strategy || "rename",
      import_mode: attempt.import_mode || "additive",
      replace_eligible: attempt.replace_eligible == true,
      recovery_snapshot_url: recovery_snapshot_url(socket, attempt),
      warning_codes: attempt.warning_codes || [],
      status: attempt.status
    }

    assign(socket, :import_state, state)
  end

  defp recovery_snapshot_url(socket, %{
         status: status,
         import_mode: "replace_project",
         pre_import_snapshot_id: snapshot_id,
         snapshot_reference_bound_at: %DateTime{},
         snapshot_lifecycle_generation: lifecycle_generation,
         snapshot_capture_digest: capture_digest
       })
       when status in ["completed", "failed", "expired"] and is_integer(snapshot_id) and snapshot_id > 0 and
              is_integer(lifecycle_generation) and lifecycle_generation > 0 and is_binary(capture_digest) do
    base =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/settings/snapshots"

    "#{base}#snapshot-#{snapshot_id}"
  end

  defp recovery_snapshot_url(_socket, %{id: _id}), do: nil

  defp import_attempt_preview(_state, attempt, "done", _resumed_preview) do
    %{
      counts: stringify_map_keys(attempt.counts || %{}),
      conflicts: %{},
      has_conflicts: false
    }
  end

  defp import_attempt_preview(_state, _attempt, _step, resumed_preview) when not is_nil(resumed_preview),
    do: serialize_preview(resumed_preview)

  defp import_attempt_preview(%{attempt_id: attempt_id, preview: preview}, %{id: attempt_id}, _step, _resumed_preview)
       when not is_nil(preview), do: preview

  defp import_attempt_preview(_state, attempt, _step, _resumed_preview) do
    %{
      counts: stringify_map_keys(attempt.counts || %{}),
      conflicts: %{},
      has_conflicts: false
    }
  end

  defp reconcile_import_attempt(socket, attempt_id, opts \\ []) do
    protect_active? = Keyword.get(opts, :protect_active, false)
    resume_opts = Keyword.delete(opts, :protect_active)

    with :ok <- Authorize.authorize(socket, :manage_project),
         {:ok, attempt, preview} <-
           Projects.resume_project_import(
             socket.assigns.current_scope,
             socket.assigns.project,
             attempt_id,
             resume_opts
           ) do
      case protect_active_import(socket, attempt, protect_active?) do
        {:preserve, protected_socket} ->
          {:reply, %{ok: false, reason: "superseded"}, protected_socket}

        {:replace, replace_socket} ->
          replace_reconciled_import(replace_socket, attempt, preview, protect_active?)
      end
    else
      {:error, reason} ->
        reconcile_import_failure(socket, attempt_id, reason)

      _reason ->
        reconcile_import_failure(socket, attempt_id, :unavailable)
    end
  end

  defp replace_reconciled_import(socket, attempt, preview, protect_active?) do
    socket = assign_import_attempt(socket, attempt, preview)

    socket =
      if protect_active? do
        socket
      else
        maybe_recover_active_after_terminal(socket, attempt)
      end

    {:reply, %{ok: true, status: socket.assigns.import_state.status}, socket}
  end

  # Browser references may outlive their attempt. A newer terminal reference
  # must not replace an older import that is still writing merely because its
  # numeric id sorts later. Re-read the displayed row: the socket can lag a
  # worker transition, while the durable status is authoritative.
  defp protect_active_import(socket, _requested_attempt, false), do: {:replace, socket}

  defp protect_active_import(socket, requested_attempt, true) do
    active_statuses = Projects.project_import_active_statuses()

    if requested_attempt.status in active_statuses do
      {:replace, socket}
    else
      socket = recover_visible_active_import(socket, requested_attempt.id)

      case socket.assigns.import_state do
        %{attempt_id: current_id, status: status}
        when is_integer(current_id) and current_id != requested_attempt.id and
               status in ["ready", "queued", "running", "retrying"] ->
          {:preserve, socket}

        _not_active ->
          {:replace, socket}
      end
    end
  end

  defp recover_visible_active_import(socket, requested_attempt_id) do
    current_attempt_id = socket.assigns.import_state.attempt_id

    socket =
      if is_integer(current_attempt_id) and current_attempt_id != requested_attempt_id do
        case load_project_import_attempt(socket, current_attempt_id) do
          {:ok, attempt} -> assign_import_attempt(socket, attempt)
          :unavailable -> socket
        end
      else
        socket
      end

    case socket.assigns.import_state do
      %{attempt_id: current_id, status: status}
      when is_integer(current_id) and current_id != requested_attempt_id and
             status in ["ready", "queued", "running", "retrying"] ->
        socket

      _not_active ->
        recover_latest_import(socket)
    end
  end

  defp maybe_recover_active_after_terminal(socket, attempt) do
    if attempt.status in Projects.project_import_active_statuses(), do: socket, else: recover_latest_import(socket)
  end

  defp reconcile_import_failure(socket, attempt_id, reason) do
    failure = import_resume_failure(reason)

    socket =
      if failure in ["invalid", "not_found", "unauthorized"] and
           socket.assigns.import_state.attempt_id == attempt_id do
        assign(socket, :import_state, empty_import_state())
      else
        socket
      end

    {:reply, %{ok: false, reason: failure}, socket}
  end

  defp import_resume_failure(reason)
       when reason in [:not_found, :import_not_found, :attempt_not_found, :project_mismatch], do: "not_found"

  defp import_resume_failure(reason) when reason in [:unauthorized, :forbidden], do: "unauthorized"
  defp import_resume_failure(:invalid_attempt_id), do: "invalid"
  defp import_resume_failure(_reason), do: "unavailable"

  defp assign_import_error(socket, reason, status \\ "failed") do
    state = %{
      socket.assigns.import_state
      | step: "error",
        error: import_error_message(reason),
        error_code: import_error_code(reason),
        status: status
    }

    assign(socket, :import_state, state)
  end

  defp assign_import_preview_error(socket, reason) do
    state = %{
      socket.assigns.import_state
      | step: "preview",
        error: nil,
        error_code: import_error_code(reason)
    }

    assign(socket, :import_state, state)
  end

  # The payload identity records what the user actually dismissed. Honor that
  # exact cancellation even if a preceding cross-tab resume event changed this
  # socket before the click reached the server. The context reauthorizes and
  # locks the row; success clears the panel only when it still displays the
  # same id, so a delayed reset cannot erase a newer attempt.
  defp cancel_import_attempt(socket, attempt_id) do
    case load_project_import_attempt(socket, attempt_id) do
      {:ok, _attempt} ->
        cancellation_outcome(Projects.cancel_project_import(socket.assigns.current_scope, attempt_id))

      :unavailable ->
        # Missing, unauthorized and cross-project ids remain indistinguishable.
        # There is nothing in this LiveView's project that may be dismissed.
        :ok
    end
  end

  # A cancellation that lost the race to the worker must keep the attempt on
  # screen. A vanished attempt is genuinely nothing to keep — clearing is
  # right. Every other failure means the attempt (and possibly its queued
  # job) is still live, so reporting success would drop the durable browser
  # reference while the import goes on to materialize.
  defp cancellation_outcome({:error, :import_not_cancellable}), do: {:error, :import_not_cancellable}
  defp cancellation_outcome({:ok, _expired}), do: :ok
  defp cancellation_outcome({:error, :not_found}), do: :ok
  defp cancellation_outcome(_failure), do: {:error, :reset_failed}

  # Three different things terminalize an attempt as `expired`, and the durable
  # row carries no message for any of them. Reporting all three as "the import
  # could not be completed" told a user whose preview simply aged out overnight
  # that their import had failed.
  defp import_attempt_error(%{status: "expired"} = attempt) do
    expired_import_message(attempt.error_code)
  end

  defp import_attempt_error(%{error_code: "project_already_has_main_flow"}) do
    dgettext(
      "projects",
      "This project already has a main flow, so the imported one could not be created. No project content was changed."
    )
  end

  defp import_attempt_error(%{error_code: code}) when code in ["duplicate_yarn_node_title", "import_plan_has_errors"] do
    import_error_message(:import_plan_has_errors)
  end

  defp import_attempt_error(%{error_code: code})
       when code in [
              "archive_entry_too_large",
              "archive_expansion_ratio_exceeded",
              "archive_missing_yarn_files",
              "archive_too_large",
              "archive_too_many_entries",
              "duplicate_archive_entry",
              "file_too_large",
              "invalid_archive",
              "invalid_archive_path",
              "invalid_json",
              "invalid_json_structure",
              "invalid_text_encoding",
              "nested_archive_not_allowed",
              "unsupported_archive_entry",
              "unsupported_import_format",
              "yarn_document_limit_exceeded",
              "yarn_statement_limit_exceeded"
            ] do
    import_error_message(:invalid_archive)
  end

  defp import_attempt_error(_attempt), do: generic_import_error()

  defp import_error_code(reason) when is_atom(reason), do: to_string(reason)
  defp import_error_code(reason) when is_binary(reason), do: reason
  defp import_error_code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp import_error_code({reason, _one, _two}) when is_atom(reason), do: to_string(reason)
  defp import_error_code(_reason), do: "unexpected_import_error"

  defp expired_import_message("import_cancelled") do
    dgettext("projects", "The import was cancelled. No project content was changed.")
  end

  defp expired_import_message("import_expired") do
    dgettext(
      "projects",
      "The import could not run before its retention deadline. No project content was changed."
    )
  end

  defp expired_import_message(code) when is_binary(code) do
    dgettext(
      "projects",
      "This import could not be validated and was discarded. Validate the file again before importing."
    )
  end

  defp expired_import_message(_no_code) do
    dgettext(
      "projects",
      "This import preview expired before the import was started. Upload the file again."
    )
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
              :invalid_json,
              :invalid_json_structure,
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

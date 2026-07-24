defmodule StoryarnWeb.FlowLive.Handlers.AnalysisHandlers do
  @moduledoc """
  Event handlers for the structural-analysis panel.

  The snapshot lifecycle is explicit: opening the panel or rerunning computes
  a fresh canonical analysis; relevant flow mutations mark the open snapshot
  stale (see `SocketHelpers.assign_flow_stats/3`) and the panel offers rerun
  instead of silently merging old dispositions with new evidence.

  The client only ever selects server-computed ids (`finding_id`,
  `dismissal_id`); finding content, evidence, rule metadata, and project ids
  always derive from the authorized socket state.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Analytics
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Shared.TimeHelpers
  alias StoryarnWeb.Helpers.Authorize

  @type result :: {:noreply, Socket.t()}

  # Client-supplied ids above the PostgreSQL bigint range would raise on
  # parameter encoding instead of failing closed (same guard as Hooks.Palette).
  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_database_id(value) when is_integer(value) and value > 0 and value <= @max_pg_bigint

  # ===========================================================================
  # Panel lifecycle
  # ===========================================================================

  @spec handle_open_analysis_panel(map(), Socket.t()) :: result()
  def handle_open_analysis_panel(_params, socket) do
    {:noreply,
     socket
     |> assign(:analysis_panel_open, true)
     |> compute_snapshot("open")}
  end

  @spec handle_close_analysis_panel(map(), Socket.t()) :: result()
  def handle_close_analysis_panel(_params, socket) do
    {:noreply, assign(socket, :analysis_panel_open, false)}
  end

  @spec handle_rerun_analysis(map(), Socket.t()) :: result()
  def handle_rerun_analysis(_params, socket) do
    {:noreply, compute_snapshot(socket, "rerun")}
  end

  # ===========================================================================
  # Dispositions
  # ===========================================================================

  @spec handle_dismiss_finding(map(), Socket.t()) :: result()
  def handle_dismiss_finding(%{"finding_id" => _} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      cond do
        # Never record a disposition against evidence the user is no longer
        # looking at — a stale snapshot must be rerun first, otherwise the
        # dismissal row would match no future occurrence and become invisible.
        match?(%{stale: true}, socket.assigns[:analysis_snapshot]) ->
          {:noreply, stale_snapshot_flash(socket)}

        finding = find_current_finding(socket, params["finding_id"]) ->
          dismiss_current_finding(socket, finding, params)

        true ->
          {:noreply, stale_selection_flash(socket)}
      end
    end)
  end

  # Hostile non-map payloads (a JSON array is valid over the wire) must fail
  # closed instead of crashing on params["..."].
  def handle_dismiss_finding(_params, socket) do
    {:noreply, stale_selection_flash(socket)}
  end

  @spec handle_restore_finding_dismissal(map(), Socket.t()) :: result()
  def handle_restore_finding_dismissal(%{"dismissal_id" => dismissal_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case dismissal_id do
        id when valid_database_id(id) -> restore_by_id(socket, id)
        _invalid -> {:noreply, stale_selection_flash(socket)}
      end
    end)
  end

  def handle_restore_finding_dismissal(_params, socket) do
    {:noreply, stale_selection_flash(socket)}
  end

  defp restore_by_id(socket, dismissal_id) do
    flow = socket.assigns.flow

    case Flows.restore_finding_dismissal(flow, dismissal_id, socket.assigns.current_scope.user.id) do
      {:ok, dismissal} ->
        track(socket, "flow analysis finding restored", %{
          rule_id: dismissal.rule_id,
          rule_version: dismissal.rule_version,
          reason_code: dismissal.reason_code
        })

        broadcast_disposition_change(socket)
        {:noreply, compute_snapshot(socket, "after_restore")}

      {:error, :not_found} ->
        {:noreply, stale_selection_flash(socket)}
    end
  end

  # ===========================================================================
  # Evidence navigation
  # ===========================================================================

  @doc """
  Navigates the canvas to a finding's evidence. The target is validated
  against the authorized current flow; deleted or foreign evidence is shown
  as stale and never navigated.
  """
  @spec handle_navigate_evidence(map(), Socket.t()) :: result()
  def handle_navigate_evidence(%{"type" => "flow_node", "id" => id}, socket) when valid_database_id(id) do
    flow = socket.assigns.flow

    if graph_loaded?(flow) and Enum.any?(flow.nodes, &(&1.id == id)) do
      track(socket, "flow analysis evidence navigated", %{evidence_type: "flow_node"})
      {:noreply, Phoenix.LiveView.push_event(socket, "navigate_to_node", %{node_db_id: id})}
    else
      {:noreply, missing_evidence_flash(socket)}
    end
  end

  def handle_navigate_evidence(%{"type" => "flow_connection", "id" => id}, socket) when valid_database_id(id) do
    flow = socket.assigns.flow

    connection = if graph_loaded?(flow), do: find_live_connection(flow, id)

    case connection do
      nil ->
        {:noreply, missing_evidence_flash(socket)}

      conn ->
        track(socket, "flow analysis evidence navigated", %{evidence_type: "flow_connection"})

        {:noreply,
         Phoenix.LiveView.push_event(socket, "navigate_to_connection", %{
           source_node_id: conn.source_node_id,
           source_pin: conn.source_pin,
           target_node_id: conn.target_node_id,
           target_pin: conn.target_pin
         })}
    end
  end

  def handle_navigate_evidence(_params, socket) do
    {:noreply, missing_evidence_flash(socket)}
  end

  # The fully-preloaded flow only arrives after the async load; a navigate
  # event racing that window must fail closed, not crash on NotLoaded.
  defp graph_loaded?(flow) do
    Ecto.assoc_loaded?(flow.nodes) and Ecto.assoc_loaded?(flow.connections)
  end

  defp find_live_connection(flow, connection_id) do
    active_node_ids = MapSet.new(flow.nodes, & &1.id)

    Enum.find(flow.connections, fn conn ->
      conn.id == connection_id and MapSet.member?(active_node_ids, conn.source_node_id) and
        MapSet.member?(active_node_ids, conn.target_node_id)
    end)
  end

  # ===========================================================================
  # Snapshot state (used by show.ex and SocketHelpers)
  # ===========================================================================

  @doc "Initial assigns for the analysis panel."
  @spec assign_initial_state(Socket.t()) :: Socket.t()
  def assign_initial_state(socket) do
    socket
    |> assign(:analysis_panel_open, false)
    |> assign(:analysis_snapshot, nil)
  end

  @doc "Keeps an already-open panel across the async flow load (fresh snapshot)."
  @spec recompute_open_snapshot(Socket.t()) :: Socket.t()
  def recompute_open_snapshot(socket) do
    socket
    |> assign(:analysis_panel_open, true)
    |> compute_snapshot("refresh")
  end

  @doc """
  Whether the current flow has a subflow/exit node referencing `flow_id`
  (in-memory check — used to scope cross-flow stale marking).
  """
  @spec references_flow?(Socket.t(), integer()) :: boolean()
  def references_flow?(socket, flow_id) do
    flow = socket.assigns[:flow]

    flow != nil and Ecto.assoc_loaded?(flow.nodes) and
      Enum.any?(flow.nodes, fn node ->
        node.type in ~w(subflow exit) and
          Storyarn.Shared.MapUtils.parse_int((node.data || %{})["referenced_flow_id"]) == flow_id
      end)
  end

  @doc "Badge counts for the given ACTIVE findings (dismissals already subtracted)."
  @spec structural_summary([struct()]) :: map()
  def structural_summary(active_findings) do
    %{
      errorCount: Enum.count(active_findings, &(&1.severity == :error)),
      warningCount: Enum.count(active_findings, &(&1.severity == :warning))
    }
  end

  @doc """
  Re-splits the current snapshot (and badge) against fresh dismissals after a
  local or remote disposition change. The analysis itself did not change, so
  this never recomputes findings and never marks the snapshot stale.
  """
  @spec refresh_dispositions(Socket.t()) :: Socket.t()
  def refresh_dispositions(socket) do
    flow = socket.assigns.flow
    dismissals = Flows.list_active_finding_dismissals(flow)

    case socket.assigns[:analysis_snapshot] do
      %{findings: findings} = snapshot ->
        {active, dismissed} = Flows.split_findings(findings, dismissals)

        socket
        |> assign(:analysis_snapshot, %{
          snapshot
          | active: active,
            dismissed: dismissed,
            orphaned: orphaned_by_key(dismissals, dismissed)
        })
        |> assign(:flow_structural_summary, structural_summary(active))

      _no_snapshot ->
        refresh_badge_only(socket, flow, dismissals)
    end
  end

  defp refresh_badge_only(socket, flow, dismissals) do
    case socket.assigns[:flow_data] do
      nil ->
        socket

      flow_data ->
        analysis = Flows.analyze_serialized_flow_structure(flow_data, flow.project_id)
        {active, _dismissed} = Flows.split_findings(analysis.findings, dismissals)
        assign(socket, :flow_structural_summary, structural_summary(active))
    end
  end

  @doc """
  Marks the current snapshot stale after a relevant flow mutation. Never
  recomputes — the user chooses when to rerun.
  """
  @spec mark_snapshot_stale(Socket.t()) :: Socket.t()
  def mark_snapshot_stale(socket) do
    case socket.assigns[:analysis_snapshot] do
      %{stale: false} = snapshot -> assign(socket, :analysis_snapshot, %{snapshot | stale: true})
      _absent_or_stale -> socket
    end
  end

  @doc "Serializes the panel props (camelCase, primitives only)."
  @spec panel_props(map()) :: map()
  def panel_props(assigns) do
    snapshot = assigns[:analysis_snapshot]

    %{
      open: assigns[:analysis_panel_open] || false,
      canEdit: assigns.can_edit,
      stale: (snapshot && snapshot.stale) || false,
      computedAt: snapshot && DateTime.to_iso8601(snapshot.computed_at),
      reasonCodes: Flows.finding_dismissal_reason_codes(),
      maxNoteLength: Flows.finding_dismissal_max_note_length(),
      active: (snapshot && Enum.map(snapshot.active, &finding_props(&1, snapshot.orphaned))) || [],
      dismissed: (snapshot && Enum.map(snapshot.dismissed, &dismissed_finding_props/1)) || []
    }
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp compute_snapshot(socket, source) do
    flow = socket.assigns.flow
    started_at = System.monotonic_time()
    was_stale = match?(%{stale: true}, socket.assigns[:analysis_snapshot])

    case Flows.analyze_flow_structure(flow.project_id, flow.id) do
      {:ok, analysis} ->
        dismissals = Flows.list_active_finding_dismissals(flow)
        {active, dismissed} = Flows.split_findings(analysis.findings, dismissals)

        track(socket, "flow analysis run", %{
          source: source,
          stale: was_stale,
          finding_count: length(active),
          dismissed_count: length(dismissed),
          error_count: Enum.count(active, &(&1.severity == :error)),
          warning_count: Enum.count(active, &(&1.severity == :warning)),
          duration_bucket: duration_bucket(started_at)
        })

        socket
        |> assign(:analysis_snapshot, %{
          findings: analysis.findings,
          active: active,
          dismissed: dismissed,
          orphaned: orphaned_by_key(dismissals, dismissed),
          stale: false,
          computed_at: TimeHelpers.now()
        })
        |> assign(:flow_structural_summary, structural_summary(active))

      {:error, :not_found} ->
        socket
        |> assign(:analysis_snapshot, nil)
        |> put_flash(:error, dgettext("flows", "Flow is no longer available"))
    end
  end

  # Active dismissal rows whose exact occurrence no longer matches any
  # current finding, keyed by finding_key — surfaced as a "previously
  # dismissed" hint when the same finding_key reactivates with new evidence.
  defp orphaned_by_key(dismissals, dismissed_pairs) do
    matched_ids = MapSet.new(dismissed_pairs, fn {_finding, dismissal} -> dismissal.id end)

    dismissals
    |> Enum.reject(&MapSet.member?(matched_ids, &1.id))
    |> Map.new(&{&1.finding_key, &1})
  end

  defp track(socket, event, properties) do
    Analytics.track(socket.assigns.current_scope, event, properties)
  end

  defp duration_bucket(started_at) do
    milliseconds = System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    cond do
      milliseconds < 100 -> "under_100ms"
      milliseconds < 500 -> "100ms_to_500ms"
      milliseconds < 2_000 -> "500ms_to_2s"
      true -> "over_2s"
    end
  end

  defp dismiss_current_finding(socket, finding, params) do
    attrs = %{
      reason_code: params["reason_code"],
      note: params["note"],
      dismissed_by_id: socket.assigns.current_scope.user.id
    }

    case Flows.dismiss_finding(socket.assigns.flow, finding, attrs) do
      {:ok, dismissal} ->
        track(socket, "flow analysis finding dismissed", %{
          rule_id: finding.rule_id,
          rule_version: finding.rule_version,
          category: to_string(finding.category),
          severity: to_string(finding.severity),
          reason_code: dismissal.reason_code
        })

        broadcast_disposition_change(socket)
        {:noreply, compute_snapshot(socket, "after_dismiss")}

      {:error, changeset} ->
        message =
          Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not dismiss finding: %{reason}", reason: message))}
    end
  end

  defp find_current_finding(_socket, finding_id) when not is_binary(finding_id), do: nil

  defp find_current_finding(socket, finding_id) do
    case socket.assigns[:analysis_snapshot] do
      %{active: active} -> Enum.find(active, &(&1.finding_id == finding_id))
      _no_snapshot -> nil
    end
  end

  # Dispositions are project-shared: other connected editors re-split their
  # snapshot and badge (never a stale mark — the analysis did not change).
  defp broadcast_disposition_change(socket) do
    Collaboration.broadcast_change_from(
      self(),
      {:flow, socket.assigns.flow.id},
      :finding_disposition_changed,
      %{}
    )
  end

  # The SNAPSHOT is outdated (the finding may still be perfectly current) —
  # distinct copy from a genuinely vanished finding id.
  defp stale_snapshot_flash(socket) do
    put_flash(
      socket,
      :error,
      dgettext("flows", "The flow changed since this analysis — rerun before dismissing.")
    )
  end

  defp stale_selection_flash(socket) do
    put_flash(
      socket,
      :error,
      dgettext("flows", "This finding is no longer current. Rerun the analysis.")
    )
  end

  defp missing_evidence_flash(socket) do
    put_flash(
      socket,
      :error,
      dgettext("flows", "This evidence is no longer available. Rerun the analysis.")
    )
  end

  defp finding_props(finding, orphaned \\ %{}) do
    previous =
      case Map.get(orphaned, finding.finding_key) do
        nil ->
          nil

        dismissal ->
          %{
            reasonCode: dismissal.reason_code,
            dismissedBy: dismissal.dismissed_by && dismissal.dismissed_by.email,
            dismissedAt: dismissal.inserted_at && DateTime.to_iso8601(dismissal.inserted_at)
          }
      end

    %{
      previousDismissal: previous,
      findingId: finding.finding_id,
      ruleId: finding.rule_id,
      ruleVersion: finding.rule_version,
      category: to_string(finding.category),
      severity: to_string(finding.severity),
      targetType: to_string(finding.target.type),
      targetId: finding.target.id,
      nodeType: finding.details[:node_type],
      limitationsKey: Flows.structural_rule_limitations_key(finding.rule_id),
      pins: finding.details[:pins] || [],
      count: finding.details[:count],
      hubId: finding.details[:hub_id],
      evidence: Enum.map(finding.evidence, &%{type: &1.type, id: &1.id})
    }
  end

  defp dismissed_finding_props({finding, dismissal}) do
    finding
    |> finding_props()
    |> Map.merge(%{
      dismissalId: dismissal.id,
      reasonCode: dismissal.reason_code,
      note: dismissal.note,
      dismissedBy: dismissal.dismissed_by && dismissal.dismissed_by.email,
      dismissedAt: dismissal.inserted_at && DateTime.to_iso8601(dismissal.inserted_at)
    })
  end
end

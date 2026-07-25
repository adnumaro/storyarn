defmodule StoryarnWeb.FlowLive.Handlers.ExplanationHandlers do
  @moduledoc """
  Panel lifecycle for the optional AI explanation of ONE structural finding.

  The client only ever selects a server-computed `finding_id` and one issued
  route reference. Everything else — the finding, its evidence, the prompt, the
  payer, the price — is resolved server-side from the authorized snapshot.

  Opening the surface creates no operation: preflight resolves routes and the
  Slice-6 disclosure without calling a provider, and an operation exists only
  after the actor picks a route. The kernel emits no completion event, so the
  panel polls its own operation while it is open and stops as soon as the
  operation settles or the panel closes.

  The generated narrative is a temporary, actor-private preview: it is never
  written into the flow, never turned into a finding, and never survives its
  TTL.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.AI
  alias Storyarn.AI.Tasks.FlowFindingExplanation
  alias Storyarn.Analytics
  alias Storyarn.FeatureFlags
  alias Storyarn.Projects

  @type result :: {:noreply, Socket.t()}

  @poll_interval_ms 1_000
  # Measured from the moment the operation starts EXECUTING, never from execute:
  # queue wait is unbounded by design (`:ai` concurrency 2, shared with the
  # maintenance workers), so counting it made the deadline fire on operations
  # that had not begun. Comfortably past the 60s provider timeout plus the
  # ~37-39s Oban retry ladder, which is the kernel's real worst case — a
  # provider timeout is terminal and never consumes an attempt. See
  # docs/features/ai-platform/OBAN_AI_QUEUE_HARDENING.md.
  @poll_deadline_ms 180_000
  @locales ~w(en es)
  # Statuses the panel stops polling on. "queued" and "running" are the two it
  # keeps watching.
  @terminal_statuses ~w(succeeded failed unknown cancelled)
  @watched_statuses [:queued, :running]
  @timer_key :explanation_poll_timer

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @doc """
  Initial assigns for the explanation surface.

  Also releases an operation nobody is left to read — this runs on close and on
  every flow reload, and an abandoned managed operation would still bill.
  """
  @spec assign_initial_state(Socket.t()) :: Socket.t()
  def assign_initial_state(socket) do
    socket
    |> cancel_watched_operation()
    |> cancel_poll()
    |> assign(:explanation, nil)
    |> then(&assign(&1, :explanation_available, available?(&1)))
  end

  @doc """
  Drops any explanation state bound to findings that no longer apply.

  Called whenever the analysis snapshot is recomputed or marked stale: an
  explanation belongs to one exact occurrence, so it must not outlive it.
  """
  @spec reset_for_new_snapshot(Socket.t()) :: Socket.t()
  def reset_for_new_snapshot(socket) do
    case socket.assigns[:explanation] do
      nil -> socket
      _explanation -> assign_initial_state(socket)
    end
  end

  @doc "Whether this actor may see the explanation surface at all."
  @spec available?(Socket.t()) :: boolean()
  def available?(socket) do
    user = socket.assigns.current_scope.user

    # An operationally DISABLED task still shows the surface: the slice asks for
    # an honest blocked state rather than a command that silently disappears.
    # Only an unregistered task (a deployment without it) hides it.
    FeatureFlags.enabled?(:ai_integrations, for: user) and
      role_can_use_ai?(socket) and
      match?({:ok, _task}, AI.get_task(FlowFindingExplanation.task_id()))
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @spec handle_open_explanation(map(), Socket.t()) :: result()
  def handle_open_explanation(%{"finding_id" => finding_id}, socket) when is_binary(finding_id) do
    with true <- available?(socket) || {:error, :unavailable},
         {:ok, finding} <- current_finding(socket.assigns, finding_id) do
      preflight(socket, finding, 0)
    else
      {:error, reason} -> {:noreply, refused(socket, reason)}
    end
  end

  def handle_open_explanation(_params, socket), do: {:noreply, refused(socket, :stale_selection)}

  @doc """
  Closes the surface, releasing any operation the actor stops waiting for.

  An abandoned managed operation would still settle and bill a unit nobody ever
  reads, so dropping the surface cancels it.
  """
  @spec handle_close_explanation(map(), Socket.t()) :: result()
  def handle_close_explanation(_params, socket), do: {:noreply, assign_initial_state(socket)}

  @doc """
  Explicitly buys a fresh explanation of the same finding.

  Raising `attempt` is the ONLY way to a second charge: without it the
  deterministic idempotency key replays the operation this actor already paid
  for.
  """
  @spec handle_rerun_explanation(map(), Socket.t()) :: result()
  def handle_rerun_explanation(_params, socket) do
    with %{finding_id: finding_id, attempt: attempt} <- socket.assigns[:explanation],
         true <- available?(socket) || {:error, :unavailable},
         {:ok, finding} <- current_finding(socket.assigns, finding_id) do
      preflight(socket, finding, attempt + 1)
    else
      {:error, reason} -> {:noreply, refused(socket, reason)}
      _absent -> {:noreply, refused(socket, :stale_selection)}
    end
  end

  @doc """
  Resumes watching an operation the panel stopped polling at the deadline.

  Creates nothing and buys nothing: the operation was still executing, so this
  only re-arms the poll against the id the panel already holds.
  """
  @spec handle_resume_explanation(map(), Socket.t()) :: result()
  def handle_resume_explanation(_params, socket) do
    case socket.assigns[:explanation] do
      %{status: :detached, operation_id: operation_id} = explanation when is_integer(operation_id) ->
        socket
        |> assign(:explanation, %{
          explanation
          | status: :running,
            error: nil,
            polling_since: System.monotonic_time(:millisecond)
        })
        |> schedule_poll()
        |> then(&{:noreply, &1})

      _absent ->
        {:noreply, refused(socket, :stale_selection)}
    end
  end

  @doc """
  Creates the operation for one explicitly chosen route.

  The reference must be one this preflight issued: a client-supplied reference
  for a route the actor never saw is refused before the kernel is asked.
  """
  @spec handle_execute_explanation(map(), Socket.t()) :: result()
  def handle_execute_explanation(%{"route_ref" => route_ref}, socket) when is_binary(route_ref) do
    with true <- available?(socket) || {:error, :unavailable},
         %{status: :preflight, routes: routes} = explanation <- socket.assigns[:explanation],
         true <- Enum.any?(routes, &(&1.requested_route_ref == route_ref)),
         {:ok, finding} <- current_finding(socket.assigns, explanation.finding_id) do
      execute(socket, explanation, finding, route_ref)
    else
      {:error, reason} -> {:noreply, refused(socket, reason)}
      _invalid -> {:noreply, refused(socket, :stale_selection)}
    end
  end

  def handle_execute_explanation(_params, socket), do: {:noreply, refused(socket, :stale_selection)}

  @doc "Internal poll tick — the kernel broadcasts nothing when an operation settles."
  @spec handle_poll(Socket.t()) :: result()
  def handle_poll(socket) do
    case socket.assigns[:explanation] do
      %{status: status, operation_id: operation_id} = explanation when status in @watched_statuses ->
        if poll_expired?(explanation) do
          {:noreply, detached(socket, explanation)}
        else
          {:noreply, poll_operation(socket, explanation, operation_id)}
        end

      _settled_or_absent ->
        {:noreply, cancel_poll(socket)}
    end
  end

  # ===========================================================================
  # Preflight
  # ===========================================================================

  defp preflight(socket, finding, attempt) do
    # Any operation still in flight belongs to the previous run and nobody will
    # read it: release it before its state map (and timer) is replaced.
    socket = socket |> cancel_watched_operation() |> cancel_poll()

    with {:ok, intent} <- build_intent(socket, finding, %{}),
         {:ok, preflight} <- AI.preflight(intent) do
      track(socket, "flow explanation preflight shown", %{
        rule_id: finding.rule_id,
        rule_version: finding.rule_version,
        route_count: length(preflight.route_options),
        blocked: blocked_reason(preflight) != nil
      })

      {:noreply,
       assign(socket, :explanation, %{
         status: :preflight,
         finding_id: finding.finding_id,
         finding_key: finding.finding_key,
         rule_id: finding.rule_id,
         attempt: attempt,
         routes: preflight.route_options,
         blocked_lanes: preflight.blocked_lanes,
         disclosure: preflight.context_disclosure,
         operation_id: nil,
         result: nil,
         error: nil,
         polling_since: nil
       })}
    else
      {:error, reason} -> {:noreply, blocked(socket, finding, attempt, reason)}
    end
  end

  defp build_intent(socket, finding, overrides) do
    %{flow: flow, project: project, current_scope: scope} = socket.assigns

    AI.new_intent(
      scope,
      Map.merge(
        %{
          workspace_id: project.workspace_id,
          project_id: project.id,
          task_id: FlowFindingExplanation.task_id(),
          input: FlowFindingExplanation.input(finding, locale(socket)),
          subject: FlowFindingExplanation.subject(flow.id, finding)
        },
        overrides
      )
    )
  end

  # ===========================================================================
  # Execution
  # ===========================================================================

  defp execute(socket, explanation, finding, route_ref) do
    lane = lane_for_ref(explanation, route_ref)

    track(socket, "flow explanation route selected", %{lane: to_string(lane)})

    overrides = %{
      requested_route_ref: route_ref,
      idempotency_key:
        FlowFindingExplanation.idempotency_key(
          socket.assigns.current_scope.user.id,
          finding,
          explanation.attempt
        )
    }

    with {:ok, intent} <- build_intent(socket, finding, overrides),
         {:ok, operation} <- AI.execute(intent) do
      track(socket, "flow explanation execution started", %{
        lane: to_string(lane),
        rule_id: finding.rule_id
      })

      socket
      |> assign(:explanation, %{
        explanation
        | status: :queued,
          operation_id: operation.id,
          polling_since: nil,
          error: nil
      })
      |> schedule_poll()
      |> then(&{:noreply, &1})
    else
      {:error, reason} -> {:noreply, failed(socket, explanation, reason)}
    end
  end

  # ===========================================================================
  # Polling
  # ===========================================================================

  defp poll_operation(socket, explanation, operation_id) do
    scope = socket.assigns.current_scope

    case AI.get_operation(scope, operation_id) do
      %{execution_status: "succeeded"} = operation ->
        load_result(socket, explanation, operation)

      %{execution_status: status} = operation when status in @terminal_statuses ->
        failed(socket, explanation, operation.error_classification || status)

      # The deadline measures EXECUTION, so it only starts once a worker picked
      # the operation up. Queue wait is bounded by capacity, not by this panel.
      %{execution_status: "running"} ->
        socket
        |> assign(:explanation, %{explanation | status: :running, polling_since: started_at(explanation)})
        |> schedule_poll()

      %{execution_status: _queued} ->
        schedule_poll(socket)

      nil ->
        failed(socket, explanation, :operation_not_found)
    end
  end

  defp started_at(%{polling_since: since}) when is_integer(since), do: since
  defp started_at(_explanation), do: System.monotonic_time(:millisecond)

  defp load_result(socket, explanation, operation) do
    scope = socket.assigns.current_scope

    case AI.get_result(scope, operation.id) do
      {:ok, output, _operation} ->
        track(socket, "flow explanation result viewed", %{
          rule_id: explanation.rule_id,
          stale: not finding_current?(socket.assigns, explanation.finding_id)
        })

        socket
        |> cancel_poll()
        |> assign(:explanation, %{explanation | status: :succeeded, result: output})

      # Succeeded but unreadable means the actor-private TTL already elapsed.
      {:error, _reason} ->
        socket
        |> cancel_poll()
        |> assign(:explanation, %{explanation | status: :expired, result: nil})
    end
  end

  defp poll_expired?(%{polling_since: since}) when is_integer(since) do
    System.monotonic_time(:millisecond) - since >= poll_deadline_ms()
  end

  defp poll_expired?(_explanation), do: false

  # Operational knob: a deployment with a slower provider can widen it, and
  # tests can collapse it without waiting three minutes.
  defp poll_deadline_ms do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:poll_deadline_ms, @poll_deadline_ms)
  end

  # The timer reference lives in the process dictionary, NOT in an assign.
  # `show.ex` passes the whole `assigns` to its prop builders, which strong-taints
  # the template: any assign change re-encodes flow_data for the entire canvas
  # (~250 KB at 500 nodes). Re-arming a poll must therefore touch no assign at
  # all, or a silent tick would cost a full editor re-render every second.
  defp schedule_poll(socket) do
    cancel_poll(socket)
    Process.put(@timer_key, Process.send_after(self(), :poll_explanation, @poll_interval_ms))
    socket
  end

  defp cancel_poll(socket) do
    case Process.delete(@timer_key) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      nil -> :ok
    end

    socket
  end

  # ===========================================================================
  # State transitions
  # ===========================================================================

  defp blocked(socket, finding, attempt, reason) do
    assign(socket, :explanation, %{
      status: :blocked,
      finding_id: finding.finding_id,
      finding_key: finding.finding_key,
      rule_id: finding.rule_id,
      attempt: attempt,
      routes: [],
      blocked_lanes: [],
      disclosure: nil,
      operation_id: nil,
      result: nil,
      error: error_class(reason),
      polling_since: nil
    })
  end

  # Stopped WATCHING, not failed. The operation is alive and already paid for,
  # so the surface keeps its id and offers to resume: reporting a failure here
  # would push the actor toward a rerun that buys a second unit for nothing.
  defp detached(socket, explanation) do
    track(socket, "flow explanation detached", %{rule_id: explanation.rule_id})

    socket
    |> cancel_poll()
    |> assign(:explanation, %{explanation | status: :detached})
  end

  # Releases an operation the actor stops waiting for. Best effort: the kernel
  # refuses once it has settled, and a settled operation needs no release.
  defp cancel_watched_operation(socket) do
    case socket.assigns[:explanation] do
      %{status: status, operation_id: operation_id}
      when status in [:queued, :running, :detached] and is_integer(operation_id) ->
        AI.cancel(socket.assigns.current_scope, operation_id)
        socket

      _settled_or_absent ->
        socket
    end
  end

  defp failed(socket, explanation, reason) do
    track(socket, "flow explanation failed", %{error_class: error_class(reason)})

    socket
    |> cancel_poll()
    |> assign(:explanation, %{
      explanation
      | status: :failed,
        error: error_class(reason)
    })
  end

  defp refused(socket, reason) do
    put_flash(socket, :error, refusal_message(reason))
  end

  defp refusal_message(:unavailable), do: dgettext("flows", "AI explanations are not available for your account.")

  defp refusal_message(:stale_snapshot),
    do: dgettext("flows", "The flow changed since this analysis — rerun before explaining.")

  defp refusal_message(_reason), do: dgettext("flows", "This finding is no longer current. Rerun the analysis.")

  # ===========================================================================
  # Panel props
  # ===========================================================================

  @doc "Serializes the explanation surface (camelCase, primitives only)."
  @spec panel_props(map()) :: map()
  def panel_props(assigns), do: props(assigns[:explanation], assigns)

  defp props(nil, assigns) do
    %{
      available: assigns[:explanation_available] || false,
      findingId: nil,
      findingKey: nil,
      status: "idle",
      error: nil,
      stale: false,
      routes: [],
      blockedLanes: [],
      disclosure: nil,
      result: nil
    }
  end

  defp props(explanation, assigns) do
    %{
      available: assigns[:explanation_available] || false,
      findingId: explanation.finding_id,
      findingKey: explanation.finding_key,
      status: to_string(explanation.status),
      error: explanation.error,
      # Revalidated at PRESENTATION time: a result whose finding moved after it
      # was produced is marked obsolete, never silently regenerated.
      stale: not finding_current?(assigns, explanation.finding_id),
      routes: Enum.map(explanation.routes, &route_props/1),
      blockedLanes: Enum.map(explanation.blocked_lanes, &blocked_lane_props/1),
      disclosure: explanation.disclosure,
      result: result_props(explanation.result)
    }
  end

  # The model answers in the task's schema (snake_case); Vue props are
  # camelCase, and the boundary is here — not in the component.
  defp result_props(nil), do: nil

  defp result_props(result) do
    %{
      summary: result["summary"],
      whyItTriggers: result["why_it_triggers"],
      implications: result["implications"] || [],
      suggestedChecks: result["suggested_checks"] || []
    }
  end

  defp blocked_lane_props(%{lane: lane, reason: reason}), do: %{lane: to_string(lane), reason: to_string(reason)}

  defp route_props(route) do
    %{
      routeRef: route.requested_route_ref,
      lane: to_string(route.lane),
      provider: route.provider,
      model: route.model,
      payer: route.payer,
      priceUnits: route.price_units
    }
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  # The client selects an id; the finding itself always comes from the
  # authorized snapshot the user is currently looking at.
  defp current_finding(assigns, finding_id) do
    case assigns[:analysis_snapshot] do
      %{stale: true} ->
        {:error, :stale_snapshot}

      %{active: active} ->
        case Enum.find(active, &(&1.finding_id == finding_id)) do
          nil -> {:error, :stale_selection}
          finding -> {:ok, finding}
        end

      _no_snapshot ->
        {:error, :stale_selection}
    end
  end

  defp finding_current?(assigns, finding_id) do
    match?({:ok, _finding}, current_finding(assigns, finding_id))
  end

  defp lane_for_ref(%{routes: routes}, route_ref) do
    case Enum.find(routes, &(&1.requested_route_ref == route_ref)) do
      nil -> :unknown
      route -> route.lane
    end
  end

  defp blocked_reason(%{blocked_lanes: [%{reason: reason} | _rest]}), do: reason
  defp blocked_reason(_preflight), do: nil

  defp role_can_use_ai?(socket) do
    case socket.assigns[:membership] do
      %{role: role} when is_binary(role) -> Projects.can?(role, :use_ai)
      _absent -> false
    end
  end

  defp locale(socket) do
    locale = socket.assigns[:locale]
    if locale in @locales, do: locale, else: "en"
  end

  # Low-cardinality error classes only: never a message, never an id.
  defp error_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_class(reason) when is_binary(reason), do: reason
  defp error_class(_reason), do: "unknown"

  defp track(socket, event, properties) do
    Analytics.track(socket.assigns.current_scope, event, properties)
  end
end

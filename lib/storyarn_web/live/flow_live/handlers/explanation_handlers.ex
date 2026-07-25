defmodule StoryarnWeb.FlowLive.Handlers.ExplanationHandlers do
  @moduledoc """
  Panel lifecycle for the optional AI explanation of ONE structural finding.

  The client only ever selects a server-computed `finding_id` and one issued
  route reference. Everything else — the finding, its evidence, the prompt, the
  payer, the price — is resolved server-side from the authorized snapshot.

  Opening the surface creates no operation, and may create no preflight either:
  it first resolves which attempt to act on, so a result already paid for and
  still inside its TTL is rendered directly and an operation still in flight is
  attached to. Only otherwise does preflight resolve routes and the Slice-6
  disclosure without calling a provider, and an operation then exists only after
  the actor picks a route.

  The kernel emits no completion event, so the panel polls its own operation while
  it is open. Polling stops when the operation settles, when the panel closes, or
  at the execution deadline — which means "stopped watching", not "failed".

  The generated narrative is a temporary, actor-private preview: it is never
  written into the flow, never turned into a finding, and never survives its
  TTL.

  ## What Slice 7.2b must touch here

  The slice contract says 7.2b "flips that flag and adds the personal cost class
  without changing any other field". True of the task; NOT true of this module.
  `AI.preflight/1` already returns `personal_choices` and `personal_preference`,
  and `panel_props/1` serializes neither, because only a `:ready` personal choice
  becomes a route. So with `personal_byok_allowed?: true` an actor whose key needs
  consent would see an empty panel: no route, no blocked lane, no reason.

  Enabling the personal lane therefore also means serializing those two into the
  panel props and rendering them in `FlowAnalysisExplanation.vue`. The TS type and
  both `flows.json` catalogs already carry `lanes.personal_byok`; only this
  boundary is missing. Deliberately not built ahead of time — an unreachable
  branch is what this slice's audit spent its time deleting.
  """

  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb.Helpers.Authorize

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.AI
  alias Storyarn.Analytics
  alias Storyarn.FeatureFlags

  defmodule Explanation do
    @moduledoc """
    The panel's own view of one explanation.

    A struct rather than a bare map because every transition previously respelled
    all thirteen keys, so adding a state meant editing three literals and a typo
    was silent.
    """
    defstruct [
      :status,
      :finding_id,
      :finding_key,
      :rule_id,
      :attempt,
      :disclosure,
      :retention_seconds,
      :operation_id,
      :result,
      :error,
      :polling_since,
      routes: [],
      blocked_lanes: [],
      # Whether THIS surface's purchase created `operation_id`, as opposed to
      # attaching to a run someone else started. Only a buyer may release.
      owns_operation?: false
    ]

    @type t :: %__MODULE__{}
  end

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
  # Statuses the panel stops polling on. "queued" and "running" are the two it
  # keeps watching.
  @terminal_statuses ~w(succeeded failed unknown cancelled)
  @watched_statuses [:queued, :running]
  @watchable_statuses ~w(queued running)
  @timer_key :explanation_poll_timer

  # Attempts one actor may spend on one occurrence, counted from 0. Enforced at
  # BOTH ends and it has to be: a reopen walks the attempts to find what was
  # already paid for, so an attempt a rerun can create but a reopen would never
  # reach is a result the actor bought and can never see again. Reruns are rare
  # (each is an explicit purchase of the same narrative, and any edit to the flow
  # rotates the fingerprint and resets the count), so this is generous rather
  # than tuned.
  @max_attempts 20

  # See `error_classes/0`. Kept sorted so a diff shows an addition clearly.
  @error_classes ~w(
    allowance_exhausted
    allowance_paused
    allowance_unavailable
    attempts_exhausted
    context_too_large
    duplicate_external_attempt
    input_too_large
    invalid_context_subject
    invalid_explanation_output
    invalid_result
    missing_use_ai
    model_context_limits_unavailable
    model_context_window_exceeded
    model_output_limit_exceeded
    no_route
    operation_not_found
    output_too_large
    provider_error
    rate_limited
    stale_finding
    stale_reservation
    task_contract_changed
    task_disabled
    unknown
    unknown_finding
    unknown_flow
    user_cancelled
    worker_interrupted
    worker_interrupted_before_attempt
    worker_retries_exhausted
  )

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @doc """
  Initial assigns for the explanation surface.

  Also releases an operation this surface bought and nobody is left to read —
  this runs on close and on every flow reload, and an abandoned managed operation
  would still bill. See `cancel_watched_operation/1` for what it will not touch.
  """
  @spec assign_initial_state(Socket.t()) :: Socket.t()
  def assign_initial_state(socket) do
    socket
    |> cancel_watched_operation()
    |> cancel_poll()
    |> assign(:explanation, nil)
    |> then(&assign(&1, :explanation_available, available?(&1)))
  end

  @doc "Whether this actor may see the explanation surface at all."
  @spec available?(Socket.t()) :: boolean()
  def available?(socket) do
    user = socket.assigns.current_scope.user

    # An operationally DISABLED task still shows the surface: the slice asks for
    # an honest blocked state rather than a command that silently disappears.
    # Only an unregistered task (a deployment without it) hides it.
    FeatureFlags.enabled?(:ai_integrations, for: user) and
      authorize(socket, :use_ai) == :ok and
      AI.flow_finding_explanation_registered?()
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @spec handle_open_explanation(map(), Socket.t()) :: result()
  def handle_open_explanation(%{"finding_id" => finding_id}, socket) when is_binary(finding_id) do
    if available?(socket) do
      case current_finding(socket.assigns, finding_id) do
        {:ok, finding} -> open_for(socket, finding)
        {:error, reason} -> {:noreply, refused(socket, reason)}
      end
    else
      {:noreply, refused(socket, :unavailable)}
    end
  end

  def handle_open_explanation(_params, socket), do: {:noreply, refused(socket, :stale_selection)}

  @doc """
  Closes the surface, releasing an operation it bought and stops waiting for.

  An abandoned managed operation would still settle and bill a unit nobody ever
  reads. It releases only what releasing is still free for, and only what this
  surface paid for — see `cancel_watched_operation/1`.
  """
  @spec handle_close_explanation(map(), Socket.t()) :: result()
  def handle_close_explanation(_params, socket), do: {:noreply, assign_initial_state(socket)}

  @doc """
  Explicitly buys a fresh explanation of the same finding.

  Raising `attempt` is the ONLY way to a second charge: without it the
  deterministic idempotency key replays the operation this actor already paid
  for. It stops at `@max_attempts`, which is what a reopen can walk back to —
  selling an attempt no reopen could ever find would take the actor's unit for a
  narrative that disappears the moment they close the panel.
  """
  @spec handle_rerun_explanation(map(), Socket.t()) :: result()
  def handle_rerun_explanation(_params, socket) do
    with %{finding_key: finding_key, attempt: attempt} = explanation <- socket.assigns[:explanation],
         true <- attempt + 1 < @max_attempts || {:exhausted, explanation},
         true <- available?(socket) || {:error, :unavailable},
         # By the STABLE key, not the occurrence id: a rerun is offered precisely
         # when the flow moved, and the occurrence id rotates with the evidence
         # fingerprint. Resolving by id would refuse the rerun exactly when the
         # actor needs it — the case the whole stale affordance exists for.
         {:ok, finding} <- current_finding_by_key(socket.assigns, finding_key) do
      # A rerun driven by staleness is the product outcome the slice cares about
      # — the actor saw an obsolete narrative and chose to pay for a current one.
      if explanation.status == :succeeded and not finding_current?(socket.assigns, explanation.finding_id) do
        track(socket, "flow explanation stale rerun", %{
          rule_id: finding.rule_id,
          rule_version: finding.rule_version
        })
      end

      preflight(socket, finding, attempt + 1)
    else
      {:exhausted, explanation} -> {:noreply, exhausted(socket, explanation)}
      {:error, reason} -> {:noreply, refused(socket, reason)}
      _absent -> {:noreply, refused(socket, :stale_selection)}
    end
  end

  # Says the same thing a reopen at the ceiling says, through the same declared
  # error class, rather than a flash with copy of its own. The last narrative is
  # not lost with it: reopening the panel replays the newest readable result.
  defp exhausted(socket, explanation) do
    assign(socket, :explanation, %{
      explanation
      | status: :blocked,
        attempt: @max_attempts,
        result: nil,
        error: error_class(:attempts_exhausted)
    })
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

    issue_preflight(socket, finding, attempt)
  end

  @doc false
  # Opening must not assume attempt 0. A key is spent PERMANENTLY by the first
  # operation that used it, even after that operation stops being readable —
  # cancelled, expired, or failed — and `Execution.execute/1` would then replay
  # the dead row forever instead of creating anything. So consider every attempt
  # this occurrence could have:
  #
  #   * the NEWEST attempt with something to show wins, so a reopen after a rerun
  #     shows what the actor last paid for rather than the narrative they
  #     replaced, and a run still in flight is ATTACHED to — which is also how
  #     two panels on one finding end up watching a single paid operation;
  #   * only then may a purchase consume the LOWEST key nobody has spent.
  #
  # Attempts are not necessarily spent in order, which is why the scan cannot
  # stop at the first gap: a blocked route and an abandoned preflight both raise
  # the attempt without creating anything, so stopping there would offer to buy a
  # narrative the actor is already holding one attempt above.
  defp open_for(socket, finding) do
    case resolve_attempt(socket, finding) do
      {:replay, attempt, output, operation} ->
        {:noreply, replayed(socket, finding, attempt, output, operation)}

      {:watch, attempt, operation} ->
        {:noreply, watching(socket, finding, attempt, operation)}

      {:preflight, attempt} ->
        preflight(socket, finding, attempt)

      :exhausted ->
        {:noreply, blocked(socket, finding, @max_attempts, :attempts_exhausted)}
    end
  end

  defp resolve_attempt(socket, finding) do
    scope = socket.assigns.current_scope
    task_id = AI.flow_finding_explanation_task_id()

    keys =
      Map.new(0..(@max_attempts - 1), fn attempt ->
        {attempt, AI.flow_finding_explanation_key(scope, finding, locale(socket), attempt)}
      end)

    spent = AI.get_operations_by_keys(scope, task_id, Map.values(keys))
    newest = Enum.sort(Map.keys(keys), :desc)

    resolved =
      newest(
        replayable(scope, task_id, keys, spent, newest),
        watchable(keys, spent, newest)
      )

    resolved || unspent(keys, spent)
  end

  defp replayable(scope, task_id, keys, spent, newest_first) do
    Enum.find_value(newest_first, fn attempt ->
      with %{execution_status: "succeeded"} <- spent[keys[attempt]],
           {:ok, output, operation} <- AI.get_replayable_result(scope, task_id, keys[attempt]) do
        {:replay, attempt, output, operation}
      else
        _unreadable -> nil
      end
    end)
  end

  defp watchable(keys, spent, newest_first) do
    Enum.find_value(newest_first, fn attempt ->
      case spent[keys[attempt]] do
        %{execution_status: status} = operation when status in @watchable_statuses ->
          {:watch, attempt, operation}

        _settled_or_absent ->
          nil
      end
    end)
  end

  defp unspent(keys, spent) do
    case Enum.find(Enum.sort(Map.keys(keys)), &is_nil(spent[keys[&1]])) do
      nil -> :exhausted
      attempt -> {:preflight, attempt}
    end
  end

  # A run still in flight outranks any completed result BELOW it: the actor reran
  # and is waiting, so attaching beats replaying what they chose to replace.
  defp newest(nil, other), do: other
  defp newest(other, nil), do: other
  defp newest(replay, watch) when elem(replay, 1) > elem(watch, 1), do: replay
  defp newest(_replay, watch), do: watch

  # Re-attaches the surface to an operation someone already paid for.
  defp watching(socket, finding, attempt, operation) do
    socket
    |> assign(:explanation, %Explanation{
      status: watch_status(operation),
      finding_id: finding.finding_id,
      finding_key: finding.finding_key,
      rule_id: finding.rule_id,
      attempt: attempt,
      operation_id: operation.id,
      polling_since: watch_started_at(operation)
    })
    |> schedule_poll()
  end

  defp watch_status(%{execution_status: "running"}), do: :running
  defp watch_status(_operation), do: :queued

  defp watch_started_at(%{execution_status: "running"}), do: System.monotonic_time(:millisecond)
  defp watch_started_at(_operation), do: nil

  defp replayed(socket, finding, attempt, output, operation) do
    AI.record_result_view(socket.assigns.current_scope, operation.id)

    track(socket, "flow explanation result viewed", %{
      rule_id: finding.rule_id,
      stale: not finding_current?(socket.assigns, finding.finding_id)
    })

    assign(socket, :explanation, %Explanation{
      status: :succeeded,
      finding_id: finding.finding_id,
      finding_key: finding.finding_key,
      rule_id: finding.rule_id,
      attempt: attempt,
      operation_id: operation.id,
      result: output
    })
  end

  defp issue_preflight(socket, finding, attempt) do
    with {:ok, intent} <- build_intent(socket, finding, %{}),
         {:ok, preflight} <- AI.preflight(intent) do
      track(socket, "flow explanation preflight shown", %{
        rule_id: finding.rule_id,
        rule_version: finding.rule_version,
        route_count: length(preflight.route_options)
      })

      {:noreply,
       assign(socket, :explanation, %Explanation{
         status: :preflight,
         finding_id: finding.finding_id,
         finding_key: finding.finding_key,
         rule_id: finding.rule_id,
         attempt: attempt,
         routes: preflight.route_options,
         blocked_lanes: preflight.blocked_lanes,
         disclosure: preflight.context_disclosure,
         retention_seconds: preflight.result_ttl_seconds
       })}
    else
      {:error, reason} -> {:noreply, blocked(socket, finding, attempt, reason)}
    end
  end

  # The task's wire format lives behind the facade; this only supplies the
  # authorized finding and the actor's own choices.
  defp build_intent(socket, finding, overrides) do
    %{flow: flow, project: project, current_scope: scope} = socket.assigns

    AI.flow_finding_explanation_intent(
      scope,
      Map.merge(
        %{
          workspace_id: project.workspace_id,
          project_id: project.id,
          flow_id: flow.id,
          finding: finding,
          locale: locale(socket)
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

    overrides = %{route_ref: route_ref, attempt: explanation.attempt}

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
          error: nil,
          # Asked, not assumed: `AI.execute/1` REPLAYS a spent key, so a second
          # panel that reached preflight for the same key before either ran gets
          # this operation back without having bought it.
          owns_operation?: AI.created_operation?(socket.assigns.current_scope, route_ref, operation.id)
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
        # Durable counterpart of the product event below: it is what lets expiry
        # tell viewed-then-abandoned from never-opened.
        AI.record_result_view(scope, operation.id)

        track(socket, "flow explanation result viewed", %{
          rule_id: explanation.rule_id,
          stale: not finding_current?(socket.assigns, explanation.finding_id)
        })

        socket
        |> cancel_poll()
        |> assign(:explanation, %{explanation | status: :succeeded, result: output})

      # Succeeded but not found means the actor-private TTL already elapsed.
      # Any other reason is a real failure and must not be dressed up as expiry:
      # a corrupt stored output would otherwise read as "no longer available"
      # and never reach the operator as its own class.
      {:error, :not_found} ->
        socket
        |> cancel_poll()
        |> assign(:explanation, %{explanation | status: :expired, result: nil})

      {:error, reason} ->
        failed(socket, explanation, reason)
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
    # `routable/1` turns "every lane blocked" into an error before the preflight
    # payload is built, so this is the ONLY place the blocked case is observable.
    track(socket, "flow explanation preflight blocked", %{
      rule_id: finding.rule_id,
      rule_version: finding.rule_version,
      error_class: error_class(reason)
    })

    assign(socket, :explanation, %Explanation{
      status: :blocked,
      finding_id: finding.finding_id,
      finding_key: finding.finding_key,
      rule_id: finding.rule_id,
      attempt: attempt,
      error: error_class(reason)
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

  # Gives up an operation this surface bought and stopped waiting for.
  #
  # Two things the panel must NOT do, both delegated to the kernel instead of
  # decided here:
  #
  #   * cancel a started provider attempt. `finish_success/4` commits the unit
  #     regardless, so cancelling then only DELETES the output the actor paid
  #     for; letting it finish leaves the result readable inside its TTL, where a
  #     reopen recovers it. Deciding that from a status read here would race the
  #     worker, so `AI.release_if_unstarted/2` decides under its own lock;
  #   * release an operation it merely ATTACHED to. Another panel is watching a
  #     run it paid for, and cancelling would fail that panel while it waits.
  #
  # Residual, and deliberate: when the buyer closes first, a panel still attached
  # to that run does lose it. Releasing what you bought is the owner's stated
  # policy, and "is anyone else still watching" is not knowable from here.
  defp cancel_watched_operation(socket) do
    with %{status: status, operation_id: operation_id, owns_operation?: true} <-
           socket.assigns[:explanation],
         true <- status in [:queued, :running, :detached] and is_integer(operation_id) do
      AI.release_if_unstarted(socket.assigns.current_scope, operation_id)
      socket
    else
      _nothing_to_release -> socket
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
      retentionSeconds: nil,
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
      retentionSeconds: explanation.retention_seconds,
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

  # A shape the kernel does not produce today. Rendering must not raise over it:
  # the panel's job is to show what it can, and `error_class/1` already maps an
  # unrecognised reason to "unknown".
  defp blocked_lane_props(_lane), do: %{lane: "unknown", reason: "unknown"}

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

  # Same rule as `current_finding/2`, keyed on the stable rule+target identity so
  # a rotated occurrence still resolves.
  defp current_finding_by_key(assigns, finding_key) do
    case assigns[:analysis_snapshot] do
      %{stale: true} ->
        {:error, :stale_snapshot}

      %{active: active} ->
        case Enum.find(active, &(&1.finding_key == finding_key)) do
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

  defp locale(socket) do
    locale = socket.assigns[:locale]
    if locale in Gettext.known_locales(Storyarn.Gettext), do: locale, else: "en"
  end

  @doc """
  Every error class this surface can render, and therefore must have copy for.

  Declared rather than derived: reasons reach here from the kernel, the task,
  the Flows domain and this module, so an open-ended passthrough plus the Vue
  `te()` fallback made a missing translation invisible — the actor saw the
  generic sentence and no test could fail. Anything not listed is deliberately
  reported as `unknown`; adding a class here without copy in both locales fails
  `explanation_handlers_test.exs`.
  """
  @spec error_classes() :: [String.t()]
  def error_classes, do: @error_classes

  # Low-cardinality error classes only: never a message, never an id.
  defp error_class(reason) when is_atom(reason), do: reason |> Atom.to_string() |> known_class()
  defp error_class(reason) when is_binary(reason), do: known_class(reason)
  defp error_class(_reason), do: "unknown"

  # Left as a private wrapper in both analysis handlers on purpose: importing a
  # 3-line shim across handler modules would buy a dependency for less than it
  # costs.
  defp track(socket, event, properties) do
    Analytics.track(socket.assigns.current_scope, event, properties)
  end

  defp known_class(class) when class in @error_classes, do: class
  defp known_class(_class), do: "unknown"
end

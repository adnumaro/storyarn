defmodule StoryarnWeb.Telemetry do
  @moduledoc false
  use Supervisor

  import Telemetry.Metrics

  alias Storyarn.Platform.Adapters.Oban.OperationalMetrics

  @multipart_inventory_failures [
    :none,
    :inventory_limit_exceeded,
    :unsupported,
    :invalid_response,
    :provider_error,
    :exception,
    :exit,
    :throw
  ]
  @prometheus_reporter_name :storyarn_operational_metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc false
  def prometheus_metrics do
    metrics()
    |> Enum.filter(&prometheus_operational_metric?/1)
    |> Enum.map(&sanitize_prometheus_metric/1)
    |> Kernel.++(oban_prometheus_metrics())
  end

  @doc false
  def prometheus_reporter_child_specs(config) when is_list(config) do
    if Keyword.fetch!(config, :enabled) do
      [
        TelemetryMetricsPrometheus.Core.child_spec(
          metrics: prometheus_metrics(),
          name: @prometheus_reporter_name,
          start_async: false
        )
      ]
    else
      []
    end
  end

  @doc false
  def prometheus_reporter_name, do: @prometheus_reporter_name

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("storyarn.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("storyarn.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("storyarn.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("storyarn.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("storyarn.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # Project template installation metrics
      sum("storyarn.project_template.installation.requested.count",
        tags: [:source, :visibility]
      ),
      sum("storyarn.project_template.installation.stop.count",
        tags: [:status, :source, :error_code]
      ),
      summary("storyarn.project_template.installation.stop.duration",
        tags: [:status, :source, :error_code],
        unit: {:native, :millisecond}
      ),

      # Project import metrics. Tags are deliberately low-cardinality and must
      # never include filenames, content, user IDs, or project IDs.
      sum("storyarn.import.prepare.stop.count",
        tags: [:format, :source_kind, :status, :error_code, :parser_version]
      ),
      summary("storyarn.import.prepare.stop.duration",
        tags: [:format, :source_kind, :status, :error_code, :parser_version],
        unit: {:native, :millisecond}
      ),
      sum("storyarn.import.execute.stop.count",
        tags: [:format, :source_kind, :status, :error_code, :parser_version, :import_mode]
      ),
      summary("storyarn.import.execute.stop.duration",
        tags: [:format, :source_kind, :status, :error_code, :parser_version, :import_mode],
        unit: {:native, :millisecond}
      ),
      sum("storyarn.import.error.count",
        tags: [:format, :parser_version, :import_mode, :phase, :error_code, :exception_module]
      ),
      sum("storyarn.import.snapshot.transition.count",
        tags: [:format, :source_kind, :parser_version, :import_mode, :state]
      ),
      sum("storyarn.import.expiration.stop.expired_count",
        tags: [:status, :error_code]
      ),
      sum("storyarn.import.expiration.stop.failure_count",
        tags: [:status, :error_code]
      ),
      sum("storyarn.import.expiration.stop.continuation_count",
        tags: [:status, :error_code]
      ),
      sum("storyarn.import.expiration.terminal.count",
        tags: [:format, :disposition]
      ),
      summary("storyarn.import.expiration.stop.duration",
        tags: [:status, :error_code],
        unit: {:native, :millisecond}
      ),

      # Recoverable asset-trash lifecycle. IDs and filenames intentionally
      # remain outside metric tags.
      sum("storyarn.assets.trash.stop.count", tags: [:action, :outcome]),
      sum("storyarn.assets.storage_compensation.persisted_retry.count"),
      sum("storyarn.assets.storage_compensation.persisted_retry.failed_count"),
      last_value("storyarn.assets.storage_compensation.backlog.pending_count"),
      last_value("storyarn.assets.storage_compensation.backlog.due_count"),
      last_value("storyarn.assets.storage_compensation.backlog.deferred_multipart_count"),
      last_value("storyarn.assets.storage_compensation.backlog.oldest_age_seconds"),
      last_value("storyarn.assets.storage_compensation.backlog.oldest_due_age_seconds"),
      last_value("storyarn.assets.storage_compensation.backlog.observed_at_unix_seconds"),

      # Product-accounted storage and provider footprint are separate signals.
      # Workspace IDs remain event metadata rather than metric tags to avoid
      # unbounded cardinality in reporters.
      last_value("storyarn.storage.accounting.updated.accounted_bytes",
        tags: [:action, :accounting_version]
      ),
      last_value("storyarn.storage.accounting.updated.reservation_bytes",
        tags: [:action, :accounting_version]
      ),
      last_value("storyarn.storage.accounting.updated.total_bytes",
        tags: [:action, :accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.physical_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.temporary_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.orphan_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.duplicate_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.cleanup_pending_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.accounted_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.reservation_bytes",
        tags: [:accounting_version]
      ),
      last_value("storyarn.storage.provider_footprint.drift_bytes",
        tags: [:accounting_version]
      ),

      # The inventory operation scans the complete provider namespace but never
      # emits provider keys or upload IDs. Only the closed failure taxonomy is
      # exported as a label.
      last_value("storyarn.storage.multipart_inventory.snapshot.count",
        keep: &multipart_inventory_metadata?/1,
        tag_values: &no_tag_values/1
      ),
      last_value("storyarn.storage.multipart_inventory.snapshot.oldest_age_seconds",
        keep: &multipart_inventory_metadata?/1,
        tag_values: &no_tag_values/1
      ),
      last_value("storyarn.storage.multipart_inventory.snapshot.inventory_complete",
        keep: &multipart_inventory_metadata?/1,
        tag_values: &no_tag_values/1
      ),
      last_value("storyarn.storage.multipart_inventory.snapshot.observed_at_unix_seconds",
        keep: &multipart_inventory_metadata?/1,
        tag_values: &no_tag_values/1
      ),
      sum("storyarn.storage.multipart_inventory.snapshot.failure_count",
        tags: [:failure],
        keep: &multipart_inventory_failure?/1,
        tag_values: &multipart_inventory_tag_values/1
      ),
      sum("storyarn.snapshot.reset.stop.object_count",
        tags: [:status, :environment, :error_code]
      ),
      sum("storyarn.snapshot.reset.stop.snapshot_row_count",
        tags: [:status, :environment, :error_code]
      ),
      sum("storyarn.snapshot.reset.stop.entity_version_row_count",
        tags: [:status, :environment, :error_code]
      ),
      sum("storyarn.snapshot.reset.stop.attempt_count",
        tags: [:status, :environment, :error_code]
      ),

      # Snapshot deletion first emits an immutable cleanup intent, then reports
      # bounded progress independently from product-accounted quota release.
      sum("storyarn.snapshot.cleanup.intent.count",
        tags: [:reason, :mode, :authority_kind]
      ),
      sum("storyarn.snapshot.cleanup.intent.object_count",
        tags: [:reason, :mode, :authority_kind]
      ),
      sum("storyarn.snapshot.cleanup.intent.estimated_cleanup_bytes",
        tags: [:reason, :mode, :authority_kind]
      ),
      sum("storyarn.snapshot.cleanup.stop.deleted_count",
        tags: [:status, :reason, :error_code]
      ),
      sum("storyarn.snapshot.cleanup.stop.retry_count",
        tags: [:status, :reason, :error_code]
      ),
      sum("storyarn.snapshot.cleanup.stop.terminal_failure_count",
        tags: [:status, :reason, :error_code]
      ),
      sum("storyarn.snapshot.cleanup.replay.count", tags: [:status, :reason]),
      sum("storyarn.snapshot.cleanup.recovery.stop.recovered_count", tags: [:status]),
      sum("storyarn.snapshot.cleanup.recovery.stop.skipped_count", tags: [:status]),
      sum("storyarn.snapshot.cleanup.recovery.stop.failure_count", tags: [:status]),
      sum("storyarn.snapshot.cleanup.recovery.stop.continuation_count", tags: [:status]),
      last_value("storyarn.snapshot.cleanup.backlog.backlog_count"),
      last_value("storyarn.snapshot.cleanup.backlog.backlog_bytes"),
      last_value("storyarn.snapshot.cleanup.backlog.retry_count"),
      last_value("storyarn.snapshot.cleanup.backlog.terminal_failures"),
      last_value("storyarn.snapshot.cleanup.backlog.terminal_retry_count"),
      last_value("storyarn.snapshot.cleanup.backlog.repeated_terminal_failures"),
      last_value("storyarn.snapshot.cleanup.backlog.oldest_age_seconds"),
      last_value("storyarn.snapshot.cleanup.backlog.observed_at_unix_seconds"),
      sum("storyarn.snapshot.retention.stop.deleted_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.expired_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.expired_export_lease_candidate_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.expired_export_lease_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.expired_export_lease_changed_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.purged_export_lease_candidate_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.purged_export_lease_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.purged_export_lease_changed_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.orphaned_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.settled_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.failure_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.continuation_count", tags: [:status]),

      # Snapshot/job IDs remain event metadata; only the bounded renewal result
      # is a metric tag.
      sum("storyarn.snapshot.build.heartbeat.count", tags: [:outcome]),

      # Snapshot download identifiers remain event metadata. Metric tags are
      # deliberately bounded to operational outcome classifications.
      sum("storyarn.snapshot.download.lease.count", tags: [:outcome]),
      sum("storyarn.snapshot.download.stop.count", tags: [:outcome, :phase, :error_code]),
      sum("storyarn.snapshot.download.stop.bytes", tags: [:outcome, :phase, :error_code]),
      sum("storyarn.snapshot.download.stop.artifact_bytes", tags: [:outcome, :phase, :error_code]),
      summary("storyarn.snapshot.download.stop.duration",
        tags: [:outcome, :phase, :error_code],
        unit: {:native, :millisecond}
      ),
      sum("storyarn.snapshot.import.delivery.stop.count",
        tags: [:outcome],
        keep: &snapshot_import_outcome?/1
      ),

      # Reconciliation is an operator-started, observation-only dry-run. IDs
      # remain out of metric tags; persisted runs and findings retain detail.
      sum("storyarn.snapshot.reconciliation.start.count", tags: [:contract_version, :mode]),
      sum("storyarn.snapshot.reconciliation.page.finding_count", tags: [:phase, :status]),
      last_value("storyarn.snapshot.reconciliation.page.inspected_snapshot_count", tags: [:phase, :status]),
      last_value("storyarn.snapshot.reconciliation.page.inspected_object_count", tags: [:phase, :status]),
      last_value("storyarn.snapshot.reconciliation.page.inspected_bytes", tags: [:phase, :status]),
      last_value("storyarn.snapshot.reconciliation.page.provider_object_count", tags: [:phase, :status]),
      last_value("storyarn.snapshot.reconciliation.page.provider_bytes", tags: [:phase, :status]),
      sum("storyarn.snapshot.reconciliation.stop.count", tags: [:status, :multipart_inventory_state]),
      last_value("storyarn.snapshot.reconciliation.stop.finding_count",
        tags: [:status, :multipart_inventory_state]
      ),
      sum("storyarn.snapshot.reconciliation.repair.stop.count", tags: [:action, :outcome]),
      sum("storyarn.snapshot.reconciliation.repair.stop.bytes", tags: [:action, :outcome]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.requeued_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.reenqueued_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.already_active_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.terminalized_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.already_terminal_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.failure_count", tags: [:status]),
      sum("storyarn.snapshot.reconciliation.repair.recovery.stop.continuation_count", tags: [:status]),
      last_value("storyarn.snapshot.reconciliation.summary.stale_reservation_bytes",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.summary.orphan_object_bytes",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.summary.missing_ready_snapshot_count",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.summary.corrupt_ready_snapshot_count",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.summary.terminal_cleanup_failure_count",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.summary.terminal_cleanup_retry_count",
        tags: [:contract_version, :mode, :multipart_inventory_state]
      ),
      last_value("storyarn.snapshot.reconciliation.projection.stop.success"),
      sum("storyarn.snapshot.reconciliation.projection.stop.failure_count"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.latest_completed_available"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.latest_completed_at_unix_seconds"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.observed_at_unix_seconds"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.finding_count"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.stale_reservation_bytes"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.orphan_object_bytes"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.missing_ready_snapshot_count"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.corrupt_ready_snapshot_count"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.terminal_cleanup_failure_count"),
      last_value("storyarn.snapshot.reconciliation.projection.stop.terminal_cleanup_retry_count"),

      # AI result retention is content-free and bounded per worker batch.
      sum("storyarn.ai.expiration.stop.expired_count", tags: [:status]),
      sum("storyarn.ai.expiration.stop.failure_count", tags: [:status]),
      summary("storyarn.ai.expiration.stop.duration",
        tags: [:status],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {StoryarnWeb, :count_users, []}
    ]
  end

  defp prometheus_operational_metric?(metric) do
    aggregate? = metric.__struct__ in [Telemetry.Metrics.Sum, Telemetry.Metrics.LastValue]
    name = metric.name

    aggregate? and
      (List.starts_with?(name, [:storyarn, :import]) or
         List.starts_with?(name, [:storyarn, :assets, :storage_compensation]) or
         List.starts_with?(name, [:storyarn, :storage, :multipart_inventory]) or
         (List.starts_with?(name, [:storyarn, :snapshot]) and
            not List.starts_with?(name, [:storyarn, :snapshot, :reconciliation, :page]) and
            not List.starts_with?(name, [:storyarn, :snapshot, :reconciliation, :summary]) and
            name != [:storyarn, :snapshot, :reconciliation, :stop, :finding_count]))
  end

  defp oban_prometheus_metrics do
    [
      counter("storyarn.oban.job.stop.count",
        event_name: [:oban, :job, :stop],
        tags: [:queue, :state],
        keep: &recovery_queue_job?/1,
        tag_values: &oban_job_tag_values/1
      ),
      counter("storyarn.oban.job.exception.count",
        event_name: [:oban, :job, :exception],
        tags: [:queue, :state],
        keep: &recovery_queue_job?/1,
        tag_values: &oban_job_tag_values/1
      ),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.backlog_count"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.due_count"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.executing_count"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.retryable_count"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.max_recorded_error_count"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.oldest_due_age_seconds"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.oldest_waiting_age_seconds"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.oldest_executing_age_seconds"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.configured_capacity"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.effective_capacity"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.paused"),
      recovery_queue_last_value("storyarn.oban.queue.snapshot.runtime_available"),
      last_value("storyarn.oban.queue.poll.stop.success"),
      last_value("storyarn.oban.queue.poll.stop.last_success_unix_seconds",
        keep: &oban_poll_success?/1
      ),
      sum("storyarn.oban.queue.poll.stop.failure_count",
        tags: [:failure],
        keep: &oban_poll_failure?/1,
        tag_values: &oban_poll_tag_values/1
      )
    ]
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :import, :execute, :stop, :count]} = metric) do
    %{metric | tags: [:format, :status, :import_mode], tag_values: &import_execute_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :import, :error, :count]} = metric) do
    %{metric | tags: [:format, :import_mode, :phase], tag_values: &import_error_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :import, :snapshot, :transition, :count]} = metric) do
    %{metric | tags: [:format, :import_mode, :state], tag_values: &import_snapshot_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :import, :expiration, :terminal, :count]} = metric) do
    %{metric | tags: [:format, :disposition], tag_values: &import_expiration_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :storage, :multipart_inventory, :snapshot | _]} = metric),
    do: metric

  defp sanitize_prometheus_metric(%{name: [:storyarn, :snapshot, :import, :delivery, :stop, :count]} = metric) do
    %{metric | tags: [:outcome], tag_values: &snapshot_import_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :snapshot, :reconciliation, :stop | _]} = metric) do
    %{metric | tags: [:status], tag_values: &reconciliation_status_tag_values/1}
  end

  defp sanitize_prometheus_metric(%{name: [:storyarn, :snapshot, :reconciliation, :repair, :stop | _]} = metric) do
    %{metric | tags: [:outcome], tag_values: &reconciliation_repair_tag_values/1}
  end

  # Every other selected metric is already global and is exported as an
  # aggregate. Per-workspace accounting, provider-footprint, and per-page
  # reconciliation gauges are not selected: dropping their scoping labels
  # would turn the latest local event into a misleading global value.
  defp sanitize_prometheus_metric(metric), do: %{metric | tags: [], tag_values: &no_tag_values/1}

  defp recovery_queue_job?(%{job: %{queue: queue}}), do: queue in OperationalMetrics.queue_names()
  defp recovery_queue_job?(_metadata), do: false

  defp recovery_queue_last_value(name) do
    last_value(name,
      tags: [:queue],
      keep: &recovery_queue_snapshot?/1,
      tag_values: &recovery_queue_snapshot_tag_values/1
    )
  end

  defp recovery_queue_snapshot?(%{queue: queue}), do: queue in OperationalMetrics.queue_names()
  defp recovery_queue_snapshot?(_metadata), do: false
  defp recovery_queue_snapshot_tag_values(%{queue: queue}), do: %{queue: queue}

  defp oban_job_tag_values(%{job: %{queue: queue}, state: state}) do
    %{queue: queue, state: bounded_job_state(state)}
  end

  defp oban_poll_success?(%{failure: :none}), do: true
  defp oban_poll_success?(_metadata), do: false

  defp oban_poll_failure?(%{failure: failure}), do: failure in [:exception, :exit, :throw]
  defp oban_poll_failure?(_metadata), do: false
  defp oban_poll_tag_values(%{failure: failure}), do: %{failure: Atom.to_string(failure)}

  defp import_execute_tag_values(metadata) do
    %{
      format: bounded_tag_value(Map.get(metadata, :format), ~w(yarn storyarn unknown)),
      status: bounded_tag_value(Map.get(metadata, :status), ~w(completed retrying failed expired)),
      import_mode: bounded_tag_value(Map.get(metadata, :import_mode), ~w(additive replace_project unknown))
    }
  end

  defp import_error_tag_values(metadata) do
    %{
      format: bounded_tag_value(Map.get(metadata, :format), ~w(yarn storyarn unknown)),
      import_mode: bounded_tag_value(Map.get(metadata, :import_mode), ~w(additive replace_project unknown)),
      phase: bounded_tag_value(Map.get(metadata, :phase), ~w(prepare execute unknown))
    }
  end

  defp import_snapshot_tag_values(metadata) do
    %{
      format: bounded_tag_value(Map.get(metadata, :format), ~w(yarn storyarn unknown)),
      import_mode: bounded_tag_value(Map.get(metadata, :import_mode), ~w(additive replace_project unknown)),
      state: bounded_tag_value(Map.get(metadata, :state), ~w(awaiting_snapshot ready))
    }
  end

  defp import_expiration_tag_values(metadata) do
    %{
      format: bounded_tag_value(Map.get(metadata, :format), ~w(yarn storyarn unknown)),
      disposition: bounded_tag_value(Map.get(metadata, :disposition), ~w(accepted preview))
    }
  end

  defp no_tag_values(_metadata), do: %{}

  defp multipart_inventory_metadata?(%{failure: failure}), do: failure in @multipart_inventory_failures

  defp multipart_inventory_metadata?(_metadata), do: false

  defp multipart_inventory_failure?(%{failure: failure} = metadata),
    do: failure != :none and multipart_inventory_metadata?(metadata)

  defp multipart_inventory_failure?(_metadata), do: false

  defp multipart_inventory_tag_values(%{failure: failure}), do: %{failure: Atom.to_string(failure)}

  defp snapshot_import_outcome?(%{outcome: outcome}),
    do: outcome in [:completed, :terminal_failure, :retrying, :snoozed, :discarded, :unexpected]

  defp snapshot_import_outcome?(_metadata), do: false
  defp snapshot_import_tag_values(%{outcome: outcome}), do: %{outcome: Atom.to_string(outcome)}

  defp reconciliation_status_tag_values(metadata) do
    %{status: bounded_tag_value(Map.get(metadata, :status), ~w(completed failed))}
  end

  defp reconciliation_repair_tag_values(metadata) do
    %{outcome: bounded_tag_value(Map.get(metadata, :outcome), ~w(repaired resolved manual failed))}
  end

  defp bounded_tag_value(value, allowed) when is_atom(value), do: bounded_tag_value(Atom.to_string(value), allowed)

  defp bounded_tag_value(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: "other"
  end

  defp bounded_tag_value(_value, _allowed), do: "other"

  defp bounded_job_state(state) when state in [:success, :failure, :cancelled, :discard, :exhausted, :snoozed],
    do: Atom.to_string(state)

  defp bounded_job_state(_state), do: "other"
end

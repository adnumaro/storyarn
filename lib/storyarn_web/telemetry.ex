defmodule StoryarnWeb.Telemetry do
  @moduledoc false
  use Supervisor

  import Telemetry.Metrics

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
        tags: [:format, :source_kind, :status, :error_code, :parser_version]
      ),
      summary("storyarn.import.execute.stop.duration",
        tags: [:format, :source_kind, :status, :error_code, :parser_version],
        unit: {:native, :millisecond}
      ),
      sum("storyarn.import.error.count",
        tags: [:format, :parser_version, :phase, :error_code, :exception_module]
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
      summary("storyarn.import.expiration.stop.duration",
        tags: [:status, :error_code],
        unit: {:native, :millisecond}
      ),

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
      sum("storyarn.snapshot.retention.stop.deleted_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.expired_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.orphaned_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.settled_build_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.failure_count", tags: [:status]),
      sum("storyarn.snapshot.retention.stop.continuation_count", tags: [:status]),

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
end

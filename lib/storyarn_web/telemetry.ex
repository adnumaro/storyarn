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
      summary("storyarn.import.expiration.stop.duration",
        tags: [:status, :error_code],
        unit: {:native, :millisecond}
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

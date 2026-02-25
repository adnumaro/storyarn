# Queue Configuration Reference

## Basic Configuration

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    critical: 20,           # High priority, fast
    mailers: 50,            # I/O-bound
    webhooks: 30,           # External API calls
    media_processing: 3,    # CPU-intensive
    external_api: [limit: 5, dispatch_cooldown: 100],
    imports: 10             # Bulk processing
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]
```

## Queue Design Principles

- **I/O vs CPU bound** — Separate queues prevent CPU work from blocking I/O
- **External dependencies** — Different APIs get isolated queues
- **Priority separation** — Critical jobs in dedicated high-concurrency queue
- **Rate limiting** — Queue-level `dispatch_cooldown` for API respect

## Connection Pool Sizing

```elixir
# Rule: pool_size >= num_queues + sum(queue_limits) + buffer
config :my_app, MyApp.Repo, pool_size: 25
```

## Cron Scheduling

```elixir
plugins: [
  {Oban.Plugins.Cron,
    timezone: "America/New_York",
    crontab: [
      {"* * * * *", MyApp.MinuteWorker},
      {"0 * * * *", MyApp.HourlyWorker},
      {"0 0 * * *", MyApp.DailyWorker},
      {"0 12 * * MON", MyApp.MondayNoonWorker},
      {"@daily", MyApp.MidnightWorker},
      {"@reboot", MyApp.StartupWorker}
    ]}
]
```

## Production Checklist

- [ ] Connection pool sized: `>= num_queues + sum(limits) + buffer`
- [ ] Pruner configured with `max_age`
- [ ] Lifeline plugin enabled for stuck jobs
- [ ] Telemetry attached for error tracking
- [ ] Graceful shutdown period set
- [ ] Unique constraints on user-triggered jobs
- [ ] All workers handle return values explicitly
- [ ] Idempotency for critical operations (payments, emails)

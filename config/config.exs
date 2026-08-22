# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Keep every object-storage socket phase bounded well below the import-plan
# reservation lease. The importer also wraps the whole PUT in a wall-clock
# deadline because a send timeout only limits individual blocked writes.
alias Storyarn.Workers.ExpireAIResultsWorker
alias Storyarn.Workers.TrashRetentionWorker

config :ex_aws, :req_opts,
  receive_timeout: 60_000,
  pool_timeout: 10_000,
  connect_options: [timeout: 30_000, transport_opts: [send_timeout: 60_000]]

config :ex_aws, :s3,
  scheme: "https://",
  region: "auto"

# ExAws configuration for Cloudflare R2 (S3-compatible)
# Credentials are configured in runtime.exs
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Req

# Feature flags — Postgres-backed with per-node cache invalidated via PubSub.
# Runtime toggling supports gradual rollout to individual users during beta.
config :fun_with_flags, :cache,
  enabled: true,
  ttl: 900

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: Storyarn.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Storyarn.Repo,
  ecto_table_name: "fun_with_flags_toggles"

# LiveVue configuration
config :live_vue,
  ssr: false,
  gettext_backend: Storyarn.Gettext

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Yarn Spinner source files are plain text but have no IANA-registered media
# type. Register the extension so LiveView uploads can keep an explicit accept
# list; server-side format and archive validation remains authoritative.
config :mime, :types, %{"text/x-yarn-spinner" => ["yarn"]}

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, ["password", "secret", "token", "api_key", "_csrf_token"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix_vite, PhoenixVite.Npm,
  assets: [args: [], cd: Path.expand("..", __DIR__)],
  vite: [
    args: ~w(exec -- vite),
    cd: Path.expand("..", __DIR__),
    env: %{"MIX_BUILD_PATH" => Mix.Project.build_path()}
  ]

# PostHog product analytics and error tracking are enabled only from runtime
# config once a project API key is present.
config :posthog,
  enable: false,
  enable_error_tracking: false,
  in_app_otp_apps: [:storyarn]

# Oban background job processing
#
# Cadence is a database-cost decision, not just a latency one. The production
# database (Neon) suspends its compute after five minutes without a query, so
# every background poll finer than that pins the compute at 100% and burns the
# monthly compute budget on an otherwise idle app. Because compute stays warm
# for five minutes after each touch, only the *finest* interval matters —
# anything coarser lands inside a wake window that was already paid for.
#
# The floor is therefore 15 minutes, and each sweep is set as coarse as the
# window it actually enforces allows. See ENG-37.
config :storyarn, Oban,
  engine: Oban.Engines.Basic,
  repo: Storyarn.Repo,
  # Process groups instead of Postgres LISTEN/NOTIFY: the latter holds a
  # connection open purely to wait. Valid because Fly runs a single machine
  # (`min_machines_running = 1`).
  notifier: {Oban.Notifiers.PG, []},
  # Oban's default is one second. Staging is a query, so at that rate the
  # compute can never idle. The cost of raising it is that everything deferred —
  # retry backoffs, `schedule_in` chains, `{:snooze, _}` — inherits up to this
  # much latency.
  stage_interval: to_timeout(minute: 15),
  queues: [
    default: 10,
    templates: 1,
    template_installs: 2,
    localization: 2,
    # `:imports` carries user-facing import execution only. The expiry sweep
    # lives on its own queue for the same reason the AI sweeps do: two
    # concurrent imports must not be able to block the sweep that expires them.
    imports: 2,
    imports_maintenance: 1,
    # `:ai` carries user-facing execution only. Maintenance sweeps live on their
    # own queue so the reaper never depends on the producer it is meant to
    # rescue, and so an expiry backlog cannot starve execution.
    ai: 2,
    ai_maintenance: 1,
    # Snapshot builds stay serialized because one job may stream many large
    # objects and owns durable retry state.
    snapshot_archives: 1,
    # Exact restores are also serialized: each operation stages and verifies
    # a complete snapshot-owned object set before its database commit.
    snapshot_restores: 1,
    snapshot_imports: 1,
    snapshots_maintenance: 1,
    storage_cleanup: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {
      Oban.Plugins.Cron,
      # Each entry is paired with the window it enforces. Nothing may be finer
      # than 15 minutes without re-doing the compute-budget arithmetic in ENG-37.
      crontab: [
        # 24h retention (`Billing.Plan` `trash_retention_hours: 24`); 4h is still
        # six times finer than the window.
        {"0 */4 * * *", TrashRetentionWorker},
        # 24h retention (`Imports` `@plan_retention_seconds 86_400`).
        {"0 * * * *", Storyarn.Workers.ExpireProjectImportsWorker},
        # Correctness does not depend on this sweep: the read path already
        # refuses results past `expires_at`. It only reclaims rows.
        {"*/30 * * * *", ExpireAIResultsWorker},
        # Recovery bound is `stale_after_seconds` + this interval. Holding the
        # documented ≤20 min means 300 + 900, where it used to be 900 + 300.
        {"*/15 * * * *", Storyarn.Workers.ReconcileAIReservationsWorker},
        # Safety net for cleanup requests whose direct enqueue failed — already a
        # rare path. Its own uniqueness window made it run every 2-3 min anyway.
        {"*/15 * * * *", Storyarn.Workers.RetryStorageCleanupRequestsWorker},
        # Snapshot cleanup ownership survives job pruning and terminal Oban
        # states. Reconcile the durable intent to an immediately available job.
        {"*/15 * * * *", Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker},
        # Repair actions are a durable operator ledger too. Restore only their
        # exact delivery chain and terminalize exhausted chains fail-closed.
        {"*/15 * * * *", Storyarn.Workers.ReconcileProjectSnapshotRepairWorker},
        # Snapshot TTL deletion is coarse, but this worker also reclaims expired
        # build reservations. Run at the ENG-37 floor to bound that quota leak.
        {"*/15 * * * *", Storyarn.Workers.ProjectSnapshotRetentionWorker}
      ]
    }
  ]

config :storyarn, Storyarn.AI.CredentialResolver, Storyarn.AI.CredentialResolver.Unavailable
config :storyarn, Storyarn.AI.InferenceProviders, providers: %{}
config :storyarn, Storyarn.AI.RouteOptions, ttl_seconds: 300
config :storyarn, Storyarn.AI.RouteResolver, managed: nil
config :storyarn, Storyarn.AI.Settlement, Storyarn.AI.Settlement.Unavailable

# Route, credential resolver and allowance stay unavailable until runtime
# configuration provides them. The task list is owned by config/runtime.exs;
# dev/test override it explicitly.
config :storyarn, Storyarn.AI.TaskRegistry, tasks: []

# UploadPart has a hard wall-clock deadline in addition to the socket-phase
# limits above. Durable multipart cleanup uses this same value as its minimum
# quiescence window, so one policy bounds both sides of the handoff.
config :storyarn, Storyarn.Assets.Storage, multipart_upload_part_deadline_ms: 5 * 60 * 1_000
config :storyarn, Storyarn.Flows.Versioning.RestorePolicy, flow_version_restore: false

# Configure Gettext locales
config :storyarn, Storyarn.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# Configures the mailer
# Development uses Mailpit (SMTP on localhost:1025, UI on localhost:8025)
# Production uses Resend API (configured in runtime.exs)
config :storyarn, Storyarn.Mailer, adapter: Swoosh.Adapters.Local

# Public, indexable locales are deliberately configured separately from
# Gettext. A locale can be available inside the authenticated application
# before its landing page, docs, legal copy, and editorial content are ready
# to be published under a canonical URL.
config :storyarn, Storyarn.Publication.Locales,
  default_locale: "en",
  locales: [
    %{gettext_locale: "en", language_tag: "en", path_segment: "en"},
    %{gettext_locale: "es", language_tag: "es", path_segment: "es"}
  ]

# Cloak encryption configuration
# Development key - NEVER use in production!
# Generate production key with: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
config :storyarn, Storyarn.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      # This is a development-only key, override in production via CLOAK_KEY env var
      tag: "AES.GCM.V1", key: Base.decode64!("dGhpc2lzYWRldmVsb3BtZW50a2V5b25seTMyYnl0ZXM="), iv_length: 12
    }
  ]

config :storyarn, Storyarn.Versioning.ProjectSnapshotLeasePolicy,
  download_signed_url_ttl_seconds: 5 * 60,
  download_max_transfer_seconds: 60 * 60,
  download_lease_safety_seconds: 60,
  build_heartbeat_interval_seconds: 60,
  build_lease_ttl_seconds: 5 * 60,
  export_lease_retention_seconds: 7 * 24 * 60 * 60

# Entity-version restore surfaces remain disabled by default and are enabled
# independently only after their canonical workflows are operationally ready.
# Exact full-project snapshot restore is part of the recovery contract and is
# always available to authorized project managers.
config :storyarn, Storyarn.Versioning.RestorePolicy,
  sheet_version_restore: false,
  scene_version_restore: false

# Configures the endpoint
config :storyarn, StoryarnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StoryarnWeb.ErrorHTML, json: StoryarnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Storyarn.PubSub,
  live_view: [signing_salt: "ox8oI2KY"],
  # Session cookie salts - override in production via env vars
  session_signing_salt: "Fnke9Hmj",
  session_encryption_salt: "cV3kP8mQ"

# Automatic trash hard-deletion is frozen while restore and referential
# integrity are being hardened.
config :storyarn, TrashRetentionWorker, enabled: false

config :storyarn,
       :import_idempotency_secret,
       :crypto.mac(
         :hmac,
         :sha256,
         Base.decode64!("dGhpc2lzYWRldmVsb3BtZW50a2V5b25seTMyYnl0ZXM="),
         "storyarn/import-idempotency/v1"
       )

# Email sender configuration (name and email address for outgoing emails)
config :storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"}

# Frontend PostHog boot is optional. The SDK config above remains the source for
# api_host/api_key; this only controls whether root metadata initializes the
# browser client.
config :storyarn, :posthog_frontend,
  frontend_enabled: false,
  error_tracking_enabled: false

config :storyarn, :scopes,
  user: [
    default: true,
    module: Storyarn.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Storyarn.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :storyarn, :snapshot_lifecycle,
  hard_delete_snapshot_limit: 1_000,
  stale_build_heartbeat_seconds: 15 * 60

config :storyarn,
  ecto_repos: [Storyarn.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Swoosh API client (needed for Resend in production)
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure tailwind (the version is required)
config :tailwind,
  # Import environment specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  version: "4.1.7",
  storyarn: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

import_config "#{config_env()}.exs"
